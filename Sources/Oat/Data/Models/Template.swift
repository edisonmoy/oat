import Foundation
import GRDB

struct Template: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var systemPrompt: String
    var outputSchema: String?

    static let databaseTableName = "template"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
