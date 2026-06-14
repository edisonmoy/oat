import SwiftUI

/// The barebones, Apple Notes-like jotting surface (PLAN.md §1.3): an editable
/// title plus a plain-text notes area that persists to the `note` table. The
/// "Enhance" action turns the raw notes into clean notes using the full
/// transcript (Phase 4 — transcript arrives in Phase 3).
struct MeetingDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let meeting: Meeting

    @AppStorage("enhancementProvider") private var enhancementProvider = EnhancementProvider.cloud
    @AppStorage("privacyMode") private var privacyMode = false

    @State private var title: String = ""
    @State private var rawNote: String = ""

    @State private var enhancing = false
    @State private var enhancedText: String?
    @State private var showingEnhanced = false
    @State private var errorMessage: String?

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
        .toolbar {
            ToolbarItem {
                Button(action: enhance) {
                    if enhancing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Enhance", systemImage: "wand.and.stars")
                    }
                }
                .disabled(enhancing)
                .help("Turn your rough notes into clean notes")
            }
        }
        .sheet(isPresented: $showingEnhanced) {
            EnhancedNoteSheet(markdown: enhancedText ?? "")
        }
        .alert("Couldn't enhance notes", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func load() {
        title = meeting.title
        guard let id = meeting.id else { return }
        rawNote = (try? env.noteRepository.rawNote(for: id).contentMarkdown) ?? ""
        enhancedText = try? env.noteRepository.enhancedNote(for: id)?.contentMarkdown
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

    private func enhance() {
        guard let id = meeting.id else { return }
        saveNote()
        enhancing = true
        errorMessage = nil

        let engine = NoteEngineFactory.make(privacyMode: privacyMode, provider: enhancementProvider)
        let notes = rawNote
        // TODO(Phase 3): pass the real transcript once capture/transcription land.
        let transcript = ""

        Task {
            do {
                let result = try await engine.enhance(rawNotes: notes, transcript: transcript, template: nil)
                try env.noteRepository.saveEnhancedNote(meetingId: id, markdown: result)
                await MainActor.run {
                    enhancedText = result
                    enhancing = false
                    showingEnhanced = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    enhancing = false
                }
            }
        }
    }
}

/// Renders the enhanced Markdown notes with copy/dismiss.
private struct EnhancedNoteSheet: View {
    let markdown: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Enhanced notes")
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            ScrollView {
                Text(attributed)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 560, height: 540)
    }

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }
}
