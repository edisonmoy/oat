import Foundation
import GRDB

struct RecordingRepository {
    let database: AppDatabase

    @discardableResult
    func create(meetingId: Int64, micPath: String?, systemPath: String?) throws -> Recording {
        try database.dbWriter.write { db in
            var rec = Recording(
                id: nil,
                meetingId: meetingId,
                micPath: micPath,
                systemPath: systemPath,
                duration: nil,
                startedAt: Date()
            )
            try rec.insert(db)
            return rec
        }
    }

    func forMeeting(_ meetingId: Int64) throws -> [Recording] {
        try database.dbWriter.read { db in
            try Recording
                .filter(Column("meetingId") == meetingId)
                .order(Column("startedAt").desc)
                .fetchAll(db)
        }
    }

    func updateDuration(_ id: Int64, duration: Double) throws {
        try database.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE recording SET duration = ? WHERE id = ?",
                arguments: [duration, id]
            )
        }
    }

    func delete(_ id: Int64) throws {
        try database.dbWriter.write { db in
            _ = try Recording.deleteOne(db, key: id)
        }
    }
}
