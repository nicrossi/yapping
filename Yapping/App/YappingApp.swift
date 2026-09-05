import SwiftUI

@main
struct YappingApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarLabel(state: appState.menuBarState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

/// Template glyphs for the menu bar. Custom wave mark when idle/active, SF Symbols for edge states.
struct MenuBarLabel: View {
    let state: AppState.MenuBarState

    var body: some View {
        switch state {
        case .idle:
            Image("MenuBarIdle")
        case .active:
            Image("MenuBarActive")
        case .busy:
            Image(systemName: "ellipsis.circle")
                .symbolRenderingMode(.hierarchical)
        case .attention:
            Image(systemName: "exclamationmark.circle")
                .symbolRenderingMode(.hierarchical)
        }
    }
}
