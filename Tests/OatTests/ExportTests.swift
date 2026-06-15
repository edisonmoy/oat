import XCTest
import AppKit
@testable import Oat

final class ExportServiceTests: XCTestCase {
    private let svc = ExportService()

    private func meeting(title: String = "Sprint review") -> Meeting {
        Meeting(id: 1, title: title, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                endedAt: nil, templateId: nil, folderId: nil, language: nil, calendarEventId: nil)
    }

    private func note(_ markdown: String, kind: Note.Kind = .raw) -> Note {
        Note(id: 1, meetingId: 1, kind: kind.rawValue, contentMarkdown: markdown, updatedAt: Date())
    }

    private func seg(_ text: String, speaker: String = "me") -> TranscriptSegmentRecord {
        TranscriptSegmentRecord(meetingId: 1, speaker: speaker, startTime: 0, endTime: 1, text: text)
    }

    // MARK: - markdownExport

    func testTitleAndDateAlwaysPresent() {
        let md = svc.markdownExport(meeting: meeting(), rawNote: nil, enhancedNote: nil, transcript: [], attendees: [])
        XCTAssertTrue(md.hasPrefix("# Sprint review"))
        XCTAssertTrue(md.contains("**Date:**"))
    }

    func testAttendeeSectionAbsentWhenEmpty() {
        let md = svc.markdownExport(meeting: meeting(), rawNote: nil, enhancedNote: nil, transcript: [], attendees: [])
        XCTAssertFalse(md.contains("**Attendees:**"))
    }

    func testAttendeeSectionPresentWhenNonEmpty() {
        let attendees = [
            Attendee(id: 1, meetingId: 1, name: "Alice", email: nil),
            Attendee(id: 2, meetingId: 1, name: "Bob", email: nil)
        ]
        let md = svc.markdownExport(meeting: meeting(), rawNote: nil, enhancedNote: nil, transcript: [], attendees: attendees)
        XCTAssertTrue(md.contains("Alice"))
        XCTAssertTrue(md.contains("Bob"))
    }

    func testEnhancedNotePreferredOverRaw() {
        let raw      = note("raw content", kind: .raw)
        let enhanced = note("enhanced content", kind: .enhanced)
        let md = svc.markdownExport(meeting: meeting(), rawNote: raw, enhancedNote: enhanced, transcript: [], attendees: [])
        XCTAssertTrue(md.contains("enhanced content"))
        XCTAssertFalse(md.contains("raw content"))
    }

    func testRawNoteUsedWhenNoEnhanced() {
        let raw = note("raw only", kind: .raw)
        let md = svc.markdownExport(meeting: meeting(), rawNote: raw, enhancedNote: nil, transcript: [], attendees: [])
        XCTAssertTrue(md.contains("raw only"))
    }

    func testNotesSectionAbsentWhenBothNil() {
        let md = svc.markdownExport(meeting: meeting(), rawNote: nil, enhancedNote: nil, transcript: [], attendees: [])
        XCTAssertFalse(md.contains("## Notes"))
    }

    func testNotesSectionAbsentWhenBothEmpty() {
        let md = svc.markdownExport(
            meeting: meeting(),
            rawNote: note(""),
            enhancedNote: note("", kind: .enhanced),
            transcript: [], attendees: []
        )
        XCTAssertFalse(md.contains("## Notes"))
    }

    func testTranscriptSectionPresentWhenNonEmpty() {
        let md = svc.markdownExport(
            meeting: meeting(), rawNote: nil, enhancedNote: nil,
            transcript: [seg("Hello world"), seg("How are you", speaker: "them")],
            attendees: []
        )
        XCTAssertTrue(md.contains("## Transcript"))
        XCTAssertTrue(md.contains("Hello world"))
        XCTAssertTrue(md.contains("How are you"))
    }

    func testTranscriptSectionAbsentWhenEmpty() {
        let md = svc.markdownExport(meeting: meeting(), rawNote: nil, enhancedNote: nil, transcript: [], attendees: [])
        XCTAssertFalse(md.contains("## Transcript"))
    }

    func testTranscriptFormatsTimeCorrectly() {
        var seg = TranscriptSegmentRecord(meetingId: 1, speaker: "me", startTime: 65, endTime: 70, text: "check time")
        let md = svc.markdownExport(meeting: meeting(), rawNote: nil, enhancedNote: nil, transcript: [seg], attendees: [])
        XCTAssertTrue(md.contains("1:05"))
    }

    // MARK: - pdfExport

    func testPDFExportProducesNonEmptyData() throws {
        let data = try svc.pdfExport(markdown: "# Test\n\nHello PDF world.")
        XCTAssertFalse(data.isEmpty)
    }

    func testPDFExportStartsWithPDFMagicBytes() throws {
        let data = try svc.pdfExport(markdown: "# Hello")
        let magic = String(data: data.prefix(4), encoding: .ascii)
        XCTAssertEqual(magic, "%PDF")
    }

    // MARK: - copyToClipboard

    func testCopyToClipboardSetsString() {
        svc.copyToClipboard("clipboard test string")
        let pasted = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasted, "clipboard test string")
    }

    // MARK: - ExportError

    func testExportErrorDescription() {
        XCTAssertTrue(ExportError.renderFailed.errorDescription!.contains("render"))
    }
}
