import Foundation
import Combine
import GRDB

/// Root object graph for the app: owns the database, repositories, and a live
/// list of meetings observed straight from SQLite. Injected into the SwiftUI
/// environment by `OatApp`.
final class AppEnvironment: ObservableObject {
    /// Live list of meetings, kept in sync with the database via `ValueObservation`.
    @Published private(set) var meetings: [Meeting] = []

    /// Set when something outside the list (e.g. the New Meeting menu command)
    /// creates a meeting that the UI should select.
    @Published var pendingSelection: Int64?

    let database: AppDatabase
    let meetingRepository: MeetingRepository
    let noteRepository: NoteRepository

    private var meetingsObservation: AnyDatabaseCancellable?

    init() {
        do {
            let directory = try AppEnvironment.supportDirectory()
            let dbQueue = try DatabaseQueue(path: directory.appendingPathComponent("oat.sqlite").path)
            database = try AppDatabase(dbQueue)
        } catch {
            fatalError("Failed to open Oat database: \(error)")
        }
        meetingRepository = MeetingRepository(database: database)
        noteRepository = NoteRepository(database: database)
        observeMeetings()
    }

    private func observeMeetings() {
        let observation = ValueObservation.tracking { db in
            try Meeting.order(Column("startedAt").desc).fetchAll(db)
        }
        meetingsObservation = observation.start(
            in: database.dbWriter,
            onError: { print("Meetings observation error: \($0)") },
            onChange: { [weak self] meetings in self?.meetings = meetings }
        )
    }

    @discardableResult
    func createMeeting() -> Meeting? {
        do {
            return try meetingRepository.create()
        } catch {
            print("Create meeting failed: \(error)")
            return nil
        }
    }

    /// Creates a meeting and asks the UI to select it.
    func requestNewMeeting() {
        if let meeting = createMeeting() {
            pendingSelection = meeting.id
        }
    }

    func deleteMeeting(_ meeting: Meeting) {
        guard let id = meeting.id else { return }
        do {
            try meetingRepository.delete(id)
        } catch {
            print("Delete meeting failed: \(error)")
        }
    }

    private static func supportDirectory() throws -> URL {
        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Oat", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
