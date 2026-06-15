import Foundation
import GRDB

struct Recording: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var meetingId: Int64
    var micPath: String?
    var systemPath: String?
    var duration: Double?
    var startedAt: Date

    static let databaseTableName = "recording"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
