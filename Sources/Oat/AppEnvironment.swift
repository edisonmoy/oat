import Foundation
import Combine
import GRDB

/// Root object graph for the app: owns the database, repositories, and a live
/// list of meetings observed straight from SQLite. Injected into the SwiftUI
/// environment by `OatApp`.
final class AppEnvironment: ObservableObject {
    /// Live list of meetings, kept in sync with the database via `ValueObservation`.
    @Published private(set) var meetings: [Meeting] = []

    /// Live list of folders.
    @Published private(set) var folders: [Folder] = []

    /// Set when something outside the list (e.g. the New Meeting menu command)
    /// creates a meeting that the UI should select.
    @Published var pendingSelection: Int64?

    let database: AppDatabase
    let meetingRepository: MeetingRepository
    let noteRepository: NoteRepository
    let folderRepository: FolderRepository
    let templateRepository: TemplateRepository
    let searchRepository: SearchRepository

    private var meetingsObservation: AnyDatabaseCancellable?
    private var foldersObservation: AnyDatabaseCancellable?

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
        folderRepository = FolderRepository(database: database)
        templateRepository = TemplateRepository(database: database)
        searchRepository = SearchRepository(database: database)

        try? templateRepository.seedDefaultsIfEmpty()
        observeMeetings()
        observeFolders()
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

    private func observeFolders() {
        let observation = ValueObservation.tracking { db in
            try Folder.order(Column("name")).fetchAll(db)
        }
        foldersObservation = observation.start(
            in: database.dbWriter,
            onError: { print("Folders observation error: \($0)") },
            onChange: { [weak self] folders in self?.folders = folders }
        )
    }

    // MARK: - Folders

    func createFolder(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do { try folderRepository.create(name: trimmed) }
        catch { print("Create folder failed: \(error)") }
    }

    func deleteFolder(_ folder: Folder) {
        guard let id = folder.id else { return }
        do { try folderRepository.delete(id) }
        catch { print("Delete folder failed: \(error)") }
    }

    func assignMeeting(_ meeting: Meeting, folderID: Int64?) {
        guard let id = meeting.id else { return }
        do { try meetingRepository.setFolder(id, folderId: folderID) }
        catch { print("Assign meeting failed: \(error)") }
    }

    // MARK: - Search

    func search(_ text: String) -> [Meeting] {
        do { return try searchRepository.search(text) }
        catch { print("Search failed: \(error)"); return [] }
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
