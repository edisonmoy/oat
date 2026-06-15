import Foundation
import WhisperKit

enum TranscriptionError: Error, LocalizedError {
    case modelNotLoaded
    case noResults

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Transcription model not loaded. Open Settings to download a model."
        case .noResults:
            return "No transcription results returned."
        }
    }
}

/// On-device speech-to-text via WhisperKit (CoreML, Apple Neural Engine).
/// Audio never leaves the device. (PLAN.md §2.2 / Phase 3)
///
/// Call `loadModel()` once (e.g. at app launch or on first recording stop)
/// before calling `transcribe(audioURL:speaker:)`. The model is cached by
/// WhisperKit in the app's Caches directory after the first download.
final class WhisperTranscriber: Transcriber {
    // "openai_whisper-base" is a good default: fast, ~150 MB, accurate enough
    // for meeting notes. The user can upgrade to "openai_whisper-large-v3" in
    // Settings for higher accuracy at the cost of more RAM + compute.
    static let defaultModel = "openai_whisper-base"

    private var pipe: WhisperKit?
    private(set) var loadedModel: String?

    func loadModel(_ name: String = WhisperTranscriber.defaultModel) async throws {
        let kit = try await WhisperKit(model: name)
        pipe = kit
        loadedModel = name
    }

    func transcribe(audioURL: URL, speaker: String) async throws -> [TranscriptSegment] {
        guard let pipe else { throw TranscriptionError.modelNotLoaded }
        let results = try await pipe.transcribe(audioPath: audioURL.path(percentEncoded: false))
        guard !results.isEmpty else { throw TranscriptionError.noResults }
        return results.flatMap { result in
            result.segments.compactMap { seg in
                let trimmed = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return TranscriptSegment(
                    speaker: speaker,
                    start: TimeInterval(seg.start),
                    end: TimeInterval(seg.end),
                    text: trimmed
                )
            }
        }
    }
}
