import Foundation

/// One line of transcript with a speaker label and timing.
struct TranscriptSegment: Identifiable, Hashable {
    let id = UUID()
    var speaker: String        // "me" | "them" | "spkN"
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

/// On-device speech-to-text. Phase 3 implements this with WhisperKit (CoreML,
/// running on the Apple Neural Engine — PLAN.md §2.2), streaming results live
/// and never sending audio off the device.
protocol Transcriber {
    func transcribe(audioURL: URL, speaker: String) async throws -> [TranscriptSegment]
}

/// Placeholder until Phase 3.
struct UnimplementedTranscriber: Transcriber {
    func transcribe(audioURL: URL, speaker: String) async throws -> [TranscriptSegment] { [] }
}
