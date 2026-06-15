import Foundation
import GRDB

struct TranscriptSegmentRecord: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var meetingId: Int64
    var speaker: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String

    static let databaseTableName = "transcriptSegment"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
