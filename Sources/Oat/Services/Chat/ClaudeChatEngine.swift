import Foundation

/// Streaming Ask-AI via the Anthropic Messages API (SSE).
struct ClaudeChatEngine: ChatEngine {
    var apiKey: String
    var model: String = "claude-haiku-4-5"
    var urlSession: URLSession = .shared

    func ask(
        _ question: String,
        context: String,
        history: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard !apiKey.isEmpty else { throw NoteEngineError.missingAPIKey }

        let system = buildSystem(context: context)
        var messages = history.map { ["role": $0.role, "content": $0.content] }
        messages.append(["role": "user", "content": question])

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "stream": true,
            "system": system,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw NoteEngineError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw NoteEngineError.api(status: http.statusCode, message: "")
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var buffer = ""
                    for try await byte in bytes {
                        buffer.append(Character(UnicodeScalar(byte)))
                        while let range = buffer.range(of: "\n\n") {
                            let event = String(buffer[buffer.startIndex..<range.lowerBound])
                            buffer = String(buffer[range.upperBound...])
                            if let text = Self.parseDelta(from: event) {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildSystem(context: String) -> String {
        var system = """
        You are a meeting-notes assistant. Answer the user's question using only the \
        provided meeting excerpts. Cite the meeting title when quoting. \
        If the answer isn't in the excerpts, say so.
        """
        if !context.isEmpty { system += "\n\nContext:\n" + context }
        return system
    }

    private static func parseDelta(from event: String) -> String? {
        guard event.contains("content_block_delta") else { return nil }
        for line in event.components(separatedBy: "\n") {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let delta = obj["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { continue }
            return text
        }
        return nil
    }
}
