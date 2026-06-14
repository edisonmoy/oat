import Foundation
import GRDB

struct Note: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    /// A note is either the user's `raw` jottings or the AI `enhanced` version.
    enum Kind: String, Codable {
        case raw
        case enhanced
    }

    var id: Int64?
    var meetingId: Int64
    var kind: String
    var contentMarkdown: String
    var updatedAt: Date

    static let databaseTableName = "note"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
