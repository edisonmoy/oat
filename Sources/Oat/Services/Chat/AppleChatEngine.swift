import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device streaming Ask-AI via Apple Foundation Models (macOS 26+).
struct AppleChatEngine: ChatEngine {
    func ask(
        _ question: String,
        context: String,
        history: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let system = context.isEmpty
                ? "You are a meeting-notes assistant."
                : "You are a meeting-notes assistant.\n\nContext:\n\(context)"
            let session = LanguageModelSession(instructions: system)
            let stream = session.streamResponse(to: question)
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        for try await partial in stream {
                            continuation.yield(partial.content)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
        #endif
        throw NoteEngineError.unavailable
    }
}
