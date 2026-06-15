import XCTest
import GRDB
@testable import Oat

// MARK: - ChatRepository

final class ChatRepositoryTests: XCTestCase {
    private func makeDB() throws -> AppDatabase { try AppDatabase(DatabaseQueue()) }

    func testInsertAndFetchByScope() throws {
        let db = try makeDB()
        let repo = ChatRepository(database: db)
        let meetings = MeetingRepository(database: db)
        let meeting = try meetings.create()
        let id = meeting.id

        let msg = ChatMessage(
            id: nil, scopeKind: "meeting", scopeId: id,
            role: "user", content: "Hello?", createdAt: Date()
        )
        let saved = try repo.insert(msg)
        XCTAssertNotNil(saved.id)

        let fetched = try repo.messages(scopeKind: "meeting", scopeId: id)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.content, "Hello?")
        XCTAssertEqual(fetched.first?.role, "user")
    }

    func testScopesAreIsolated() throws {
        let db = try makeDB()
        let repo = ChatRepository(database: db)

        try repo.insert(ChatMessage(id: nil, scopeKind: "meeting", scopeId: 1, role: "user", content: "A", createdAt: Date()))
        try repo.insert(ChatMessage(id: nil, scopeKind: "meeting", scopeId: 2, role: "user", content: "B", createdAt: Date()))

        let scope1 = try repo.messages(scopeKind: "meeting", scopeId: 1)
        XCTAssertEqual(scope1.count, 1)
        XCTAssertEqual(scope1.first?.content, "A")
    }

    func testGlobalScopeHasNilId() throws {
        let db = try makeDB()
        let repo = ChatRepository(database: db)

        try repo.insert(ChatMessage(id: nil, scopeKind: "global", scopeId: nil, role: "assistant", content: "Hi", createdAt: Date()))
        let msgs = try repo.messages(scopeKind: "global", scopeId: nil)
        XCTAssertEqual(msgs.count, 1)
    }

    func testDeleteAll() throws {
        let db = try makeDB()
        let repo = ChatRepository(database: db)

        try repo.insert(ChatMessage(id: nil, scopeKind: "meeting", scopeId: 1, role: "user", content: "X", createdAt: Date()))
        try repo.insert(ChatMessage(id: nil, scopeKind: "meeting", scopeId: 1, role: "assistant", content: "Y", createdAt: Date()))
        try repo.deleteAll(scopeKind: "meeting", scopeId: 1)

        XCTAssertTrue(try repo.messages(scopeKind: "meeting", scopeId: 1).isEmpty)
    }

    func testMessagesOrderedByCreatedAt() throws {
        let db = try makeDB()
        let repo = ChatRepository(database: db)
        let now = Date()

        try repo.insert(ChatMessage(id: nil, scopeKind: "global", scopeId: nil, role: "user", content: "First", createdAt: now))
        try repo.insert(ChatMessage(id: nil, scopeKind: "global", scopeId: nil, role: "assistant", content: "Second", createdAt: now.addingTimeInterval(1)))
        let msgs = try repo.messages(scopeKind: "global", scopeId: nil)
        XCTAssertEqual(msgs.map(\.content), ["First", "Second"])
    }
}

// MARK: - ChatMessage model

final class ChatMessageModelTests: XCTestCase {
    func testDidInsertSetsId() throws {
        let db = try AppDatabase(DatabaseQueue())
        let repo = ChatRepository(database: db)
        let msg = try repo.insert(ChatMessage(
            id: nil, scopeKind: "global", scopeId: nil,
            role: "user", content: "test", createdAt: Date()
        ))
        XCTAssertNotNil(msg.id)
    }

    func testScopeKindRawValues() {
        XCTAssertEqual(ChatMessage.ScopeKind.meeting.rawValue, "meeting")
        XCTAssertEqual(ChatMessage.ScopeKind.folder.rawValue, "folder")
        XCTAssertEqual(ChatMessage.ScopeKind.global.rawValue, "global")
    }

    func testRoleRawValues() {
        XCTAssertEqual(ChatMessage.Role.user.rawValue, "user")
        XCTAssertEqual(ChatMessage.Role.assistant.rawValue, "assistant")
    }
}

// MARK: - ContextBuilder

final class ContextBuilderTests: XCTestCase {
    private func meeting(_ id: Int64, title: String) -> Meeting {
        Meeting(id: id, title: title, startedAt: Date(timeIntervalSince1970: 0),
                endedAt: nil, templateId: nil, folderId: nil, language: nil, calendarEventId: nil)
    }

    func testEmptyChunksReturnsEmptyContext() {
        let ctx = ContextBuilder().buildContext(query: "q", chunks: [], meetings: [])
        XCTAssertTrue(ctx.isEmpty)
    }

    func testSingleChunkIncludesMeetingTitle() {
        let match = SemanticMatch(meetingId: 1, chunkText: "discussed the budget", score: 0.9)
        let meetings = [meeting(1, title: "Budget review")]
        let ctx = ContextBuilder().buildContext(query: "q", chunks: [match], meetings: meetings)
        XCTAssertTrue(ctx.contains("Budget review"))
        XCTAssertTrue(ctx.contains("discussed the budget"))
    }

    func testTruncatesAtMaxContextChars() {
        let longChunk = String(repeating: "x", count: 500)
        let matches = (1...10).map { SemanticMatch(meetingId: Int64($0), chunkText: longChunk, score: Float($0)) }
        let meetings = (1...10).map { meeting(Int64($0), title: "M\($0)") }
        let ctx = ContextBuilder(maxContextChars: 1_000).buildContext(query: "q", chunks: matches, meetings: meetings)
        XCTAssertLessThanOrEqual(ctx.count, 1_000 + 100) // small slack for header overhead
    }

    func testChunkWithoutMatchingMeetingIsSkipped() {
        let match = SemanticMatch(meetingId: 99, chunkText: "orphan chunk", score: 0.9)
        let ctx = ContextBuilder().buildContext(query: "q", chunks: [match], meetings: [])
        XCTAssertTrue(ctx.isEmpty)
    }

    func testMultipleChunksOrderedByInputOrder() {
        let matches = [
            SemanticMatch(meetingId: 1, chunkText: "first chunk", score: 0.9),
            SemanticMatch(meetingId: 2, chunkText: "second chunk", score: 0.7)
        ]
        let meetings = [meeting(1, title: "Alpha"), meeting(2, title: "Beta")]
        let ctx = ContextBuilder().buildContext(query: "q", chunks: matches, meetings: meetings)
        let alphaPos = ctx.range(of: "Alpha")!.lowerBound
        let betaPos = ctx.range(of: "Beta")!.lowerBound
        XCTAssertLessThan(alphaPos, betaPos)
    }
}
