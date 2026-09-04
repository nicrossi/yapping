import SwiftUI

struct OverlayView: View {
    @Environment(DictationSession.self) private var session

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 22)
            Text(caption)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(captionColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            if session.state == .recording {
                LevelBars(level: session.level)
            } else if session.state.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .padding(6)
        .animation(.easeOut(duration: 0.15), value: session.state)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch session.state {
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse, options: .repeating)
        case .transcribing, .processing, .inserting:
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .idle:
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        switch session.state {
        case .recording:
            session.partialTranscript.isEmpty ? "Listening…" : session.partialTranscript
        case .transcribing:
            session.partialTranscript.isEmpty ? "Transcribing…" : session.partialTranscript
        case .processing: "Cleaning up…"
        case .inserting: "Inserting…"
        case .failed(let message): message
        case .idle: ""
        }
    }

    private var captionColor: Color {
        switch session.state {
        case .failed: .orange
        case .recording where session.partialTranscript.isEmpty: .secondary
        case .transcribing where session.partialTranscript.isEmpty: .secondary
        default: .primary
        }
    }
}

/// Five bars that dance with the input level.
struct LevelBars: View {
    let level: Float
    private let weights: [Float] = [0.55, 0.8, 1.0, 0.8, 0.55]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(weights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: height(for: i))
            }
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func height(for index: Int) -> CGFloat {
        let base: CGFloat = 4
        let scaled = CGFloat(level * weights[index]) * 16
        return base + scaled
    }
}
