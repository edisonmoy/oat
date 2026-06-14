import Foundation

/// Captures the microphone and system-output audio as two *separate* streams
/// (the trick that gives near-free "Me" vs "Them" labeling — PLAN.md §2.1).
///
/// Phase 2 implements this with Core Audio process taps (system output) +
/// AVAudioEngine (mic), encoding each stream to Opus on disk for retention.
protocol AudioCaptureService {
    /// Begins capture for a meeting, writing mic/system audio to disk.
    func start(meetingID: Int64) async throws
    /// Stops capture and finalizes the recording files.
    func stop() async
}

enum AudioCaptureError: Error {
    case notImplemented
    case permissionDenied
}

/// Placeholder until Phase 2 so the rest of the app can compile against the
/// interface.
struct UnimplementedAudioCaptureService: AudioCaptureService {
    func start(meetingID: Int64) async throws { throw AudioCaptureError.notImplemented }
    func stop() async {}
}
