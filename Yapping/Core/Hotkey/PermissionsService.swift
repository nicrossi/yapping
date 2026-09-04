import AppKit
import ApplicationServices
import AVFoundation

struct PermissionsStatus: Equatable, Sendable {
    var accessibility = false
    var microphone: AVAuthorizationStatus = .notDetermined

    var microphoneGranted: Bool { microphone == .authorized }
    var allGranted: Bool { accessibility && microphoneGranted }
}

/// Reads and requests the two TCC permissions Yapping needs:
/// Accessibility (global Fn key tap + synthetic ⌘V) and Microphone.
@MainActor
final class PermissionsService {
    func current() -> PermissionsStatus {
        PermissionsStatus(
            accessibility: AXIsProcessTrusted(),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio)
        )
    }

    /// Shows the system prompt that deep-links to the Accessibility pane (only once per install).
    func requestAccessibility() {
        // Literal key: `kAXTrustedCheckOptionPrompt` is a C global and not concurrency-safe under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
