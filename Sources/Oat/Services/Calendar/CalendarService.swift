import EventKit
import Foundation

/// Wraps EventKit to surface upcoming calendar events so the user can
/// start a meeting note directly from their calendar. (PLAN.md Phase 5)
///
/// Authorization is requested lazily on first use. The app declares the
/// `NSCalendarsUsageDescription` key in Info.plist (via project.yml) and
/// the `com.apple.security.personal-information.calendars` entitlement.
final class CalendarService {
    private let store = EKEventStore()

    // MARK: - Authorization

    /// Returns `true` if the user has already granted calendar access.
    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Requests full calendar access. Returns whether access was granted.
    @discardableResult
    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    // MARK: - Fetching events

    /// Upcoming calendar events within the next `days` days, sorted by start time.
    func upcomingEvents(days: Int = 7) -> [EKEvent] {
        guard isAuthorized else { return [] }
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: now) else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Conversion helpers

    /// Builds a list of `Attendee` models from an `EKEvent`'s participant list.
    func attendees(from event: EKEvent) -> [Attendee] {
        (event.attendees ?? []).compactMap { participant in
            guard let name = participant.name, !name.isEmpty else { return nil }
            return Attendee(
                id: nil,
                meetingId: 0,   // caller sets the real meetingId before inserting
                name: name,
                email: participant.url.absoluteString.hasPrefix("mailto:")
                    ? String(participant.url.absoluteString.dropFirst("mailto:".count))
                    : nil
            )
        }
    }
}
