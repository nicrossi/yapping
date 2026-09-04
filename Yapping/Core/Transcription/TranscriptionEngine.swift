import Foundation

enum EngineID: String, CaseIterable, Codable, Sendable, Identifiable {
    case speechAnalyzer
    case parakeet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speechAnalyzer: "Apple Speech"
        case .parakeet: "Parakeet (NVIDIA)"
        }
    }
}

struct TranscriptUpdate: Equatable, Sendable {
    let text: String
    let isFinal: Bool
}

enum TranscriptionError: LocalizedError {
    case unsupportedLocale(Locale)
    case modelUnavailable(String)
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let locale): "Speech model does not support \(locale.identifier)."
        case .modelUnavailable(let why): "Speech model unavailable: \(why)"
        case .noAudioFormat: "Could not negotiate an audio format with the speech engine."
        }
    }
}

/// A speech-to-text backend. Implementations consume the microphone stream until it finishes
/// (the user released the key), then emit exactly one `isFinal == true` update and end.
/// Streaming engines may emit any number of non-final updates before that.
protocol TranscriptionEngine: Sendable {
    var id: EngineID { get }

    /// Loads or downloads models. Must be idempotent and cheap once ready.
    func prepare() async throws

    func transcribe(_ audio: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptUpdate, any Error>
}
