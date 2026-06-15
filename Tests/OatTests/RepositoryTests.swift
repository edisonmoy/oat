import XCTest
import GRDB
@testable import Oat

final class RepositoryTests: XCTestCase {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    // MARK: - FolderRepository

    func testFolderAllReturnsSortedByName() throws {
        let db = try makeDatabase()
        let folders = FolderRepository(database: db)

        XCTAssertTrue(try folders.all().isEmpty)
        try folders.create(name: "Zebra")
        try folders.create(name: "Alpha")
        let all = try folders.all()
        XCTAssertEqual(all.map(\.name), ["Alpha", "Zebra"])
    }

    func testFolderDelete() throws {
        let db = try makeDatabase()
        let folders = FolderRepository(database: db)

        let folder = try folders.create(name: "Delete Me")
        XCTAssertEqual(try folders.all().count, 1)
        try folders.delete(folder.id!)
        XCTAssertTrue(try folders.all().isEmpty)
    }

    // MARK: - SearchRepository

    func testSearchEmptyQueryReturnsEmpty() throws {
        let db = try makeDatabase()
        let search = SearchRepository(database: db)

        XCTAssertTrue(try search.search("").isEmpty)
        XCTAssertTrue(try search.search("   ").isEmpty)
    }

    func testSearchNoMatchesReturnsEmpty() throws {
        let db = try makeDatabase()
        let meetings = MeetingRepository(database: db)
        let search = SearchRepository(database: db)

        try meetings.create(title: "Product review")
        XCTAssertTrue(try search.search("xyzzy").isEmpty)
    }

    // MARK: - TemplateRepository

    func testTemplateAllAfterSeed() throws {
        let db = try makeDatabase()
        let templates = TemplateRepository(database: db)

        XCTAssertTrue(try templates.all().isEmpty)
        try templates.seedDefaultsIfEmpty()
        XCTAssertEqual(try templates.all().count, TemplateRepository.defaults.count)
    }
}
