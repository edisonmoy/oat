import Foundation

/// Orchestrates chunking text and writing embeddings to the database.
/// Called after note saves and after transcription completes.
struct EmbeddingService {
    let embedder: Embedder
    let repository: EmbeddingRepository

    // MARK: - Indexing

    func indexNote(_ note: Note) throws {
        guard let noteId = note.id else { return }
        let text = note.contentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            try repository.deleteForSource(kind: "note", sourceId: noteId)
            return
        }
        let records = chunk(text, maxChars: 500).enumerated().compactMap { (i, chunk) -> EmbeddingRecord? in
            let vec = embedder.embed(chunk)
            guard !vec.isEmpty else { return nil }
            return EmbeddingRecord(
                sourceKind: "note", sourceId: noteId,
                meetingId: note.meetingId, chunkIndex: i,
                chunkText: chunk, vector: vec
            )
        }
        try repository.replaceAll(sourceKind: "note", sourceId: noteId, records: records)
    }

    func indexTranscriptSegments(_ segments: [TranscriptSegmentRecord], meetingId: Int64) throws {
        try repository.deleteForSource(kind: "transcript", sourceId: meetingId)
        let grouped = groupSegments(segments, maxChars: 300)
        let records = grouped.enumerated().compactMap { (i, pair) -> EmbeddingRecord? in
            let vec = embedder.embed(pair.text)
            guard !vec.isEmpty else { return nil }
            return EmbeddingRecord(
                sourceKind: "transcript", sourceId: pair.anchorId,
                meetingId: meetingId, chunkIndex: i,
                chunkText: pair.text, vector: vec
            )
        }
        try repository.replaceAll(sourceKind: "transcript", sourceId: meetingId, records: records)
    }

    // MARK: - Chunking

    /// Splits text into chunks of at most `maxChars` characters, breaking at
    /// paragraph boundaries first, then sentence boundaries.
    func chunk(_ text: String, maxChars: Int) -> [String] {
        guard !text.isEmpty, maxChars > 0 else { return [] }
        let paragraphs = text.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var current = ""
        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if current.isEmpty {
                current = trimmed
            } else if current.count + 2 + trimmed.count <= maxChars {
                current += "\n\n" + trimmed
            } else {
                chunks.append(current)
                if trimmed.count <= maxChars {
                    current = trimmed
                } else {
                    // Break long paragraph at sentence boundaries
                    current = ""
                    for sentence in trimmed.components(separatedBy: ". ") {
                        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !s.isEmpty else { continue }
                        if current.isEmpty {
                            current = s
                        } else if current.count + 2 + s.count <= maxChars {
                            current += ". " + s
                        } else {
                            chunks.append(current)
                            current = s
                        }
                    }
                }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - Helpers

    private func groupSegments(
        _ segments: [TranscriptSegmentRecord],
        maxChars: Int
    ) -> [(anchorId: Int64, text: String)] {
        var result: [(anchorId: Int64, text: String)] = []
        var current = ""
        var anchorId: Int64 = 0
        for seg in segments {
            guard let segId = seg.id else { continue }
            if current.isEmpty {
                current = seg.text
                anchorId = segId
            } else if current.count + 1 + seg.text.count <= maxChars {
                current += " " + seg.text
            } else {
                result.append((anchorId: anchorId, text: current))
                current = seg.text
                anchorId = segId
            }
        }
        if !current.isEmpty { result.append((anchorId: anchorId, text: current)) }
        return result
    }
}
