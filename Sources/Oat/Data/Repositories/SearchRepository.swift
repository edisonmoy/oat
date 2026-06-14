import Foundation
import GRDB

/// Full-text search across meeting titles and note bodies (PLAN.md Phase 6 brings
/// semantic search on top of this keyword layer).
struct SearchRepository {
    let database: AppDatabase

    func search(_ query: String) throws -> [Meeting] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let pattern = FTS5Pattern(matchingAllTokensIn: trimmed) else {
            return []
        }

        return try database.dbWriter.read { db in
            let titleMatches = try Int64.fetchAll(db, sql: """
                SELECT m.id FROM meeting m
                JOIN meeting_ft ON meeting_ft.rowid = m.id
                WHERE meeting_ft MATCH ?
                """, arguments: [pattern])

            let noteMatches = try Int64.fetchAll(db, sql: """
                SELECT n.meetingId FROM note n
                JOIN note_ft ON note_ft.rowid = n.id
                WHERE note_ft MATCH ?
                """, arguments: [pattern])

            let ids = Array(Set(titleMatches + noteMatches))
            guard !ids.isEmpty else { return [] }

            return try Meeting
                .filter(ids.contains(Column("id")))
                .order(Column("startedAt").desc)
                .fetchAll(db)
        }
    }
}
