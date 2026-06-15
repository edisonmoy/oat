import SwiftUI

/// Shows live or post-meeting transcript segments with Me/Them labels.
struct TranscriptView: View {
    let segments: [TranscriptSegmentRecord]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(segments) { seg in
                        HStack(alignment: .top, spacing: 8) {
                            Text(seg.speaker == "me" ? "Me" : "Them")
                                .font(.caption.bold())
                                .foregroundStyle(seg.speaker == "me" ? Color.accentColor : .secondary)
                                .frame(width: 36, alignment: .trailing)

                            Text(seg.text)
                                .font(.callout)
                                .textSelection(.enabled)

                            Spacer(minLength: 0)

                            Text(formatTime(seg.startTime))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                        .id(seg.id)
                    }
                }
                .padding()
            }
            .onChange(of: segments.count) { _, _ in
                if let last = segments.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Two horizontal bars showing mic and system audio levels (0–1).
struct AudioLevelView: View {
    let micLevel: Float
    let systemLevel: Float

    var body: some View {
        HStack(spacing: 4) {
            LevelBar(label: "Mic", level: micLevel, color: .accentColor)
            LevelBar(label: "Sys", level: systemLevel, color: .orange)
        }
        .frame(height: 20)
    }
}

private struct LevelBar: View {
    let label: String
    let level: Float
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(level))
                }
            }
        }
    }
}
