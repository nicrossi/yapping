import Foundation

enum ProcessorID: String, CaseIterable, Codable, Sendable, Identifiable {
    case passthrough
    case quick
    case foundationModels

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .passthrough: "Raw transcript"
        case .quick: "Quick cleanup"
        case .foundationModels: "Apple Intelligence (deep, slower)"
        }
    }

    var detail: String {
        switch self {
        case .passthrough: "Exactly what the speech engine heard."
        case .quick: "Instant. Drops ums and uhs, fixes stutters, punctuation and capitalization."
        case .foundationModels: "On-device language model rewrites the text. Several seconds on M1."
        }
    }
}

/// What the processor knows about where the text is going.
struct ProcessingContext: Sendable {
    var appName: String?
    var bundleID: String?
    var locale: Locale = .current
}

/// Post-processes a raw transcript (filler removal, punctuation, formatting).
protocol TextProcessor: Sendable {
    var id: ProcessorID { get }
    func isAvailable() async -> Bool
    /// Warm up models/sessions so the first `process` call is fast. Optional.
    func prepare() async
    func process(_ text: String, context: ProcessingContext) async throws -> String
}

extension TextProcessor {
    func prepare() async {}
}
