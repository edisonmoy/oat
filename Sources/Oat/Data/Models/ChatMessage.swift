import Foundation
import GRDB

struct ChatMessage: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    enum ScopeKind: String, Codable { case meeting, folder, global }
    enum Role: String, Codable { case user, assistant }

    var id: Int64?
    var scopeKind: String
    var scopeId: Int64?
    var role: String
    var content: String
    var createdAt: Date

    static let databaseTableName = "chatMessage"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
