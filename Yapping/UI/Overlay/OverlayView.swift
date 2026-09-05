import SwiftUI

/// Drives the pill's enter/exit; owned by `OverlayPanelController`.
@MainActor
@Observable
final class OverlayPresentation {
    var isVisible = false
}

/// Minimal pill: a dark capsule holding only the waveform. No text, no icons.
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
            .padding(8)
    }

    private var scale: CGFloat {
        if reduceMotion { return 1 }
        return presentation.isVisible ? 1 : 0.96
    }

    private var pill: some View {
        Waveform(levels: session.levelHistory, mode: mode, reduceMotion: reduceMotion)
            .frame(width: 120, height: 24)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.09).opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    private var mode: Waveform.Mode {
        switch session.state {
        case .recording: .live
        case .transcribing, .processing, .inserting: .thinking
        case .done: .done
        case .failed: .failed
        case .idle: .idle
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

/// Scrolling bar waveform. In `.live` the bars mirror the last ~2.4 s of mic level (newest on the right).
/// In `.thinking` they breathe with a slow travelling wave. `.done` collapses to a flat line; `.failed` goes orange.
struct Waveform: View {
    enum Mode: Equatable { case idle, live, thinking, done, failed }

    let levels: [Float]
    let mode: Mode
    var reduceMotion = false

    private let barWidth: CGFloat = 2.5
    private let minHeight: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: mode != .thinking || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth) {
                ForEach(levels.indices, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(fill)
                        .frame(width: barWidth, height: height(at: i, time: t))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(mode == .live ? Motion.level : Motion.swap, value: levels)
        .animation(Motion.swap, value: mode)
    }

    private var fill: AnyShapeStyle {
        switch mode {
        case .failed: AnyShapeStyle(Color.orange)
        case .idle: AnyShapeStyle(Color.white.opacity(0.35))
        default: AnyShapeStyle(Brand.gradientHorizontal)
        }
    }

    private func height(at i: Int, time: Double) -> CGFloat {
        let maxHeight: CGFloat = 24
        switch mode {
        case .live:
            // Perceptual curve so quiet speech still reads as movement.
            let shaped = pow(CGFloat(levels[i]), 0.65)
            return minHeight + shaped * (maxHeight - minHeight)
        case .thinking:
            if reduceMotion { return minHeight + 4 }
            // Slow travelling sine, small amplitude.
            let phase = time * 2.2 - Double(i) * 0.45
            let wave = (sin(phase) + 1) / 2  // 0...1
            return minHeight + CGFloat(wave) * 7
        case .done, .idle, .failed:
            return minHeight
        }
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
