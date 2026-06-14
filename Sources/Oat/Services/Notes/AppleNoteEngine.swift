import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device note enhancement via Apple's Foundation Models framework — used in
/// privacy/offline mode (PLAN.md §3.2). Requires macOS 26 + Apple Intelligence.
///
/// The `canImport` guard lets the project still compile on older SDKs (where the
/// framework is absent); at runtime it throws `.unavailable` if the model isn't
/// usable.
struct AppleNoteEngine: NoteEngine {
    func enhance(rawNotes: String, transcript: String, template: Template?) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let prompt = NotePrompt.build(rawNotes: rawNotes, transcript: transcript, template: template)
            let session = LanguageModelSession(instructions: prompt.system)
            let response = try await session.respond(to: prompt.user)
            return response.content
        }
        #endif
        throw NoteEngineError.unavailable
    }
}

/// Chooses the engine based on the user's settings and the local/cloud split.
enum NoteEngineFactory {
    static let apiKeyKeychainKey = "anthropicAPIKey"

    static func make(privacyMode: Bool, provider: EnhancementProvider) -> NoteEngine {
        if privacyMode || provider == .local {
            return AppleNoteEngine()
        }
        let key = KeychainStore.get(apiKeyKeychainKey) ?? ""
        return ClaudeNoteEngine(apiKey: key)
    }
}
