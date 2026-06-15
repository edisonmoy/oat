import Foundation
import GRDB

struct TranscriptRepository {
    let database: AppDatabase

    func insert(_ segment: TranscriptSegmentRecord) throws -> TranscriptSegmentRecord {
        try database.dbWriter.write { db in
            var seg = segment
            try seg.insert(db)
            return seg
        }
    }

    func insertAll(_ segments: [TranscriptSegmentRecord]) throws {
        try database.dbWriter.write { db in
            for var seg in segments {
                try seg.insert(db)
            }
        }
    }

    func forMeeting(_ meetingId: Int64) throws -> [TranscriptSegmentRecord] {
        try database.dbWriter.read { db in
            try TranscriptSegmentRecord
                .filter(Column("meetingId") == meetingId)
                .order(Column("startTime"))
                .fetchAll(db)
        }
    }

    func deleteForMeeting(_ meetingId: Int64) throws {
        try database.dbWriter.write { db in
            try TranscriptSegmentRecord
                .filter(Column("meetingId") == meetingId)
                .deleteAll(db)
        }
    }
}
