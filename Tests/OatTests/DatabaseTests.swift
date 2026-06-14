import XCTest
import GRDB
@testable import Oat

final class DatabaseTests: XCTestCase {
    private func makeDatabase() throws -> AppDatabase {
        // In-memory database for fast, isolated tests.
        try AppDatabase(DatabaseQueue())
    }

    func testCreateAndFetchMeeting() throws {
        let db = try makeDatabase()
        let repo = MeetingRepository(database: db)

        let created = try repo.create(title: "Standup")
        XCTAssertNotNil(created.id)

        let all = try repo.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Standup")
    }

    func testUpdateTitle() throws {
        let db = try makeDatabase()
        let repo = MeetingRepository(database: db)

        let created = try repo.create()
        try repo.updateTitle(created.id!, title: "Weekly sync")

        XCTAssertEqual(try repo.all().first?.title, "Weekly sync")
    }

    func testDeleteMeeting() throws {
        let db = try makeDatabase()
        let repo = MeetingRepository(database: db)

        let created = try repo.create()
        try repo.delete(created.id!)

        XCTAssertTrue(try repo.all().isEmpty)
    }

    func testRawNoteIsCreatedThenUpdated() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let notes = NoteRepository(database: db)

        let meeting = try meetings.create()
        let id = meeting.id!

        // First access creates an empty raw note.
        XCTAssertEqual(try notes.rawNote(for: id).contentMarkdown, "")

        // Saving updates it in place (no duplicate rows thanks to the unique key).
        try notes.saveRawNote(meetingId: id, markdown: "- ship it")
        XCTAssertEqual(try notes.rawNote(for: id).contentMarkdown, "- ship it")
    }
}
