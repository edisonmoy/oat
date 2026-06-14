import Foundation

/// Cloud note enhancement via the Anthropic Messages API — the default per the
/// local/cloud split (PLAN.md §3.2). Only text leaves the device, never audio.
struct ClaudeNoteEngine: NoteEngine {
    enum Quality {
        case fast   // claude-haiku-4-5
        case best   // claude-sonnet-4-6

        var model: String {
            switch self {
            case .fast: return "claude-haiku-4-5"
            case .best: return "claude-sonnet-4-6"
            }
        }
    }

    var apiKey: String
    var quality: Quality = .best
    var urlSession: URLSession = .shared

    func enhance(rawNotes: String, transcript: String, template: Template?) async throws -> String {
        guard !apiKey.isEmpty else { throw NoteEngineError.missingAPIKey }
        let prompt = NotePrompt.build(rawNotes: rawNotes, transcript: transcript, template: template)

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": quality.model,
            "max_tokens": 2048,
            "system": prompt.system,
            "messages": [["role": "user", "content": prompt.user]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NoteEngineError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw NoteEngineError.api(status: http.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return decoded.content.compactMap(\.text).joined()
    }
}

private struct ClaudeResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]
}
