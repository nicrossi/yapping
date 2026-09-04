import AppKit
import SwiftUI

/// Floating, non-activating pill shown while a dictation cycle is in flight.
/// Never takes key focus so the target app keeps its first responder.
@MainActor
final class OverlayPanelController {
    private let panel: NSPanel
    private let session: DictationSession
    private let presentation = OverlayPresentation()
    private var hideTask: Task<Void, Never>?
    private var orderOutTask: Task<Void, Never>?

    // Extra room around the 44pt pill so scale/offset transitions never clip.
    private static let size = NSSize(width: 380, height: 72)
    private static let bottomMargin: CGFloat = 88
    /// Slightly longer than `Motion.exit` so the fade completes before the window disappears.
    private static let orderOutDelay: Duration = .milliseconds(140)

    init(session: DictationSession) {
        self.session = session

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = NSHostingView(
            rootView: OverlayView().environment(session).environment(presentation)
        )
        self.panel = panel

        session.onStateChange = { [weak self] state in
            self?.stateDidChange(state)
        }
    }

    private func stateDidChange(_ state: DictationSession.State) {
        hideTask?.cancel()
        switch state {
        case .idle:
            hide()
        case .failed:
            show()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: DictationSession.failureDisplayDuration)
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        default:
            show()
        }
    }

    private func show() {
        orderOutTask?.cancel()
        orderOutTask = nil
        if !panel.isVisible {
            position()
            panel.orderFrontRegardless()
        }
        // The SwiftUI content animates in (opacity + scale + rise); the window itself stays opaque.
        presentation.isVisible = true
    }

    private func hide() {
        guard panel.isVisible, presentation.isVisible else { return }
        presentation.isVisible = false
        orderOutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.orderOutDelay)
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    /// Bottom-center of the screen containing the mouse (usually where the user is typing).
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: frame.midX - Self.size.width / 2,
            y: frame.minY + Self.bottomMargin
        )
        panel.setFrameOrigin(origin)
    }
}
