import SwiftUI
import EventKit

struct ContentView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selectedID: Int64?
    @State private var activeFolderID: Int64?
    @State private var searchText = ""
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var upcomingEvents: [EKEvent] = []
    @State private var calendarAuthorized = false

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedMeetings: [Meeting] {
        if isSearching { return env.search(searchText) }
        if let activeFolderID {
            return env.meetings.filter { $0.folderId == activeFolderID }
        }
        return env.meetings
    }

    private var activeFolderName: String {
        guard let activeFolderID,
              let folder = env.folders.first(where: { $0.id == activeFolderID }) else {
            return "All Meetings"
        }
        return folder.name
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                // MARK: Upcoming calendar events
                if !upcomingEvents.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcomingEvents, id: \.eventIdentifier) { event in
                            Button {
                                startMeetingFrom(event: event)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title ?? "Untitled")
                                        .lineLimit(1)
                                    Text(event.startDate, format: .dateTime.weekday(.abbreviated).hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // MARK: Recorded meetings
                Section(isSearching ? "Results" : activeFolderName) {
                    ForEach(displayedMeetings) { meeting in
                        MeetingRow(meeting: meeting)
                            .tag(meeting.id ?? 0)
                            .contextMenu {
                                moveMenu(for: meeting)
                                Button("Delete", role: .destructive) {
                                    env.deleteMeeting(meeting)
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Oat")
            .searchable(text: $searchText, prompt: "Search meetings")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("All Meetings") { activeFolderID = nil }
                        if !env.folders.isEmpty {
                            Divider()
                            ForEach(env.folders) { folder in
                                Button(folder.name) { activeFolderID = folder.id }
                            }
                        }
                        Divider()
                        Button("New Folder…") {
                            newFolderName = ""
                            showingNewFolder = true
                        }
                    } label: {
                        Label(activeFolderName, systemImage: "folder")
                    }
                }
                ToolbarItem {
                    Button {
                        if let meeting = env.createMeeting() {
                            if let activeFolderID {
                                env.assignMeeting(meeting, folderID: activeFolderID)
                            }
                            selectedID = meeting.id
                        }
                    } label: {
                        Label("New Meeting", systemImage: "square.and.pencil")
                    }
                }
            }
        } detail: {
            if let id = selectedID,
               let meeting = env.meetings.first(where: { $0.id == id }) {
                MeetingDetailView(meeting: meeting)
                    .id(meeting.id)
            } else {
                ContentUnavailableView(
                    "No meeting selected",
                    systemImage: "doc.text",
                    description: Text("Create a meeting or pick one from the list.")
                )
            }
        }
        .onChange(of: env.pendingSelection) { _, newValue in
            if let newValue {
                selectedID = newValue
                env.pendingSelection = nil
            }
        }
        .alert("New Folder", isPresented: $showingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { env.createFolder(name: newFolderName) }
            Button("Cancel", role: .cancel) {}
        }
        .task { await setupCalendar() }
    }

    // MARK: - Calendar

    private func setupCalendar() async {
        guard !env.calendarService.isAuthorized else {
            refreshEvents()
            return
        }
        calendarAuthorized = (try? await env.calendarService.requestAccess()) ?? false
        if calendarAuthorized { refreshEvents() }
    }

    private func refreshEvents() {
        upcomingEvents = env.calendarService.upcomingEvents(days: 7)
    }

    /// Creates a new meeting pre-populated from a calendar event.
    private func startMeetingFrom(event: EKEvent) {
        guard var meeting = env.createMeeting() else { return }
        meeting.calendarEventId = event.eventIdentifier

        let title = event.title ?? "Untitled meeting"
        try? env.meetingRepository.updateTitle(meeting.id!, title: title)

        // Persist attendees
        if let id = meeting.id {
            let attendees = env.calendarService.attendees(from: event).map { att in
                Attendee(id: nil, meetingId: id, name: att.name, email: att.email)
            }
            try? env.attendeeRepository.replaceAll(for: id, attendees: attendees)
        }

        selectedID = meeting.id
    }

    // MARK: - Context menu

    @ViewBuilder
    private func moveMenu(for meeting: Meeting) -> some View {
        Menu("Move to") {
            Button("None") { env.assignMeeting(meeting, folderID: nil) }
            if !env.folders.isEmpty {
                Divider()
                ForEach(env.folders) { folder in
                    Button(folder.name) { env.assignMeeting(meeting, folderID: folder.id) }
                }
            }
        }
    }
}
