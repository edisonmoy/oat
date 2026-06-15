import Foundation
import AppKit

enum ExportError: Error, LocalizedError {
    case renderFailed
    var errorDescription: String? { "Failed to render the export document." }
}

struct ExportService {

    // MARK: - Markdown

    func markdownExport(
        meeting: Meeting,
        rawNote: Note?,
        enhancedNote: Note?,
        transcript: [TranscriptSegmentRecord],
        attendees: [Attendee]
    ) -> String {
        var md = "# \(meeting.title)\n\n"

        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .short
        md += "**Date:** \(df.string(from: meeting.startedAt))\n\n"

        if !attendees.isEmpty {
            md += "**Attendees:** \(attendees.map(\.name).joined(separator: ", "))\n\n"
        }

        let noteBody = enhancedNote?.contentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? rawNote?.contentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if let body = noteBody, !body.isEmpty {
            md += "## Notes\n\n\(body)\n\n"
        }

        if !transcript.isEmpty {
            md += "## Transcript\n\n"
            for seg in transcript {
                let speaker = seg.speaker == "me" ? "Me" : "Them"
                md += "**[\(formatTime(seg.startTime))] \(speaker):** \(seg.text)\n\n"
            }
        }

        return md
    }

    // MARK: - PDF

    func pdfExport(markdown: String) throws -> Data {
        let attrStr = NSAttributedString(string: markdown, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black
        ])

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw ExportError.renderFailed
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.renderFailed
        }

        ctx.beginPDFPage(nil)
        let graphicsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsCtx
        attrStr.draw(in: CGRect(x: 54, y: 54, width: 504, height: 684))
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()

        return pdfData as Data
    }

    // MARK: - Clipboard

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
