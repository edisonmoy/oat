import Foundation

protocol ChatEngine {
    func ask(
        _ question: String,
        context: String,
        history: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error>
}
