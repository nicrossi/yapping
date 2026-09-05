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
            } header: {
                Text("Dictation")
            } footer: {
                Text("Speech is recognized on-device in the selected language. Apple offers regional variants only; pick the closest.")
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
