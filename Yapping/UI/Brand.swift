import SwiftUI

/// Yapping identity tokens. Glass-wave direction: violet → pink gradient, white wave.
enum Brand {
    static let name = "yapping"

    static let violet = Color(red: 0x7C / 255, green: 0x5C / 255, blue: 1.0)
    static let pink = Color(red: 1.0, green: 0x5C / 255, blue: 0xA8 / 255)

    static let gradient = LinearGradient(
        colors: [violet, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Horizontal variant for level bars and inline text.
    static let gradientHorizontal = LinearGradient(
        colors: [violet, pink],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// Playful copy used in the pill and menus. Keep it short; it flashes for under a second.
enum Copy {
    static let listening = "Go on, yap."
    static let transcribing = "Catching that…"
    static let processing = "Tidying up…"
    static let inserting = "Dropping it in…"
    static let done = "Yapped."
    static let holdHint = "Hold **Fn** to yap"
    static let ready = "Ready to yap"
    static let needsPermissions = "Needs a couple of permissions"
    static let micMuted = "Mic's muted. No yapping."
    static let loadingModel = "Warming up…"
}

/// Lowercase gradient wordmark.
struct Wordmark: View {
    var size: CGFloat = 15

    var body: some View {
        Text(Brand.name)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .tracking(-0.3)
            .foregroundStyle(Brand.gradientHorizontal)
    }
}

/// The wave glyph rendered in SwiftUI, for headers and the about box.
struct WaveGlyph: View {
    var size: CGFloat = 28
    private let heights: [CGFloat] = [0.34, 0.62, 1.0, 0.62, 0.34]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.226, style: .continuous)
                .fill(Brand.gradient)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.226, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                }
            HStack(spacing: size * 0.052) {
                ForEach(heights.indices, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(0.96))
                        .frame(width: size * 0.075, height: size * 0.48 * heights[i])
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Brand.violet.opacity(0.35), radius: size * 0.2, y: size * 0.08)
    }
}
