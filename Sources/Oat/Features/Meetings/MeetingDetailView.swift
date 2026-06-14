import SwiftUI

/// The barebones, Apple Notes-like jotting surface (PLAN.md §1.3): an editable
/// title plus a plain-text notes area that persists to the `note` table. Audio,
/// live transcript, and AI enhancement attach to this view in later phases.
struct MeetingDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let meeting: Meeting

    @State private var title: String = ""
    @State private var rawNote: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Meeting title", text: $title)
                .font(.largeTitle.bold())
                .textFieldStyle(.plain)
                .padding(.horizontal)
                .padding(.top)
                .onSubmit(saveTitle)

            Text(meeting.startedAt, format: .dateTime.weekday().month().day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 2)

            Divider()
                .padding(.top, 10)

            TextEditor(text: $rawNote)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .overlay(alignment: .topLeading) {
                    if rawNote.isEmpty {
                        Text("Jot down anything — the AI fills in the rest after the call.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
        .task(id: meeting.id) { load() }
        .onChange(of: rawNote) { _, _ in saveNote() }
        .onDisappear {
            saveTitle()
            saveNote()
        }
    }

    private func load() {
        title = meeting.title
        guard let id = meeting.id else { return }
        rawNote = (try? env.noteRepository.rawNote(for: id).contentMarkdown) ?? ""
    }

    private func saveTitle() {
        guard let id = meeting.id else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "Untitled meeting" : trimmed
        try? env.meetingRepository.updateTitle(id, title: finalTitle)
    }

    private func saveNote() {
        guard let id = meeting.id else { return }
        try? env.noteRepository.saveRawNote(meetingId: id, markdown: rawNote)
    }
}
