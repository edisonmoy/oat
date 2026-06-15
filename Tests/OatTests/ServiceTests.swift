import XCTest
@testable import Oat

// MARK: - KeychainStore

final class KeychainStoreTests: XCTestCase {
    // Use a per-run unique key to avoid cross-test interference.
    private let testKey = "com.oat.test.\(UUID().uuidString)"

    override func tearDown() {
        KeychainStore.set(nil, for: testKey)
    }

    func testSetAndGet() {
        KeychainStore.set("secret-value", for: testKey)
        XCTAssertEqual(KeychainStore.get(testKey), "secret-value")
    }

    func testSetNilClearsExistingValue() {
        KeychainStore.set("secret-value", for: testKey)
        KeychainStore.set(nil, for: testKey)
        XCTAssertNil(KeychainStore.get(testKey))
    }

    func testSetEmptyStringClearsExistingValue() {
        KeychainStore.set("secret-value", for: testKey)
        KeychainStore.set("", for: testKey)
        XCTAssertNil(KeychainStore.get(testKey))
    }

    func testGetMissingKeyReturnsNil() {
        XCTAssertNil(KeychainStore.get("com.oat.test.key.definitely.missing"))
    }
}

// MARK: - AudioCaptureService

final class AudioCaptureServiceTests: XCTestCase {
    func testUnimplementedStartThrowsNotImplemented() async {
        let service = UnimplementedAudioCaptureService()
        do {
            try await service.start(meetingID: 42)
            XCTFail("Expected notImplemented error")
        } catch AudioCaptureError.notImplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnimplementedStopCompletes() async {
        let service = UnimplementedAudioCaptureService()
        await service.stop()
    }
}

// MARK: - Transcriber

final class TranscriberTests: XCTestCase {
    func testUnimplementedTranscriberReturnsEmpty() async throws {
        let transcriber = UnimplementedTranscriber()
        let result = try await transcriber.transcribe(audioURL: URL(fileURLWithPath: "/dev/null"), speaker: "me")
        XCTAssertTrue(result.isEmpty)
    }

    func testTranscriptSegmentProperties() {
        let segment = TranscriptSegment(speaker: "them", start: 1.0, end: 2.5, text: "Hello world")
        XCTAssertEqual(segment.speaker, "them")
        XCTAssertEqual(segment.start, 1.0)
        XCTAssertEqual(segment.end, 2.5)
        XCTAssertEqual(segment.text, "Hello world")
        XCTAssertNotNil(segment.id)
    }

    func testTranscriptSegmentHashableAndEquatable() {
        let seg1 = TranscriptSegment(speaker: "me", start: 0, end: 1, text: "hi")
        let seg2 = TranscriptSegment(speaker: "me", start: 0, end: 1, text: "hi")
        // Each instance gets a fresh UUID, so they're never equal.
        XCTAssertNotEqual(seg1, seg2)
        // Exercise synthesized hash(into:) via Set insertion.
        let set = Set([seg1, seg2])
        XCTAssertEqual(set.count, 2)
    }
}

// MARK: - Embedder

final class EmbedderTests: XCTestCase {
    func testUnimplementedEmbedderReturnsEmpty() {
        let embedder = UnimplementedEmbedder()
        XCTAssertTrue(embedder.embed("hello world").isEmpty)
    }
}

// MARK: - EnhancementProvider

final class EnhancementProviderTests: XCTestCase {
    func testIdentifiers() {
        XCTAssertEqual(EnhancementProvider.cloud.id, "cloud")
        XCTAssertEqual(EnhancementProvider.local.id, "local")
    }

    func testLabels() {
        XCTAssertTrue(EnhancementProvider.cloud.label.contains("Cloud"))
        XCTAssertTrue(EnhancementProvider.local.label.contains("On-device"))
    }

    func testAllCasesCount() {
        XCTAssertEqual(EnhancementProvider.allCases.count, 2)
    }
}
