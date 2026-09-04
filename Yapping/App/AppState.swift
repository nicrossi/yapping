import Foundation
import Observation

/// Root observable state for the app. Owned by `YappingApp`, injected via `.environment`.
@MainActor
@Observable
final class AppState {
    let permissionsService = PermissionsService()

    private(set) var permissions = PermissionsStatus()
    private var permissionsPollTask: Task<Void, Never>?

    init() {
        refreshPermissions()
    }

    var menuBarSymbol: String {
        permissions.allGranted ? "waveform" : "waveform.badge.exclamationmark"
    }

    func refreshPermissions() {
        permissions = permissionsService.current()
    }

    /// Accessibility trust has no change notification; poll briefly while a UI that shows it is visible.
    func startPermissionsPolling() {
        guard permissionsPollTask == nil else { return }
        permissionsPollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopPermissionsPolling() {
        permissionsPollTask?.cancel()
        permissionsPollTask = nil
    }
}
