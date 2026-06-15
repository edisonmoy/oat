import Foundation

enum ChatEngineFactory {
    static func make(privacyMode: Bool, provider: EnhancementProvider) -> ChatEngine {
        if privacyMode || provider == .local {
            return AppleChatEngine()
        }
        let key = KeychainStore.get(NoteEngineFactory.apiKeyKeychainKey) ?? ""
        return ClaudeChatEngine(apiKey: key)
    }
}
