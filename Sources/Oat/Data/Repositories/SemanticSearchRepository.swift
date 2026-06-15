import Foundation
import GRDB

struct SemanticMatch {
    let meetingId: Int64
    let chunkText: String
    let score: Float
}

enum SemanticScope {
    case meeting(Int64)
    case folder(Int64)
    case global
}

/// Brute-force cosine similarity search over stored embeddings.
/// At typical meeting-notes scale (< 50 k chunks) a full in-Swift scan
/// runs in well under 20 ms — fast enough for on-demand search.
struct SemanticSearchRepository {
    let database: AppDatabase
    let embedder: Embedder

    func search(_ query: String, in scope: SemanticScope = .global, topK: Int = 10) throws -> [SemanticMatch] {
        let queryVector = embedder.embed(query)
        guard !queryVector.isEmpty else { return [] }

        let candidates = try fetchCandidates(scope: scope)
        guard !candidates.isEmpty else { return [] }

        // Score every chunk; keep one entry per meeting (best chunk wins).
        var best: [Int64: (score: Float, chunk: String)] = [:]
        for record in candidates {
            let vec = record.toFloatArray()
            guard vec.count == queryVector.count else { continue }
            let score = VectorMath.cosineSimilarity(queryVector, vec)
            if score > (best[record.meetingId]?.score ?? -Float.infinity) {
                best[record.meetingId] = (score: score, chunk: record.chunkText)
            }
        }

        return best
            .map { (meetingId, pair) in SemanticMatch(meetingId: meetingId, chunkText: pair.chunk, score: pair.score) }
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0 }
    }

    private func fetchCandidates(scope: SemanticScope) throws -> [EmbeddingRecord] {
        try database.dbWriter.read { db in
            switch scope {
            case .meeting(let meetingId):
                return try EmbeddingRecord
                    .filter(Column("meetingId") == meetingId)
                    .fetchAll(db)
            case .folder(let folderId):
                let ids = try Int64.fetchAll(
                    db, sql: "SELECT id FROM meeting WHERE folderId = ?", arguments: [folderId]
                )
                return try EmbeddingRecord
                    .filter(ids.contains(Column("meetingId")))
                    .fetchAll(db)
            case .global:
                return try EmbeddingRecord.fetchAll(db)
            }
        }
    }
}
