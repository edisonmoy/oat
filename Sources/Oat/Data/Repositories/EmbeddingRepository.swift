import Foundation
import GRDB

struct EmbeddingRepository {
    let database: AppDatabase

    /// Atomically replaces all embeddings for a given source (note or transcript chunk).
    func replaceAll(sourceKind: String, sourceId: Int64, records: [EmbeddingRecord]) throws {
        try database.dbWriter.write { db in
            try EmbeddingRecord
                .filter(Column("sourceKind") == sourceKind && Column("sourceId") == sourceId)
                .deleteAll(db)
            for var rec in records {
                try rec.insert(db)
            }
        }
    }

    func deleteForSource(kind: String, sourceId: Int64) throws {
        try database.dbWriter.write { db in
            try EmbeddingRecord
                .filter(Column("sourceKind") == kind && Column("sourceId") == sourceId)
                .deleteAll(db)
        }
    }

    func deleteForMeeting(_ meetingId: Int64) throws {
        try database.dbWriter.write { db in
            try EmbeddingRecord.filter(Column("meetingId") == meetingId).deleteAll(db)
        }
    }

    func allForMeeting(_ meetingId: Int64) throws -> [EmbeddingRecord] {
        try database.dbWriter.read { db in
            try EmbeddingRecord.filter(Column("meetingId") == meetingId).fetchAll(db)
        }
    }

    func all() throws -> [EmbeddingRecord] {
        try database.dbWriter.read { db in
            try EmbeddingRecord.fetchAll(db)
        }
    }
}
