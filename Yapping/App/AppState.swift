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
    }

    // MARK: - Derived UI state

    var menuBarSymbol: String {
        switch session.state {
        case .recording: "waveform.circle.fill"
        case .transcribing, .processing, .inserting: "ellipsis.circle"
        case .failed: "exclamationmark.circle"
        case .idle: permissions.allGranted ? "waveform" : "waveform.badge.exclamationmark"
        }
    }

    var statusLine: String {
        guard permissions.allGranted else { return "Needs permissions" }
        switch engineReadiness {
        case .loading: return "Loading \(settings.engineID.displayName) model…"
        case .failed(let message): return message
        case .ready: return "\(settings.engineID.displayName) · \(settings.preferredLocale.localizedLanguageName)"
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
        let locales = await SpeechAnalyzerEngine.supportedLocales()
        availableLocales = locales
            .map { $0.identifier(.bcp47) }
            .sorted { Locale(identifier: $0).localizedLanguageName < Locale(identifier: $1).localizedLanguageName }
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
        case .foundationModels: FoundationModelsProcessor()
        }
    }

    // MARK: - Permissions / hotkey

    func refreshPermissions() {
        permissions = permissionsService.current()
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
