import Foundation
import GRDB

struct MeetingRepository {
    let database: AppDatabase

    @discardableResult
    func create(title: String = "Untitled meeting") throws -> Meeting {
        try database.dbWriter.write { db in
            var meeting = Meeting(
                id: nil,
                title: title,
                startedAt: Date(),
                endedAt: nil,
                templateId: nil,
                folderId: nil,
                language: nil
            )
            try meeting.insert(db)
            return meeting
        }
    }

    func all() throws -> [Meeting] {
        try database.dbWriter.read { db in
            try Meeting.order(Column("startedAt").desc).fetchAll(db)
        }
    }

    func updateTitle(_ id: Int64, title: String) throws {
        try database.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE meeting SET title = ? WHERE id = ?",
                arguments: [title, id]
            )
        }
    }

    func setFolder(_ id: Int64, folderId: Int64?) throws {
        try database.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE meeting SET folderId = ? WHERE id = ?",
                arguments: [folderId, id]
            )
        }
    }

    func delete(_ id: Int64) throws {
        try database.dbWriter.write { db in
            _ = try Meeting.deleteOne(db, key: id)
        }
    }
}
