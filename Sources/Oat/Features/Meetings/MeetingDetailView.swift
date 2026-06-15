import SwiftUI

struct MeetingDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    let meeting: Meeting

    @AppStorage("enhancementProvider") private var enhancementProvider = EnhancementProvider.cloud
    @AppStorage("privacyMode") private var privacyMode = false

    @State private var title: String = ""
    @State private var rawNote: String = ""
    @State private var segments: [TranscriptSegmentRecord] = []
    @State private var showingTranscript = false

    @State private var isRecording = false
    @State private var currentRecordingId: Int64?

    @State private var micLevel: Float = 0
    @State private var systemLevel: Float = 0
    private let levelTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    @State private var enhancing = false
    @State private var enhancedText: String?
    @State private var showingEnhanced = false
    @State private var errorMessage: String?

    var body: some View {
        HSplitView {
            // MARK: Notes pane
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

                if isRecording {
                    AudioLevelView(micLevel: micLevel, systemLevel: systemLevel)
                        .padding(.horizontal)
                        .padding(.top, 6)
                        .onReceive(levelTimer) { _ in
                            micLevel = env.audioCapture.micLevel
                            systemLevel = env.audioCapture.systemLevel
                        }
                }

                Divider().padding(.top, 8)

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

            // MARK: Transcript pane (toggled)
            if showingTranscript {
                VStack(spacing: 0) {
                    HStack {
                        Text("Transcript")
                            .font(.headline)
                        Spacer()
                        Text("\(segments.count) segments")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    Divider()
                    if segments.isEmpty {
                        ContentUnavailableView(
                            "No transcript yet",
                            systemImage: "waveform",
                            description: Text("Start recording to see a live transcript here.")
                        )
                    } else {
                        TranscriptView(segments: segments)
                    }
                }
                .frame(minWidth: 240, maxWidth: 340)
            }
        }
        .task(id: meeting.id) { load() }
        .onChange(of: rawNote) { _, _ in saveNote() }
        .onDisappear {
            saveTitle()
            saveNote()
            if isRecording { Task { await stopRecording() } }
        }
        .toolbar {
            // Record / Stop
            ToolbarItem {
                Button(action: toggleRecording) {
                    if isRecording {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Label("Record", systemImage: "record.circle")
                    }
                }
                .help(isRecording ? "Stop recording" : "Start recording mic + system audio")
            }

            // Transcript toggle
            ToolbarItem {
                Toggle(isOn: $showingTranscript) {
                    Label("Transcript", systemImage: "text.bubble")
                }
                .toggleStyle(.button)
                .help("Show/hide transcript pane")
            }

            // Enhance
            ToolbarItem {
                Button(action: enhance) {
                    if enhancing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Enhance", systemImage: "wand.and.stars")
                    }
                }
                .disabled(enhancing || isRecording)
                .help("Turn your rough notes into clean, AI-enhanced notes")
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

    // MARK: - Load

    private func load() {
        title = meeting.title
        guard let id = meeting.id else { return }
        rawNote = (try? env.noteRepository.rawNote(for: id).contentMarkdown) ?? ""
        enhancedText = try? env.noteRepository.enhancedNote(for: id)?.contentMarkdown
        segments = (try? env.transcriptRepository.forMeeting(id)) ?? []
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording {
            Task { await stopRecording() }
        } else {
            Task { await startRecording() }
        }
    }

    private func startRecording() async {
        guard let id = meeting.id else { return }
        do {
            try await env.audioCapture.start(meetingID: id)
            let rec = try env.recordingRepository.create(
                meetingId: id, micPath: "mic.caf", systemPath: "system.caf"
            )
            currentRecordingId = rec.id
            isRecording = true
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() async {
        let start = Date()
        await env.audioCapture.stop()
        isRecording = false
        micLevel = 0
        systemLevel = 0

        let duration = Date().timeIntervalSince(start)
        if let recId = currentRecordingId {
            try? env.recordingRepository.updateDuration(recId, duration: duration)
        }
        currentRecordingId = nil

        // Transcribe both streams and merge results
        guard let meetingId = meeting.id else { return }
        await transcribeAfterStop(meetingId: meetingId)
    }

    private func transcribeAfterStop(meetingId: Int64) async {
        guard let recordings = try? env.recordingRepository.forMeeting(meetingId),
              let latest = recordings.first else { return }

        let supportBase = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ))
        guard let base = supportBase else { return }
        let dir = base.appendingPathComponent("Oat/recordings/\(meetingId)")

        do {
            if env.transcriber.loadedModel == nil {
                try await env.transcriber.loadModel()
            }

            var merged: [TranscriptSegment] = []
            if latest.micPath != nil {
                let url = dir.appendingPathComponent("mic.caf")
                let segs = try await env.transcriber.transcribe(audioURL: url, speaker: "me")
                merged.append(contentsOf: segs)
            }
            if latest.systemPath != nil {
                let url = dir.appendingPathComponent("system.caf")
                let segs = try await env.transcriber.transcribe(audioURL: url, speaker: "them")
                merged.append(contentsOf: segs)
            }

            let sorted = merged.sorted { $0.start < $1.start }
            let records = sorted.map {
                TranscriptSegmentRecord(
                    meetingId: meetingId,
                    speaker: $0.speaker,
                    startTime: $0.start,
                    endTime: $0.end,
                    text: $0.text
                )
            }
            try env.transcriptRepository.deleteForMeeting(meetingId)
            try env.transcriptRepository.insertAll(records)
            segments = (try? env.transcriptRepository.forMeeting(meetingId)) ?? []
        } catch {
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    private func saveTitle() {
        guard let id = meeting.id else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = trimmed.isEmpty ? "Untitled meeting" : trimmed
        try? env.meetingRepository.updateTitle(id, title: final)
    }

    private func saveNote() {
        guard let id = meeting.id else { return }
        try? env.noteRepository.saveRawNote(meetingId: id, markdown: rawNote)
    }

    // MARK: - Enhancement

    private func enhance() {
        guard let id = meeting.id else { return }
        saveNote()
        enhancing = true
        errorMessage = nil

        let engine = NoteEngineFactory.make(privacyMode: privacyMode, provider: enhancementProvider)
        let notes = rawNote
        let transcript = segments.map { "[\($0.speaker == "me" ? "Me" : "Them")] \($0.text)" }
            .joined(separator: "\n")

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

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

// MARK: - Enhanced note sheet

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
