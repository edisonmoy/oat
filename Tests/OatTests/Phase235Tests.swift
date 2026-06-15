import XCTest
import GRDB
@testable import Oat

// MARK: - RecordingRepository

final class RecordingRepositoryTests: XCTestCase {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    func testCreateAndFetch() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let recordings = RecordingRepository(database: db)

        let meeting = try meetings.create(title: "Weekly sync")
        let rec = try recordings.create(meetingId: meeting.id!, micPath: "mic.caf", systemPath: "system.caf")
        XCTAssertNotNil(rec.id)
        XCTAssertEqual(try recordings.forMeeting(meeting.id!).count, 1)
    }

    func testUpdateDuration() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let recordings = RecordingRepository(database: db)

        let meeting = try meetings.create()
        let rec = try recordings.create(meetingId: meeting.id!, micPath: nil, systemPath: nil)
        try recordings.updateDuration(rec.id!, duration: 42.5)

        let fetched = try recordings.forMeeting(meeting.id!).first
        XCTAssertEqual(fetched?.duration, 42.5)
    }

    func testDelete() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let recordings = RecordingRepository(database: db)

        let meeting = try meetings.create()
        let rec = try recordings.create(meetingId: meeting.id!, micPath: nil, systemPath: nil)
        try recordings.delete(rec.id!)
        XCTAssertTrue(try recordings.forMeeting(meeting.id!).isEmpty)
    }

    func testCascadeDeleteWithMeeting() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let recordings = RecordingRepository(database: db)

        let meeting = try meetings.create()
        let id = meeting.id!
        try recordings.create(meetingId: id, micPath: nil, systemPath: nil)
        try meetings.delete(id)
        XCTAssertTrue(try recordings.forMeeting(id).isEmpty)
    }
}

// MARK: - TranscriptRepository

final class TranscriptRepositoryTests: XCTestCase {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    private func seg(meetingId: Int64, speaker: String, start: Double, end: Double, text: String) -> TranscriptSegmentRecord {
        TranscriptSegmentRecord(meetingId: meetingId, speaker: speaker, startTime: start, endTime: end, text: text)
    }

    func testInsertAndFetch() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let repo = TranscriptRepository(database: db)

        let meeting = try meetings.create()
        let id = meeting.id!
        _ = try repo.insert(seg(meetingId: id, speaker: "me", start: 0, end: 1, text: "Hello"))
        _ = try repo.insert(seg(meetingId: id, speaker: "them", start: 1, end: 2, text: "Hi there"))

        let segs = try repo.forMeeting(id)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].speaker, "me")
        XCTAssertEqual(segs[1].speaker, "them")
    }

    func testInsertAll() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let repo = TranscriptRepository(database: db)

        let meeting = try meetings.create()
        let id = meeting.id!
        try repo.insertAll([
            seg(meetingId: id, speaker: "me", start: 0, end: 1, text: "One"),
            seg(meetingId: id, speaker: "them", start: 1, end: 2, text: "Two"),
            seg(meetingId: id, speaker: "me", start: 2, end: 3, text: "Three")
        ])
        XCTAssertEqual(try repo.forMeeting(id).count, 3)
    }

    func testDeleteForMeeting() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let repo = TranscriptRepository(database: db)

        let meeting = try meetings.create()
        let id = meeting.id!
        try repo.insertAll([
            seg(meetingId: id, speaker: "me", start: 0, end: 1, text: "Hello"),
            seg(meetingId: id, speaker: "them", start: 1, end: 2, text: "World")
        ])
        try repo.deleteForMeeting(id)
        XCTAssertTrue(try repo.forMeeting(id).isEmpty)
    }

    func testSegmentsOrderedByStartTime() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let repo = TranscriptRepository(database: db)

        let meeting = try meetings.create()
        let id = meeting.id!
        // Insert out-of-order
        try repo.insertAll([
            seg(meetingId: id, speaker: "them", start: 5, end: 6, text: "Last"),
            seg(meetingId: id, speaker: "me", start: 0, end: 1, text: "First"),
            seg(meetingId: id, speaker: "them", start: 2, end: 3, text: "Middle")
        ])
        let ordered = try repo.forMeeting(id)
        XCTAssertEqual(ordered.map(\.text), ["First", "Middle", "Last"])
    }
}

// MARK: - AttendeeRepository

final class AttendeeRepositoryTests: XCTestCase {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    func testInsertAndFetch() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let repo = AttendeeRepository(database: db)

        let meeting = try meetings.create()
        let id = meeting.id!
        let att = try repo.insert(Attendee(id: nil, meetingId: id, name: "Alice", email: "alice@example.com"))
        XCTAssertNotNil(att.id)

        let fetched = try repo.forMeeting(id)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Alice")
        XCTAssertEqual(fetched.first?.email, "alice@example.com")
    }

    func testReplaceAllClearsExisting() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let repo = AttendeeRepository(database: db)

        let meeting = try meetings.create()
        let id = meeting.id!
        try repo.insert(Attendee(id: nil, meetingId: id, name: "Old", email: nil))

        let newAttendees = [
            Attendee(id: nil, meetingId: id, name: "Alice", email: nil),
            Attendee(id: nil, meetingId: id, name: "Bob", email: nil)
        ]
        try repo.replaceAll(for: id, attendees: newAttendees)

        let fetched = try repo.forMeeting(id)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched.map(\.name), ["Alice", "Bob"]) // sorted by name
    }

    func testForMeetingReturnsEmptyWhenNone() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let repo = AttendeeRepository(database: db)

        let meeting = try meetings.create()
        XCTAssertTrue(try repo.forMeeting(meeting.id!).isEmpty)
    }
}

// MARK: - TranscriptSegmentRecord model

final class TranscriptSegmentRecordTests: XCTestCase {
    func testDidInsertSetsId() throws {
        let db = try AppDatabase(DatabaseQueue())
        let meetings = MeetingRepository(database: db)
        let repo = TranscriptRepository(database: db)

        let meeting = try meetings.create()
        var seg = TranscriptSegmentRecord(meetingId: meeting.id!, speaker: "me", startTime: 0, endTime: 1, text: "hi")
        XCTAssertNil(seg.id)
        seg = try repo.insert(seg)
        XCTAssertNotNil(seg.id)
    }
}

// MARK: - Recording model

final class RecordingModelTests: XCTestCase {
    func testDidInsertSetsId() throws {
        let db = try AppDatabase(DatabaseQueue())
        let meetings = MeetingRepository(database: db)
        let recordings = RecordingRepository(database: db)

        let meeting = try meetings.create()
        let rec = try recordings.create(meetingId: meeting.id!, micPath: nil, systemPath: nil)
        XCTAssertNotNil(rec.id)
    }
}

// MARK: - Attendee model

final class AttendeeModelTests: XCTestCase {
    func testDidInsertSetsId() throws {
        let db = try AppDatabase(DatabaseQueue())
        let meetings = MeetingRepository(database: db)
        let repo = AttendeeRepository(database: db)

        let meeting = try meetings.create()
        let att = try repo.insert(Attendee(id: nil, meetingId: meeting.id!, name: "Z", email: nil))
        XCTAssertNotNil(att.id)
    }
}

// MARK: - Meeting calendarEventId

final class MeetingCalendarTests: XCTestCase {
    func testCalendarEventIdPersists() throws {
        let db = try AppDatabase(DatabaseQueue())
        let repo = MeetingRepository(database: db)

        var meeting = try repo.create(title: "Sprint review")
        meeting.calendarEventId = "ek-abc-123"
        try db.dbWriter.write { try meeting.update($0) }

        let fetched = try repo.all().first
        XCTAssertEqual(fetched?.calendarEventId, "ek-abc-123")
    }
}

// MARK: - SearchRepository covers transcript segments

final class TranscriptSearchTests: XCTestCase {
    func testSearchFindsTranscriptText() throws {
        let db = try AppDatabase(DatabaseQueue())
        let meetings = MeetingRepository(database: db)
        let transcripts = TranscriptRepository(database: db)
        let search = SearchRepository(database: db)

        let meeting = try meetings.create(title: "Product review")
        let id = meeting.id!
        try transcripts.insert(
            TranscriptSegmentRecord(meetingId: id, speaker: "them", startTime: 0, endTime: 2, text: "quarterly roadmap discussion")
        )

        let results = try search.search("roadmap")
        XCTAssertTrue(results.contains(where: { $0.id == id }))
    }
}

// MARK: - TranscriptionError

final class TranscriptionErrorTests: XCTestCase {
    func testErrorDescriptions() {
        XCTAssertTrue(TranscriptionError.modelNotLoaded.errorDescription!.contains("model"))
        XCTAssertTrue(TranscriptionError.noResults.errorDescription!.contains("No transcription"))
    }
}
