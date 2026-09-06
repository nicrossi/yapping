import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section {
                if appState.availableLocales.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading languages…").foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Language", selection: $settings.localeIdentifier) {
                        Text("Follow System (\(appState.resolvedLanguageName))").tag(String?.none)
                        Divider()
                        ForEach(appState.availableLocales, id: \.self) { id in
                            Text(Locale(identifier: id).localizedLanguageName).tag(String?.some(id))
                        }
                    }
                    if !appState.isSelectedLanguageInstalled {
                        Label("The \(appState.resolvedLanguageName) model downloads on first use.",
                              systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("Speech engine", selection: $settings.engineID) {
                    ForEach(EngineID.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                Picker("Also trigger with", selection: $settings.pushToTalkSecondary) {
                    Text("Nothing (Fn only)").tag(PushToTalkKey?.none)
                    ForEach(PushToTalkKey.allCases) { key in
                        Text(key.displayName).tag(PushToTalkKey?.some(key))
                    }
                }
            } header: {
                Text("Dictation")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Speech is recognized on-device in the selected language. Apple offers regional variants only; pick the closest.")
                    Text("Holding **Fn** always starts dictation. To use another keyboard, map a key to one of the triggers above. F13–F19 are safest; a modifier like Right Option also types accents, so it starts dictation whenever you use it. On QMK, map the key to e.g. `KC_F13`.")
                }
            }
            Section {
                Picker("Cleanup", selection: $settings.processorID) {
                    ForEach(ProcessorID.allCases) { processor in
                        Text(processor.displayName).tag(processor)
                    }
                }
                Text(settings.processorID.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.processorID == .foundationModels, let reason = appState.cleanupUnavailableReason {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Text cleanup")
            } footer: {
                Text("Everything runs on this Mac. Nothing is sent anywhere.")
            }
            Section("Permissions") {
                PermissionsChecklist()
            }
            Section {
                HStack(spacing: 12) {
                    WaveGlyph(size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Wordmark(size: 18)
                        Text("Push-to-talk dictation. Everything stays on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 500)
        .task { await appState.loadAvailableLocales() }
        .onAppear { appState.startPermissionsPolling() }
        .onDisappear { appState.stopPermissionsPolling() }
    }
}

extension Locale {
    /// "English (United States)" style name in the user's UI language.
    var localizedLanguageName: String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
