import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if appState.permissions.allGranted {
                @Bindable var settings = appState.settings
                Label {
                    Text(.init(Copy.holdHint))
                } icon: {
                    Image(systemName: "hand.tap")
                }
                .foregroundStyle(.secondary)
                Picker("Cleanup", selection: $settings.processorID) {
                    ForEach(ProcessorID.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                .font(.callout)
            } else {
                PermissionsChecklist()
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { appState.startPermissionsPolling() }
        .onDisappear { appState.stopPermissionsPolling() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            WaveGlyph(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Wordmark(size: 15)
                Text(appState.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { openSettings() }
                .keyboardShortcut(",")
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(PressableButtonStyle())
        .font(.callout)
    }
}

struct PermissionsChecklist: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PermissionRow(
                title: "Accessibility",
                detail: "Needed to detect the Fn key and paste text.",
                granted: appState.permissions.accessibility
            ) {
                appState.permissionsService.requestAccessibility()
                appState.permissionsService.openAccessibilitySettings()
            }
            PermissionRow(
                title: "Microphone",
                detail: "Needed to hear you.",
                granted: appState.permissions.microphoneGranted
            ) {
                Task {
                    let granted = await appState.permissionsService.requestMicrophone()
                    if !granted { appState.permissionsService.openMicrophoneSettings() }
                    appState.refreshPermissions()
                }
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant", action: action)
                    .controlSize(.small)
                    .buttonStyle(PressableBorderedStyle())
            }
        }
    }
}

/// Bordered look with press feedback, for the small "Grant" buttons.
struct PressableBorderedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.85 : 1), in: Capsule())
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
