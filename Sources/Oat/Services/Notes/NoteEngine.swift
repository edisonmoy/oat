import Foundation

/// Expands the user's raw notes into polished, structured notes using the full
/// transcript as context (PLAN.md §1.4 / §2.3).
///
/// Phase 4 ships two interchangeable implementations selected per the local/cloud
/// split (§3.2): cloud Claude by default for quality, and Apple's on-device
/// Foundation Models for privacy/offline mode.
protocol NoteEngine {
    func enhance(rawNotes: String, transcript: String, template: Template?) async throws -> String
}

/// Placeholder until Phase 4 — echoes the raw notes back unchanged.
struct UnimplementedNoteEngine: NoteEngine {
    func enhance(rawNotes: String, transcript: String, template: Template?) async throws -> String {
        rawNotes
    }
}
