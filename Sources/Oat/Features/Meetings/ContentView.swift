import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selectedID: Int64?
    @State private var activeFolderID: Int64?
    @State private var searchText = ""
    @State private var showingNewFolder = false
    @State private var newFolderName = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedMeetings: [Meeting] {
        if isSearching {
            return env.search(searchText)
        }
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
    }

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
