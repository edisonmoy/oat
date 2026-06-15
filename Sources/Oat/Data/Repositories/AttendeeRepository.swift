import Foundation
import GRDB

struct AttendeeRepository {
    let database: AppDatabase

    @discardableResult
    func insert(_ attendee: Attendee) throws -> Attendee {
        try database.dbWriter.write { db in
            var att = attendee
            try att.insert(db)
            return att
        }
    }

    func replaceAll(for meetingId: Int64, attendees: [Attendee]) throws {
        try database.dbWriter.write { db in
            try Attendee.filter(Column("meetingId") == meetingId).deleteAll(db)
            for var att in attendees {
                try att.insert(db)
            }
        }
    }

    func forMeeting(_ meetingId: Int64) throws -> [Attendee] {
        try database.dbWriter.read { db in
            try Attendee
                .filter(Column("meetingId") == meetingId)
                .order(Column("name"))
                .fetchAll(db)
        }
    }
}
