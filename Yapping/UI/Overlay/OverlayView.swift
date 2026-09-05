import SwiftUI

/// Drives the pill's enter/exit; owned by `OverlayPanelController`.
@MainActor
@Observable
final class OverlayPresentation {
    var isVisible = false
}

struct OverlayView: View {
    @Environment(DictationSession.self) private var session
    @Environment(OverlayPresentation.self) private var presentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        pill
            .opacity(presentation.isVisible ? 1 : 0)
            .scaleEffect(scale, anchor: .bottom)
            .offset(y: reduceMotion || presentation.isVisible ? 0 : 6)
            .animation(presentation.isVisible ? Motion.enter : Motion.exit, value: presentation.isVisible)
            .padding(10)
    }

    private var scale: CGFloat {
        if reduceMotion { return 1 }
        return presentation.isVisible ? 1 : 0.96
    }

    private var pill: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18, height: 18)
                .contentTransition(.symbolEffect(.replace.downUp.byLayer))

            ZStack(alignment: .leading) {
                Text(caption)
                    .id(captionIdentity)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
            }
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .truncationMode(.head)
            .foregroundStyle(captionColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(Motion.swap, value: captionIdentity)

            trailing
                .frame(width: 26, height: 20)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .animation(Motion.swap, value: session.state)
    }

    // MARK: Pieces

    @ViewBuilder
    private var statusIcon: some View {
        switch session.state {
        case .recording:
            Image(systemName: "mic.fill")
                .foregroundStyle(Brand.gradient)
        case .transcribing, .processing, .inserting:
            Image(systemName: "sparkles")
                .foregroundStyle(Brand.gradient)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Brand.gradient)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .idle:
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch session.state {
        case .recording:
            LevelBars(level: session.level)
                .transition(.opacity)
        case .transcribing, .processing, .inserting:
            ProgressView()
                .controlSize(.small)
                .transition(.opacity)
        default:
            Color.clear
        }
    }

    private var caption: String {
        switch session.state {
        case .recording:
            session.partialTranscript.isEmpty ? Copy.listening : session.partialTranscript
        case .transcribing:
            session.partialTranscript.isEmpty ? Copy.transcribing : session.partialTranscript
        case .processing: Copy.processing
        case .inserting: Copy.inserting
        case .done: Copy.done
        case .failed(let message): message
        case .idle: ""
        }
    }

    /// Only *kinds* of caption crossfade; live transcript words update in place with no animation.
    private var captionIdentity: String {
        switch session.state {
        case .recording, .transcribing:
            session.partialTranscript.isEmpty ? "waiting" : "transcript"
        case .processing: "processing"
        case .inserting: "inserting"
        case .done: "done"
        case .failed: "failed"
        case .idle: "idle"
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

/// Motion tokens. Fast, ease-out, exits quicker than enters.
enum Motion {
    static let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    static let exit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.11)
    static let swap = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
    static let level = Animation.spring(duration: 0.12, bounce: 0)
}

/// Five bars that follow the input level. Center bars react most; outer bars lag behind.
struct LevelBars: View {
    let level: Float
    private let weights: [Float] = [0.5, 0.8, 1.0, 0.8, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(weights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Brand.gradientHorizontal)
                    .frame(width: 3, height: height(for: i))
            }
        }
        .frame(height: 20)
        .animation(Motion.level, value: level)
    }

    private func height(for index: Int) -> CGFloat {
        let floor: CGFloat = 3
        let range: CGFloat = 17
        // Slight curve so quiet speech still reads as movement.
        let shaped = pow(CGFloat(level), 0.7)
        return floor + shaped * CGFloat(weights[index]) * range
    }
}

/// Press feedback for any pressable control: subtle scale, fast ease-out.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
