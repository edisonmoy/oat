import Foundation
import GRDB

struct NoteRepository {
    let database: AppDatabase

    /// Returns the raw note for a meeting, creating an empty one if needed.
    func rawNote(for meetingId: Int64) throws -> Note {
        try database.dbWriter.write { db in
            if let existing = try Note
                .filter(Column("meetingId") == meetingId && Column("kind") == Note.Kind.raw.rawValue)
                .fetchOne(db) {
                return existing
            }
            var note = Note(
                id: nil,
                meetingId: meetingId,
                kind: Note.Kind.raw.rawValue,
                contentMarkdown: "",
                updatedAt: Date()
            )
            try note.insert(db)
            return note
        }
    }

    /// Upserts the raw note content for a meeting.
    func saveRawNote(meetingId: Int64, markdown: String) throws {
        try database.dbWriter.write { db in
            if var note = try Note
                .filter(Column("meetingId") == meetingId && Column("kind") == Note.Kind.raw.rawValue)
                .fetchOne(db) {
                note.contentMarkdown = markdown
                note.updatedAt = Date()
                try note.update(db)
            } else {
                var note = Note(
                    id: nil,
                    meetingId: meetingId,
                    kind: Note.Kind.raw.rawValue,
                    contentMarkdown: markdown,
                    updatedAt: Date()
                )
                try note.insert(db)
            }
        }
    }
}
