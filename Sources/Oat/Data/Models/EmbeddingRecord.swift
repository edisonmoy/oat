import Foundation
import GRDB

struct EmbeddingRecord: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var sourceKind: String  // "note" | "transcript"
    var sourceId: Int64
    var meetingId: Int64
    var chunkIndex: Int
    var chunkText: String
    var vector: Data        // 512 × Float32, little-endian IEEE 754

    static let databaseTableName = "embedding"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    init(sourceKind: String, sourceId: Int64, meetingId: Int64,
         chunkIndex: Int, chunkText: String, vector: [Float]) {
        self.id = nil
        self.sourceKind = sourceKind
        self.sourceId = sourceId
        self.meetingId = meetingId
        self.chunkIndex = chunkIndex
        self.chunkText = chunkText
        self.vector = vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    func toFloatArray() -> [Float] {
        vector.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
