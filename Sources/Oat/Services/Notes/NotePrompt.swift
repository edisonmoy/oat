import Foundation

/// Builds the system + user prompt that turns rough notes into clean notes
/// (PLAN.md §1.4). Pure and provider-agnostic so both the Claude and Apple
/// engines share identical prompting.
enum NotePrompt {
    static func build(rawNotes: String, transcript: String, template: Template?) -> (system: String, user: String) {
        let system = template?.systemPrompt ?? """
        You turn a user's rough meeting notes into clean, well-structured notes. \
        Use the transcript to add accurate detail and context the user didn't \
        capture, but stay faithful — never invent facts, names, or numbers. \
        Preserve the user's intent and emphasis. Output GitHub-flavored Markdown \
        with clear headings and an "Action items" section when relevant.
        """

        let transcriptSection = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(No transcript available — work from the notes alone.)"
            : transcript

        let user = """
        # My rough notes
        \(rawNotes.isEmpty ? "(none)" : rawNotes)

        # Transcript
        \(transcriptSection)

        Produce the enhanced notes now.
        """

        return (system, user)
    }
}

enum NoteEngineError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case api(status: Int, message: String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Anthropic API key in Settings to use cloud enhancement."
        case .invalidResponse:
            return "Unexpected response from the server."
        case .api(let status, let message):
            return "API error \(status): \(message)"
        case .unavailable:
            return "On-device enhancement needs macOS 26 with Apple Intelligence."
        }
    }
}
