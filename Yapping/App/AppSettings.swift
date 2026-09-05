import Foundation
import Observation

/// User preferences, persisted to `UserDefaults`. Changes are reported via `onChange`.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let engine = "engine"
        static let processor = "processor"
        static let locale = "localeIdentifier"
    }

    static let defaultLocaleIdentifier = "en-US"

    var onChange: (() -> Void)?

    var engineID: EngineID {
        didSet { persist(engineID.rawValue, Key.engine) }
    }

    var processorID: ProcessorID {
        didSet { persist(processorID.rawValue, Key.processor) }
    }

    /// BCP-47 identifier, or `nil` to follow the system language. Defaults to American English.
    var localeIdentifier: String? {
        didSet { persist(localeIdentifier, Key.locale) }
    }

    var preferredLocale: Locale {
        localeIdentifier.map { Locale(identifier: $0) } ?? .current
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        engineID = defaults.string(forKey: Key.engine).flatMap(EngineID.init(rawValue:)) ?? .speechAnalyzer
        processorID = defaults.string(forKey: Key.processor).flatMap(ProcessorID.init(rawValue:)) ?? .quick
        localeIdentifier = defaults.string(forKey: Key.locale) ?? Self.defaultLocaleIdentifier
    }

    private func persist(_ value: String?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        onChange?()
    }
}
