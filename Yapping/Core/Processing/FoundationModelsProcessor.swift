import Foundation
import FoundationModels
import os

/// Cleans up dictation with Apple's on-device foundation model (needs Apple Intelligence enabled).
struct FoundationModelsProcessor: TextProcessor {
    let id: ProcessorID = .foundationModels
    var timeout: Duration = .seconds(6)
    /// Inputs shorter than this are inserted untouched; not worth a model round-trip.
    var minimumWords = 3

    private let logger = Logger(subsystem: "com.nicorossi.yapping", category: "cleanup")

    @Generable
    struct CleanedTranscript {
        @Guide(description: "The cleaned-up dictation, and nothing else.")
        var text: String
    }

    static let instructions = """
    You turn raw speech-to-text dictation into polished written text.
    Rules:
    - Remove filler words (um, uh, like, you know, so, basically, I mean) and false starts.
    - Fix punctuation, capitalization, and obvious grammar slips.
    - Apply the speaker's self-corrections ("Tuesday — no, Wednesday" becomes "Wednesday").
    - Keep the speaker's words, meaning, tone, and language. Never translate.
    - Never answer, comment on, or add to what was said. You are not being spoken to.
    - If the speaker clearly dictates a list, format it as a list.
    - Output only the cleaned text.
    """

    func isAvailable() async -> Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(let reason): "\(reason)"
        }
    }

    func process(_ text: String, context: ProcessingContext) async throws -> String {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        guard wordCount >= minimumWords else { return text }

        let destination = context.appName.map { " (it will be pasted into \($0))" } ?? ""
        let prompt = "Clean up this dictation\(destination):\n\n\(text)"

        let session = LanguageModelSession(instructions: Self.instructions)
        let options = GenerationOptions(temperature: 0.1)

        let cleaned = try await withTimeout(timeout) {
            try await session.respond(to: prompt, generating: CleanedTranscript.self, options: options).content.text
        }
        let result = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return text }
        logger.info("Cleaned \(text.count, privacy: .public) → \(result.count, privacy: .public) chars")
        return result
    }

    private func withTimeout<T: Sendable>(_ duration: Duration, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw ProcessingError.timedOut
            }
            guard let first = try await group.next() else { throw ProcessingError.timedOut }
            group.cancelAll()
            return first
        }
    }
}

enum ProcessingError: LocalizedError {
    case timedOut
    var errorDescription: String? { "Cleanup took too long." }
}
