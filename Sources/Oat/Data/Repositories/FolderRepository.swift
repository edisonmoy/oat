import Foundation
import GRDB

struct FolderRepository {
    let database: AppDatabase

    @discardableResult
    func create(name: String) throws -> Folder {
        try database.dbWriter.write { db in
            var folder = Folder(id: nil, name: name, parentId: nil)
            try folder.insert(db)
            return folder
        }
    }

    func all() throws -> [Folder] {
        try database.dbWriter.read { db in
            try Folder.order(Column("name")).fetchAll(db)
        }
    }

    func delete(_ id: Int64) throws {
        try database.dbWriter.write { db in
            _ = try Folder.deleteOne(db, key: id)
        }
    }
}
