import Foundation
import GRDB

struct Attendee: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var meetingId: Int64
    var name: String
    var email: String?

    static let databaseTableName = "attendee"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
