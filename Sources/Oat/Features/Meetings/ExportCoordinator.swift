import AppKit
import UniformTypeIdentifiers

@MainActor
struct ExportCoordinator {
    func export(meeting: Meeting, env: AppEnvironment) async {
        guard let meetingId = meeting.id else { return }
        let rawNote    = try? env.noteRepository.rawNote(for: meetingId)
        let enhanced   = try? env.noteRepository.enhancedNote(for: meetingId)
        let transcript = (try? env.transcriptRepository.forMeeting(meetingId)) ?? []
        let attendees  = (try? env.attendeeRepository.forMeeting(meetingId)) ?? []

        let svc = ExportService()
        let markdown = svc.markdownExport(
            meeting: meeting, rawNote: rawNote, enhancedNote: enhanced,
            transcript: transcript, attendees: attendees
        )

        let mdType = UTType(filenameExtension: "md") ?? .plainText
        let panel = NSSavePanel()
        panel.allowedContentTypes = [mdType, .pdf]
        panel.nameFieldStringValue = "\(meeting.title).md"

        guard let window = NSApp.keyWindow else { return }
        let response = await panel.beginSheetModal(for: window)
        guard response == .OK, let url = panel.url else { return }

        do {
            if url.pathExtension.lowercased() == "pdf" {
                try svc.pdfExport(markdown: markdown).write(to: url)
            } else {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Export failed: \(error)")
        }
    }
}
