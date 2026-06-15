import Foundation
import GRDB

struct ChatRepository {
    let database: AppDatabase

    @discardableResult
    func insert(_ message: ChatMessage) throws -> ChatMessage {
        try database.dbWriter.write { db in
            var msg = message
            try msg.insert(db)
            return msg
        }
    }

    func messages(scopeKind: String, scopeId: Int64?) throws -> [ChatMessage] {
        try database.dbWriter.read { db in
            try ChatMessage
                .filter(Column("scopeKind") == scopeKind && Column("scopeId") == scopeId)
                .order(Column("createdAt"))
                .fetchAll(db)
        }
    }

    func deleteAll(scopeKind: String, scopeId: Int64?) throws {
        try database.dbWriter.write { db in
            try ChatMessage
                .filter(Column("scopeKind") == scopeKind && Column("scopeId") == scopeId)
                .deleteAll(db)
        }
    }
}
