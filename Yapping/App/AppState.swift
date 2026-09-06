import Foundation
import Observation
import os

/// Root observable state for the app. Owned by `YappingApp`, injected via `.environment`.
@MainActor
@Observable
final class AppState {
    let settings = AppSettings()
    let permissionsService = PermissionsService()
    let session: DictationSession
    let hotkey = HotkeyMonitor()

    private(set) var permissions = PermissionsStatus()
    /// BCP-47 identifiers the active speech engine supports, for the language picker.
    private(set) var availableLocales: [String] = []
    /// Which of those already have their model downloaded.
    private(set) var installedLocales: Set<String> = []

    private var overlay: OverlayPanelController?
    private var engines: [EngineID: any TranscriptionEngine] = [:]
    private var permissionsPollTask: Task<Void, Never>?
    private var hotkeyBootstrapTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.nicorossi.yapping", category: "app")

    init() {
        session = DictationSession(
            audio: AudioCapture(),
            engine: PlaceholderEngine(),
            processor: PassthroughProcessor(),
            inserter: PasteboardTextInserter()
        )
        overlay = OverlayPanelController(session: session)

        hotkey.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .pressed: session.beginRecording()
            case .released: session.endRecording()
            }
        }
        settings.onChange = { [weak self] in self?.applySettings() }

        applySettings()
        refreshPermissions()
        bootstrapHotkey()
        Task { await loadAvailableLocales() }
    }

    // MARK: - Derived UI state

    enum MenuBarState { case idle, active, busy, attention }

    var menuBarState: MenuBarState {
        switch session.state {
        case .recording, .done: .active
        case .transcribing, .processing, .inserting: .busy
        case .failed: .attention
        case .idle: permissions.allGranted ? .idle : .attention
        }
    }

    var statusLine: String {
        guard permissions.allGranted else { return Copy.needsPermissions }
        switch engineReadiness {
        case .loading: return Copy.loadingModel
        case .failed(let message): return message
        case .ready: return "\(Copy.ready) · \(settings.engineID.displayName) · \(settings.preferredLocale.localizedLanguageName)"
        }
    }

    var cleanupUnavailableReason: String? {
        FoundationModelsProcessor.unavailableReason
    }

    // MARK: - Settings

    enum EngineReadiness: Equatable { case ready, loading, failed(String) }
    private(set) var engineReadiness: EngineReadiness = .loading
    private var warmUpTask: Task<Void, Never>?

    /// Rebuilds the pipeline from current settings and warms it up.
    func applySettings() {
        session.engine = engine(for: settings.engineID)
        session.processor = processor(for: settings.processorID)
        hotkey.secondaryKey = settings.pushToTalkSecondary
        warmUpTask?.cancel()
        engineReadiness = .loading
        warmUpTask = Task { [weak self] in
            guard let self else { return }
            let error = await session.warmUp()
            guard !Task.isCancelled else { return }
            engineReadiness = error.map { .failed($0.localizedDescription) } ?? .ready
        }
    }

    func loadAvailableLocales() async {
        let supported = await SpeechAnalyzerEngine.supportedLocales()
        let installed = await SpeechAnalyzerEngine.installedLocales()
        // Only the three languages this user dictates in.
        let shown = ["en-US", "es-MX", "es-CL"]
        let supportedIDs = Set(supported.map { $0.identifier(.bcp47) })
        availableLocales = shown.filter(supportedIDs.contains)
        installedLocales = Set(installed.map { $0.identifier(.bcp47) })
    }

    /// The supported locale the current selection actually resolves to (e.g. system es-AR → es-MX).
    var resolvedLanguageName: String {
        resolvedLocale()?.localizedLanguageName ?? settings.preferredLocale.localizedLanguageName
    }

    /// False when the resolved model still needs to download on first use.
    var isSelectedLanguageInstalled: Bool {
        guard !installedLocales.isEmpty, let resolved = resolvedLocale() else { return true }
        return installedLocales.contains(resolved.identifier(.bcp47))
    }

    private func resolvedLocale() -> Locale? {
        guard !availableLocales.isEmpty else { return nil }
        let supported = availableLocales.map(Locale.init(identifier:))
        return LocaleResolver.resolve(preferred: settings.preferredLocale, from: supported)
    }

    private func engine(for id: EngineID) -> any TranscriptionEngine {
        // Engines are keyed by id + locale so a language change gets a fresh, correctly-resolved engine.
        let locale = settings.preferredLocale
        switch id {
        case .speechAnalyzer:
            return SpeechAnalyzerEngine(locale: locale)
        case .parakeet:
            // Parakeet holds ~600 MB of CoreML models; keep one instance alive across setting changes.
            if let cached = engines[.parakeet] { return cached }
            let engine = ParakeetEngine(locale: locale)
            engines[.parakeet] = engine
            return engine
        }
    }

    private func processor(for id: ProcessorID) -> any TextProcessor {
        switch id {
        case .passthrough: PassthroughProcessor()
        case .quick: QuickCleanupProcessor()
        case .foundationModels: FoundationModelsProcessor()
        }
    }

    // MARK: - Permissions / hotkey

    func refreshPermissions() {
        let previous = permissions
        permissions = permissionsService.current()
        if permissions != previous {
            logger.notice("Permissions: accessibility=\(self.permissions.accessibility, privacy: .public) microphone=\(String(describing: self.permissions.microphone), privacy: .public)")
        }
        if permissions.accessibility, !hotkey.isRunning {
            hotkey.start()
        }
    }

    /// Accessibility trust has no change notification; poll while a UI that shows it is visible.
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

    /// Tear everything down before the process exits: stop the global tap and the mic,
    /// cancel background tasks. Called from Quit.
    func shutDown() {
        hotkey.stop()
        session.cancel()
        stopPermissionsPolling()
        hotkeyBootstrapTask?.cancel()
        logger.notice("Shutting down")
    }

    /// Keep trying to start the Fn tap until Accessibility is granted (user may grant it later).
    private func bootstrapHotkey() {
        guard !hotkey.isRunning else { return }
        hotkeyBootstrapTask = Task { [weak self] in
            while let self, !Task.isCancelled, !hotkey.isRunning {
                refreshPermissions()
                if hotkey.isRunning { break }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

/// Stand-in used only until `applySettings()` installs the real engine during init.
private struct PlaceholderEngine: TranscriptionEngine {
    let id: EngineID = .speechAnalyzer
    func prepare() async throws {}
    func transcribe(_ audio: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        AsyncThrowingStream { $0.finish(throwing: TranscriptionError.modelUnavailable("not configured")) }
    }
}
