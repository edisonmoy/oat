import Foundation
import GRDB

struct Meeting: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var templateId: Int64?
    var folderId: Int64?
    var language: String?

    static let databaseTableName = "meeting"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
