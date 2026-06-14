import Foundation
import GRDB

struct Folder: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var parentId: Int64?

    static let databaseTableName = "folder"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
