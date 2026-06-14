import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selectedID: Int64?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                Section("Meetings") {
                    ForEach(env.meetings) { meeting in
                        MeetingRow(meeting: meeting)
                            .tag(meeting.id ?? 0)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    env.deleteMeeting(meeting)
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Oat")
            .toolbar {
                ToolbarItem {
                    Button {
                        if let meeting = env.createMeeting() {
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
    }
}
