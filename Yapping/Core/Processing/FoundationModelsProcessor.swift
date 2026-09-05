import Foundation
import FoundationModels
import os

/// Cleans up dictation with Apple's on-device foundation model (needs Apple Intelligence enabled).
/// Keeps one prewarmed session ready so the first request after a pause doesn't pay model load time.
final class FoundationModelsProcessor: TextProcessor, @unchecked Sendable {
    let id: ProcessorID = .foundationModels
    let timeout: Duration
    /// Inputs shorter than this are inserted untouched; not worth a model round-trip.
    let minimumWords: Int

    private let logger = Logger(subsystem: "com.nicorossi.yapping", category: "cleanup")
    /// A fresh, prewarmed session waiting for the next request. Sessions are single-use here so
    /// the transcript never accumulates across dictations.
    private let warmSession = OSAllocatedUnfairLock<LanguageModelSession?>(initialState: nil)

    init(timeout: Duration = .seconds(8), minimumWords: Int = 3) {
        self.timeout = timeout
        self.minimumWords = minimumWords
    }

    /// Short and imperative: every instruction token is prefill cost on each request.
    static let instructions = """
    Rewrite dictated speech as clean written text. Remove filler words (um, uh, like, you know, \
    I mean, basically) and false starts. Apply the speaker's self-corrections. Fix punctuation \
    and capitalization. Keep the words, meaning, tone and language. Never translate, answer, \
    or add anything. Reply with the cleaned text only.
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

    func prepare() async {
        guard await isAvailable() else { return }
        guard warmSession.withLock({ $0 == nil }) else { return }
        let session = makeSession()
        session.prewarm()
        warmSession.withLock { $0 = session }
    }

    func process(_ text: String, context: ProcessingContext) async throws -> String {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        guard wordCount >= minimumWords else { return text }
        guard DictationHeuristics.needsCleanup(text) else {
            logger.info("Cleanup skipped: transcript already clean (\(wordCount, privacy: .public) words)")
            return text
        }

        let started = ContinuousClock.now
        let warm = warmSession.withLock { session -> LanguageModelSession? in
            defer { session = nil }
            return session
        }
        let session = warm ?? makeSession()
        // Warm the next one while this request runs.
        Task { await self.prepare() }

        let options = GenerationOptions(
            sampling: .greedy,
            temperature: 0,
            maximumResponseTokens: max(64, wordCount * 3)
        )
        let prompt = "Dictation:\n\(text)"

        let cleaned = try await withTimeout(timeout) {
            try await session.respond(to: prompt, options: options).content
        }
        let result = Self.stripWrapping(cleaned)
        let elapsed = ContinuousClock.now - started
        logger.notice(
            "Cleaned \(text.count, privacy: .public) → \(result.count, privacy: .public) chars in \(Int(elapsed / .milliseconds(1)), privacy: .public)ms (\(warm == nil ? "cold" : "warm", privacy: .public) session)"
        )
        guard !result.isEmpty else { return text }
        return result
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Self.instructions)
    }

    /// Models sometimes wrap the answer in quotes or a label; undo that.
    private static func stripWrapping(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Cleaned text:", "Cleaned:", "Output:", "Text:"] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if t.count >= 2, t.first == "\"", t.last == "\"" {
            t = String(t.dropFirst().dropLast())
        }
        return t
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

/// Cheap text checks that decide whether a transcript is worth a model round-trip.
/// SpeechAnalyzer already punctuates and capitalizes, so most dictations need nothing.
enum DictationHeuristics {
    /// Filler tokens / phrases, matched on word boundaries, case-insensitive.
    static let fillers: [String] = [
        "um", "uh", "uhm", "umm", "erm", "hmm", "mm",
        "you know", "i mean", "kind of like", "sort of like",
        "basically", "literally", "actually",
    ]
    /// Phrases that signal a self-correction the model should resolve.
    static let corrections: [String] = [
        "no wait", "wait no", "i mean", "scratch that", "actually no", "make that", "or rather",
    ]

    static func needsCleanup(_ text: String) -> Bool {
        let lower = " " + text.lowercased() + " "
        for phrase in fillers where containsWord(lower, phrase) { return true }
        for phrase in corrections where lower.contains(" " + phrase + " ") || lower.contains(" " + phrase) { return true }
        if hasStutter(lower) { return true }
        // Long unpunctuated runs: let the model add structure.
        let words = text.split(whereSeparator: \.isWhitespace)
        let punctuation = text.filter { ".,;:!?".contains($0) }.count
        if words.count >= 25, punctuation <= words.count / 25 { return true }
        return false
    }

    private static func containsWord(_ padded: String, _ phrase: String) -> Bool {
        // Match "um", "um,", "um." etc. by checking with common trailing punctuation.
        for suffix in [" ", ", ", ". ", "? ", "! "] where padded.contains(" " + phrase + suffix) { return true }
        return false
    }

    /// "I I think" / "the the" — repeated consecutive words.
    private static func hasStutter(_ padded: String) -> Bool {
        let words = padded.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: .punctuationCharacters) }
        for i in 1..<max(1, words.count) where words[i] == words[i - 1] && words[i].count > 1 { return true }
        return false
    }
}
