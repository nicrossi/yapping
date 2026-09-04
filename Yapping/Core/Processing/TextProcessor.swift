import Foundation

enum ProcessorID: String, CaseIterable, Codable, Sendable, Identifiable {
    case passthrough
    case foundationModels

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .passthrough: "Raw transcript"
        case .foundationModels: "Apple Intelligence cleanup"
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
