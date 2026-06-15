import XCTest
import GRDB
@testable import Oat

// MARK: - VectorMath

final class VectorMathTests: XCTestCase {
    func testCosineSimilarityParallel() {
        let a: [Float] = [1, 0, 0]
        XCTAssertEqual(VectorMath.cosineSimilarity(a, a), 1.0, accuracy: 1e-6)
    }

    func testCosineSimilarityAntiParallel() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 0], [-1, 0]), -1.0, accuracy: 1e-6)
    }

    func testCosineSimilarityOrthogonal() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 0], [0, 1]), 0.0, accuracy: 1e-6)
    }

    func testCosineSimilarityMismatchedLengthReturnsZero() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 2], [1]), 0.0)
    }

    func testCosineSimilarityEmptyReturnsZero() {
        XCTAssertEqual(VectorMath.cosineSimilarity([], []), 0.0)
    }

    func testCosineSimilarityZeroVector() {
        XCTAssertEqual(VectorMath.cosineSimilarity([0, 0], [1, 0]), 0.0)
    }

    func testTopKReturnsTopByScore() {
        let input: [(id: Int64, score: Float)] = [(1, 0.3), (2, 0.9), (3, 0.5)]
        let top = VectorMath.topK(input, k: 2)
        XCTAssertEqual(top.map(\.id), [2, 3])
    }

    func testTopKMoreThanAvailable() {
        let input: [(id: Int64, score: Float)] = [(1, 0.5), (2, 0.8)]
        XCTAssertEqual(VectorMath.topK(input, k: 10).count, 2)
    }

    func testTopKEmptyInput() {
        XCTAssertTrue(VectorMath.topK([], k: 5).isEmpty)
    }
}

// MARK: - EmbeddingRecord serialization

final class EmbeddingRecordSerializationTests: XCTestCase {
    func testFloatRoundTrip() {
        let original: [Float] = [0.1, -0.5, 1.0, 0.0, Float.pi]
        let record = EmbeddingRecord(
            sourceKind: "note", sourceId: 1, meetingId: 1,
            chunkIndex: 0, chunkText: "hello", vector: original
        )
        let rt = record.toFloatArray()
        XCTAssertEqual(rt.count, original.count)
        for (a, b) in zip(original, rt) { XCTAssertEqual(a, b, accuracy: 1e-7) }
    }

    func testEmptyVectorRoundTrip() {
        let record = EmbeddingRecord(
            sourceKind: "note", sourceId: 1, meetingId: 1,
            chunkIndex: 0, chunkText: "x", vector: []
        )
        XCTAssertTrue(record.toFloatArray().isEmpty)
    }
}

// MARK: - EmbeddingService.chunk

final class EmbeddingServiceChunkTests: XCTestCase {
    private var svc: EmbeddingService!

    override func setUp() {
        super.setUp()
        let db = try! AppDatabase(DatabaseQueue())
        svc = EmbeddingService(embedder: UnimplementedEmbedder(), repository: EmbeddingRepository(database: db))
    }

    func testEmptyTextReturnsEmpty() {
        XCTAssertTrue(svc.chunk("", maxChars: 100).isEmpty)
    }

    func testZeroMaxCharsReturnsEmpty() {
        XCTAssertTrue(svc.chunk("hello", maxChars: 0).isEmpty)
    }

    func testShortTextSingleChunk() {
        XCTAssertEqual(svc.chunk("Hello world", maxChars: 100), ["Hello world"])
    }

    func testSplitsOnParagraphBoundary() {
        let chunks = svc.chunk("Para one.\n\nPara two.", maxChars: 20)
        XCTAssertEqual(chunks, ["Para one.", "Para two."])
    }

    func testLongParagraphSplitsOnSentence() {
        let text = "First sentence. Second sentence. Third sentence."
        let chunks = svc.chunk(text, maxChars: 30)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks { XCTAssertLessThanOrEqual(chunk.count, 30) }
    }

    func testWhitespaceOnlyParagraphsSkipped() {
        let chunks = svc.chunk("Real text.\n\n   \n\nMore text.", maxChars: 200)
        XCTAssertEqual(chunks.count, 1)
    }
}

// MARK: - EmbeddingRepository

final class EmbeddingRepositoryTests: XCTestCase {
    private func makeDB() throws -> AppDatabase { try AppDatabase(DatabaseQueue()) }

    func testReplaceAllAndFetch() throws {
        let db = try makeDB()
        let meeting = try MeetingRepository(database: db).create(title: "T")
        let repo = EmbeddingRepository(database: db)
        let id = meeting.id!
        try repo.replaceAll(sourceKind: "note", sourceId: 1, records: [
            EmbeddingRecord(sourceKind: "note", sourceId: 1, meetingId: id, chunkIndex: 0, chunkText: "A", vector: [1, 0]),
            EmbeddingRecord(sourceKind: "note", sourceId: 1, meetingId: id, chunkIndex: 1, chunkText: "B", vector: [0, 1])
        ])
        XCTAssertEqual(try repo.allForMeeting(id).count, 2)
    }

    func testReplaceAllOverwritesPrevious() throws {
        let db = try makeDB()
        let meeting = try MeetingRepository(database: db).create()
        let repo = EmbeddingRepository(database: db)
        let id = meeting.id!
        try repo.replaceAll(sourceKind: "note", sourceId: 1, records: [
            EmbeddingRecord(sourceKind: "note", sourceId: 1, meetingId: id, chunkIndex: 0, chunkText: "old", vector: [1])
        ])
        try repo.replaceAll(sourceKind: "note", sourceId: 1, records: [
            EmbeddingRecord(sourceKind: "note", sourceId: 1, meetingId: id, chunkIndex: 0, chunkText: "new", vector: [2])
        ])
        let fetched = try repo.allForMeeting(id)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.chunkText, "new")
    }

    func testDeleteForSource() throws {
        let db = try makeDB()
        let meeting = try MeetingRepository(database: db).create()
        let repo = EmbeddingRepository(database: db)
        let id = meeting.id!
        try repo.replaceAll(sourceKind: "note", sourceId: 1, records: [
            EmbeddingRecord(sourceKind: "note", sourceId: 1, meetingId: id, chunkIndex: 0, chunkText: "x", vector: [1])
        ])
        try repo.deleteForSource(kind: "note", sourceId: 1)
        XCTAssertTrue(try repo.allForMeeting(id).isEmpty)
    }

    func testDeleteForMeeting() throws {
        let db = try makeDB()
        let meeting = try MeetingRepository(database: db).create()
        let repo = EmbeddingRepository(database: db)
        let id = meeting.id!
        try repo.replaceAll(sourceKind: "note", sourceId: 1, records: [
            EmbeddingRecord(sourceKind: "note", sourceId: 1, meetingId: id, chunkIndex: 0, chunkText: "x", vector: [1])
        ])
        try repo.deleteForMeeting(id)
        XCTAssertTrue(try repo.all().isEmpty)
    }
}

// MARK: - EmbeddingService (full integration with stub embedder)

private struct FixedEmbedder: Embedder {
    let value: [Float]
    func embed(_ text: String) -> [Float] { value }
}

final class EmbeddingServiceIntegrationTests: XCTestCase {
    private func makeDB() throws -> AppDatabase { try AppDatabase(DatabaseQueue()) }

    func testIndexNoteInsertsEmbeddings() throws {
        let db = try makeDB()
        let meetings = MeetingRepository(database: db)
        let notes = NoteRepository(database: db)
        let repo = EmbeddingRepository(database: db)
        let svc = EmbeddingService(embedder: FixedEmbedder(value: [1, 0, 0]), repository: repo)

        let meeting = try meetings.create()
        let id = meeting.id!
        try notes.saveRawNote(meetingId: id, markdown: "Meeting notes.\n\nMore content.")
        let note = try notes.rawNote(for: id)
        try svc.indexNote(note)

        let saved = try repo.allForMeeting(id)
        XCTAssertFalse(saved.isEmpty)
        XCTAssertTrue(saved.allSatisfy { $0.sourceKind == "note" })
    }

    func testIndexNoteEmptyContentDeletesExisting() throws {
        let db = try makeDB()
        let meetings = MeetingRepository(database: db)
        let notes = NoteRepository(database: db)
        let repo = EmbeddingRepository(database: db)
        let svc = EmbeddingService(embedder: FixedEmbedder(value: [1]), repository: repo)

        let meeting = try meetings.create()
        let id = meeting.id!
        try notes.saveRawNote(meetingId: id, markdown: "some content")
        try svc.indexNote(try notes.rawNote(for: id))
        XCTAssertFalse(try repo.allForMeeting(id).isEmpty)

        try notes.saveRawNote(meetingId: id, markdown: "")
        try svc.indexNote(try notes.rawNote(for: id))
        XCTAssertTrue(try repo.allForMeeting(id).isEmpty)
    }

    func testIndexTranscriptSegments() throws {
        let db = try makeDB()
        let meetings = MeetingRepository(database: db)
        let transcripts = TranscriptRepository(database: db)
        let repo = EmbeddingRepository(database: db)
        let svc = EmbeddingService(embedder: FixedEmbedder(value: [0, 1]), repository: repo)

        let meeting = try meetings.create()
        let id = meeting.id!
        try transcripts.insertAll([
            TranscriptSegmentRecord(meetingId: id, speaker: "me", startTime: 0, endTime: 1, text: "Hello there"),
            TranscriptSegmentRecord(meetingId: id, speaker: "them", startTime: 1, endTime: 2, text: "Hi back")
        ])
        let segs = try transcripts.forMeeting(id)
        try svc.indexTranscriptSegments(segs, meetingId: id)

        let saved = try repo.allForMeeting(id)
        XCTAssertFalse(saved.isEmpty)
        XCTAssertTrue(saved.allSatisfy { $0.sourceKind == "transcript" })
    }
}

// MARK: - SemanticSearchRepository

final class SemanticSearchRepositoryTests: XCTestCase {
    private func makeDB() throws -> AppDatabase { try AppDatabase(DatabaseQueue()) }

    func testSearchRanksHigherSimilarityFirst() throws {
        let db = try makeDB()
        let meetings = MeetingRepository(database: db)
        let repo = EmbeddingRepository(database: db)

        let m1 = try meetings.create(title: "A")
        let m2 = try meetings.create(title: "B")
        // m1 aligned with [1,0], m2 orthogonal
        try repo.replaceAll(sourceKind: "note", sourceId: 1, records: [
            EmbeddingRecord(sourceKind: "note", sourceId: 1, meetingId: m1.id!, chunkIndex: 0, chunkText: "rel", vector: [1, 0])
        ])
        try repo.replaceAll(sourceKind: "note", sourceId: 2, records: [
            EmbeddingRecord(sourceKind: "note", sourceId: 2, meetingId: m2.id!, chunkIndex: 0, chunkText: "unrel", vector: [0, 1])
        ])

        let searcher = SemanticSearchRepository(database: db, embedder: FixedEmbedder(value: [1, 0]))
        let results = try searcher.search("q")
        XCTAssertEqual(results.first?.meetingId, m1.id)
        XCTAssertGreaterThan(results.first!.score, results.last!.score)
    }

    func testSearchEmptyEmbedderReturnsEmpty() throws {
        let db = try makeDB()
        let searcher = SemanticSearchRepository(database: db, embedder: UnimplementedEmbedder())
        XCTAssertTrue(try searcher.search("anything").isEmpty)
    }

    func testSearchNoCandidatesReturnsEmpty() throws {
        let db = try makeDB()
        let searcher = SemanticSearchRepository(database: db, embedder: FixedEmbedder(value: [1]))
        XCTAssertTrue(try searcher.search("q").isEmpty)
    }

    func testSearchScopedToMeeting() throws {
        let db = try makeDB()
        let meetings = MeetingRepository(database: db)
        let repo = EmbeddingRepository(database: db)

        let m1 = try meetings.create(title: "Target")
        let m2 = try meetings.create(title: "Other")
        try repo.replaceAll(sourceKind: "note", sourceId: 1, records: [
            EmbeddingRecord(sourceKind: "note", sourceId: 1, meetingId: m1.id!, chunkIndex: 0, chunkText: "x", vector: [1])
        ])
        try repo.replaceAll(sourceKind: "note", sourceId: 2, records: [
            EmbeddingRecord(sourceKind: "note", sourceId: 2, meetingId: m2.id!, chunkIndex: 0, chunkText: "y", vector: [1])
        ])

        let searcher = SemanticSearchRepository(database: db, embedder: FixedEmbedder(value: [1]))
        let results = try searcher.search("q", in: .meeting(m1.id!))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.meetingId, m1.id)
    }

    func testSearchScopedToFolder() throws {
        let db = try makeDB()
        let meetings = MeetingRepository(database: db)
        let folders = FolderRepository(database: db)
        let repo = EmbeddingRepository(database: db)

        let folder = try folders.create(name: "Work")
        let m1 = try meetings.create(title: "In folder")
        try meetings.setFolder(m1.id!, folderId: folder.id)
        let m2 = try meetings.create(title: "Out")
        try repo.replaceAll(sourceKind: "note", sourceId: 1, records: [
            EmbeddingRecord(sourceKind: "note", sourceId: 1, meetingId: m1.id!, chunkIndex: 0, chunkText: "x", vector: [1])
        ])
        try repo.replaceAll(sourceKind: "note", sourceId: 2, records: [
            EmbeddingRecord(sourceKind: "note", sourceId: 2, meetingId: m2.id!, chunkIndex: 0, chunkText: "y", vector: [1])
        ])

        let searcher = SemanticSearchRepository(database: db, embedder: FixedEmbedder(value: [1]))
        let results = try searcher.search("q", in: .folder(folder.id!))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.meetingId, m1.id)
    }
}
