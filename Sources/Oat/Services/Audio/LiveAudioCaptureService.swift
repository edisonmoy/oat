import AVFoundation
import Accelerate
import ScreenCaptureKit

/// Concrete implementation of AudioCaptureService (Phase 2).
///
/// Captures two independent streams:
///   - Mic   → AVAudioEngine inputNode tap → CAF file
///   - System → ScreenCaptureKit audio-only stream → CAF file via AVAssetWriter
///
/// The two-stream approach gives near-free "Me" vs "Them" labeling for
/// transcription (PLAN.md §2.1). Both files are retained on disk so the
/// user can replay them, re-transcribe with a larger model, and jump to
/// any transcript line (Phase 3 wires this up).
@MainActor
final class LiveAudioCaptureService: NSObject, AudioCaptureService {
    // MARK: - Published state (read from the UI for level meters)

    private(set) var micLevel: Float = 0
    private(set) var systemLevel: Float = 0

    // Callback fires on main thread whenever a new recording is persisted.
    var onRecordingCreated: ((URL) -> Void)?

    // MARK: - Private state

    private var micEngine: AVAudioEngine?
    private var micFile: AVAudioFile?

    private var scStream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var assetInput: AVAssetWriterInput?
    private var writerSessionStarted = false
    private var currentDirectory: URL?

    // MARK: - AudioCaptureService

    func start(meetingID: Int64) async throws {
        let dir = try recordingDirectory(for: meetingID)
        currentDirectory = dir
        try startMicCapture(in: dir)
        // System audio is best-effort — missing screen-capture permission just
        // means we record mic only, which is still useful.
        try? await startSystemCapture(in: dir)
    }

    func stop() async {
        micEngine?.inputNode.removeTap(onBus: 0)
        micEngine?.stop()
        micEngine = nil
        micFile = nil
        micLevel = 0

        if let stream = scStream {
            try? await stream.stopCapture()
            scStream = nil
        }

        assetInput?.markAsFinished()
        if let writer = assetWriter {
            await writer.finishWriting()
        }
        assetWriter = nil
        assetInput = nil
        writerSessionStarted = false
        systemLevel = 0
    }

    // MARK: - Mic capture

    private func startMicCapture(in directory: URL) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let url = directory.appendingPathComponent("mic.caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        micFile = file
        micEngine = engine

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self, weak file] buffer, _ in
            try? file?.write(from: buffer)
            let level = LiveAudioCaptureService.rmsLevel(buffer: buffer)
            DispatchQueue.main.async { self?.micLevel = level }
        }
        try engine.start()
    }

    // MARK: - System audio capture (ScreenCaptureKit, macOS 12.3+)

    private func startSystemCapture(in directory: URL) async throws {
        guard #available(macOS 12.3, *) else { return }

        let url = directory.appendingPathComponent("system.caf")
        let writer = try AVAssetWriter(outputURL: url, fileType: .caf)
        // outputSettings = nil → passthrough (preserves the stream's native format)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        writer.startWriting()
        assetWriter = writer
        assetInput = input

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { return }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 44_100
        config.channelCount = 2
        // Capture a 2×2 frame so ScreenCaptureKit is satisfied but video
        // overhead is negligible (audio-only tap lands in macOS 14.4 via CATap,
        // which we can adopt later without changing the file format).
        config.width = 2
        config.height = 2

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()
        scStream = stream
    }

    // MARK: - Helpers

    private func recordingDirectory(for meetingID: Int64) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = base.appendingPathComponent("Oat/recordings/\(meetingID)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let count = vDSP_Length(buffer.frameLength)
        guard count > 0 else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(data[0], 1, &rms, count)
        // Scale to a 0–1 range suitable for driving a level-meter view.
        return min(1, rms * 10)
    }
}

// MARK: - SCStreamOutput

@available(macOS 12.3, *)
extension LiveAudioCaptureService: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  let input = assetInput,
                  input.isReadyForMoreMediaData else { return }
            if !writerSessionStarted {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                assetWriter?.startSession(atSourceTime: pts)
                writerSessionStarted = true
            }
            input.append(sampleBuffer)
        }
    }
}
