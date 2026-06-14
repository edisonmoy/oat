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

    func testFolderAssignment() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let folders = FolderRepository(database: db)

        let folder = try folders.create(name: "Sales")
        let meeting = try meetings.create()
        try meetings.setFolder(meeting.id!, folderId: folder.id)

        let fetched = try meetings.all().first
        XCTAssertEqual(fetched?.folderId, folder.id)
    }

    func testFullTextSearchMatchesTitleAndNotes() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let notes = NoteRepository(database: db)
        let search = SearchRepository(database: db)

        let budget = try meetings.create(title: "Budget review")
        let other = try meetings.create(title: "Roadmap sync")
        try notes.saveRawNote(meetingId: other.id!, markdown: "discussed the budget line items")

        // Title match.
        XCTAssertEqual(try search.search("review").map(\.id), [budget.id])
        // Note-body match returns the meeting that owns the note.
        XCTAssertTrue(try search.search("line items").map(\.id).contains(other.id))
        // Both meetings mention "budget".
        XCTAssertEqual(Set(try search.search("budget").compactMap(\.id)), Set([budget.id!, other.id!]))
    }

    func testDefaultTemplatesAreSeededOnce() throws {
        let db = try makeDatabase()
        let templates = TemplateRepository(database: db)

        try templates.seedDefaultsIfEmpty()
        let first = try templates.all().count
        XCTAssertEqual(first, TemplateRepository.defaults.count)

        // Idempotent: seeding again does nothing.
        try templates.seedDefaultsIfEmpty()
        XCTAssertEqual(try templates.all().count, first)
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
