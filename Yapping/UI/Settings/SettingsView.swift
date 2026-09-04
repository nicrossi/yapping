import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Permissions") {
                PermissionsChecklist()
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 260)
        .onAppear { appState.startPermissionsPolling() }
        .onDisappear { appState.stopPermissionsPolling() }
    }
}
