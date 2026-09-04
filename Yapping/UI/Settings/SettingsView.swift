import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section("Dictation") {
                Picker("Language", selection: $settings.localeIdentifier) {
                    Text("System (\(Locale.current.localizedLanguageName))").tag(String?.none)
                    ForEach(appState.availableLocales, id: \.self) { id in
                        Text(Locale(identifier: id).localizedLanguageName).tag(String?.some(id))
                    }
                }
                Picker("Speech engine", selection: $settings.engineID) {
                    ForEach(EngineID.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
            }
            Section {
                Picker("Cleanup", selection: $settings.processorID) {
                    ForEach(ProcessorID.allCases) { processor in
                        Text(processor.displayName).tag(processor)
                    }
                }
                if settings.processorID == .foundationModels, let reason = appState.cleanupUnavailableReason {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Text cleanup")
            } footer: {
                Text("Apple Intelligence cleanup removes filler words and fixes punctuation, entirely on-device.")
            }
            Section("Permissions") {
                PermissionsChecklist()
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
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
