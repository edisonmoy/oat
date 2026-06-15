import Foundation
import GRDB

/// Owns the SQLite connection and schema migrations. The schema here covers the
/// Phase 0–1 core (meetings, notes, folders, templates); later phases add
/// recordings, transcripts, attendees, spaces, etc. (see PLAN.md §4).
final class AppDatabase {
    let dbWriter: any DatabaseWriter

    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // Recreate the database from scratch when the schema changes during development.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_core") { db in
            try db.create(table: "folder") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("parentId", .integer).references("folder", onDelete: .setNull)
            }

            try db.create(table: "template") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("systemPrompt", .text).notNull().defaults(to: "")
                t.column("outputSchema", .text)
            }

            try db.create(table: "meeting") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull().defaults(to: "Untitled meeting")
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("templateId", .integer).references("template", onDelete: .setNull)
                t.column("folderId", .integer).references("folder", onDelete: .setNull)
                t.column("language", .text)
            }

            try db.create(table: "note") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meetingId", .integer).notNull()
                    .references("meeting", onDelete: .cascade)
                t.column("kind", .text).notNull() // "raw" | "enhanced"
                t.column("contentMarkdown", .text).notNull().defaults(to: "")
                t.column("updatedAt", .datetime).notNull()
                t.uniqueKey(["meetingId", "kind"])
            }
        }

        migrator.registerMigration("v2_search") { db in
            try db.create(virtualTable: "meeting_ft", using: FTS5()) { t in
                t.synchronize(withTable: "meeting")
                t.column("title")
            }
            try db.create(virtualTable: "note_ft", using: FTS5()) { t in
                t.synchronize(withTable: "note")
                t.column("contentMarkdown")
            }
        }

        migrator.registerMigration("v3_recordings") { db in
            try db.create(table: "recording") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meetingId", .integer).notNull().references("meeting", onDelete: .cascade)
                t.column("micPath", .text)
                t.column("systemPath", .text)
                t.column("duration", .double)
                t.column("startedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v4_transcripts") { db in
            try db.create(table: "transcriptSegment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meetingId", .integer).notNull().references("meeting", onDelete: .cascade)
                t.column("speaker", .text).notNull()
                t.column("startTime", .double).notNull()
                t.column("endTime", .double).notNull()
                t.column("text", .text).notNull()
            }
            try db.create(virtualTable: "transcriptSegment_ft", using: FTS5()) { t in
                t.synchronize(withTable: "transcriptSegment")
                t.column("text")
            }
        }

        migrator.registerMigration("v5_calendar") { db in
            try db.create(table: "attendee") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meetingId", .integer).notNull().references("meeting", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("email", .text)
            }
            try db.alter(table: "meeting") { t in
                t.add(column: "calendarEventId", .text)
            }
        }

        migrator.registerMigration("v6_embeddings") { db in
            try db.create(table: "embedding") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sourceKind", .text).notNull()
                t.column("sourceId", .integer).notNull()
                t.column("meetingId", .integer).notNull().references("meeting", onDelete: .cascade)
                t.column("chunkIndex", .integer).notNull().defaults(to: 0)
                t.column("chunkText", .text).notNull()
                t.column("vector", .blob).notNull()
                t.uniqueKey(["sourceKind", "sourceId", "chunkIndex"])
            }
            try db.create(index: "embedding_meetingId", on: "embedding", columns: ["meetingId"])
        }

        migrator.registerMigration("v7_chat") { db in
            try db.create(table: "chatMessage") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("scopeKind", .text).notNull()
                t.column("scopeId", .integer)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(
                index: "chatMessage_scope",
                on: "chatMessage",
                columns: ["scopeKind", "scopeId", "createdAt"]
            )
        }

        return migrator
    }
}
