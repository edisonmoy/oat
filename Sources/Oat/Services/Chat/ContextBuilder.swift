import Foundation

/// Builds the context string that accompanies an Ask-AI query.
/// Prepends meeting-titled sections, truncating to `maxContextChars`.
struct ContextBuilder {
    let maxContextChars: Int

    init(maxContextChars: Int = 12_000) {
        self.maxContextChars = maxContextChars
    }

    func buildContext(query: String, chunks: [SemanticMatch], meetings: [Meeting]) -> String {
        let meetingMap = Dictionary(uniqueKeysWithValues: meetings.compactMap { m -> (Int64, Meeting)? in
            guard let id = m.id else { return nil }
            return (id, m)
        })

        var context = ""
        var remaining = maxContextChars

        for match in chunks {
            guard let meeting = meetingMap[match.meetingId] else { continue }
            let header = "--- [\(meeting.title), \(formatDate(meeting.startedAt))] ---"
            let section = "\(header)\n\(match.chunkText)\n\n"
            guard section.count <= remaining else { break }
            context += section
            remaining -= section.count
        }

        return context
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
