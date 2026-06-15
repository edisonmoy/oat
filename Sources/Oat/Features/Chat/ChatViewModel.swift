import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    enum Scope {
        case meeting(Meeting)
        case folder(Folder)
        case global

        var kind: String {
            switch self {
            case .meeting: return ChatMessage.ScopeKind.meeting.rawValue
            case .folder:  return ChatMessage.ScopeKind.folder.rawValue
            case .global:  return ChatMessage.ScopeKind.global.rawValue
            }
        }

        var id: Int64? {
            switch self {
            case .meeting(let m): return m.id
            case .folder(let f):  return f.id
            case .global:         return nil
            }
        }

        var semanticScope: SemanticScope {
            switch self {
            case .meeting(let m): return .meeting(m.id ?? 0)
            case .folder(let f):  return .folder(f.id ?? 0)
            case .global:         return .global
            }
        }
    }

    @Published var messages: [ChatMessage] = []
    @Published var isStreaming = false
    @Published var streamingContent = ""
    @Published var error: String?

    let scope: Scope
    private let chatRepo: ChatRepository
    private let semanticRepo: SemanticSearchRepository
    private let contextBuilder: ContextBuilder
    private let engine: ChatEngine
    private let meetingRepo: MeetingRepository
    private var streamTask: Task<Void, Never>?

    init(
        scope: Scope,
        chatRepo: ChatRepository,
        semanticRepo: SemanticSearchRepository,
        contextBuilder: ContextBuilder,
        engine: ChatEngine,
        meetingRepo: MeetingRepository
    ) {
        self.scope = scope
        self.chatRepo = chatRepo
        self.semanticRepo = semanticRepo
        self.contextBuilder = contextBuilder
        self.engine = engine
        self.meetingRepo = meetingRepo
        messages = (try? chatRepo.messages(scopeKind: scope.kind, scopeId: scope.id)) ?? []
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMsg = ChatMessage(
            id: nil, scopeKind: scope.kind, scopeId: scope.id,
            role: ChatMessage.Role.user.rawValue, content: trimmed, createdAt: Date()
        )
        if let saved = try? chatRepo.insert(userMsg) { messages.append(saved) }

        isStreaming = true
        streamingContent = ""
        error = nil

        streamTask = Task {
            do {
                let matches = (try? semanticRepo.search(trimmed, in: scope.semanticScope)) ?? []
                let allMeetings = (try? meetingRepo.all()) ?? []
                let context = contextBuilder.buildContext(query: trimmed, chunks: matches, meetings: allMeetings)
                let stream = try await engine.ask(trimmed, context: context, history: messages)

                for try await token in stream { streamingContent += token }

                let assistantMsg = ChatMessage(
                    id: nil, scopeKind: scope.kind, scopeId: scope.id,
                    role: ChatMessage.Role.assistant.rawValue,
                    content: streamingContent, createdAt: Date()
                )
                if let saved = try? chatRepo.insert(assistantMsg) { messages.append(saved) }
                streamingContent = ""
                isStreaming = false
            } catch {
                self.error = error.localizedDescription
                streamingContent = ""
                isStreaming = false
            }
        }
    }

    func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        streamingContent = ""
        isStreaming = false
    }

    func clear() {
        stopStream()
        try? chatRepo.deleteAll(scopeKind: scope.kind, scopeId: scope.id)
        messages = []
    }
}
