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
                // Grid keeps the labels in one column and the controls in another, so both
                // pickers start and end at the same x.
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Cleanup").gridColumnAlignment(.leading)
                        Picker("Cleanup", selection: $settings.processorID) {
                            ForEach(ProcessorID.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                    GridRow {
                        Text("Language")
                        Picker("Language", selection: $settings.localeIdentifier) {
                            Text("System (\(appState.resolvedLanguageName))").tag(String?.none)
                            ForEach(appState.availableLocales, id: \.self) { id in
                                Text(Locale(identifier: id).localizedLanguageName).tag(String?.some(id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                }
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
            Button("Settings") {
                // Accessory apps must activate first, or openSettings() no-ops. Let the menu
                // window dismiss first, then bring the app forward and show Settings.
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
            }
            .keyboardShortcut(",")
            Spacer()
            Button("Quit") {
                appState.shutDown()
                // Dismiss the menu window first, then terminate, so the quit is reliable.
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(MenuActionButtonStyle())
        .font(.callout)
        .padding(.horizontal, -9)  // let the hover highlight extend to the row edges
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

/// Bordered look with hover + press feedback, for the small "Grant" buttons.
struct PressableBorderedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleContent(configuration: configuration)
    }

    struct StyleContent: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(opacity), in: Capsule())
                .foregroundStyle(.white)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .onHover { hovering = $0 }
                .animation(Motion.press, value: hovering)
                .animation(Motion.press, value: configuration.isPressed)
        }

        private var opacity: Double {
            if configuration.isPressed { return 0.8 }
            return hovering ? 1 : 0.9
        }
    }
}
