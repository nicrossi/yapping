import Foundation

/// Instant, rule-based cleanup. Conservative: only removes unambiguous vocal fillers, collapses
/// stutters, and tidies punctuation/capitalization. Runs in microseconds.
struct QuickCleanupProcessor: TextProcessor {
    let id: ProcessorID = .quick

    func isAvailable() async -> Bool { true }

    func process(_ text: String, context: ProcessingContext) async throws -> String {
        Self.clean(text)
    }

    /// Standalone vocal fillers. Case-insensitive, whole-word, optional trailing comma/period.
    private static let fillerPattern: NSRegularExpression = {
        let words = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "hmm", "hm", "mm", "mhm"]
        let phrases = ["you know", "i mean"]
        // Phrases only when set off by commas, e.g. "It's, you know, fine."
        let phraseAlt = phrases.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let wordAlt = words.joined(separator: "|")
        let pattern = "(?i)(?:,\\s*)?\\b(?:\(wordAlt))\\b[,.]?\\s*|(?:,\\s*)\\b(?:\(phraseAlt))\\b,\\s*"
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// "the the", "I I" — repeated word, keeps the first.
    private static let stutterPattern = try! NSRegularExpression(pattern: "(?i)\\b(\\w+)(?:[,]?\\s+\\1\\b)+")

    static func clean(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }

        s = fillerPattern.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        s = stutterPattern.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")

        // Whitespace + punctuation spacing.
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "([,.;:!?])\\1+", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "^[,.;:\\s]+", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }

        // Capitalize sentence starts.
        s = capitalizeSentences(s)

        // Terminal punctuation.
        if let last = s.last, !".!?…\"')".contains(last) {
            s += "."
        }
        return s
    }

    private static func capitalizeSentences(_ s: String) -> String {
        var out = ""
        var capitalizeNext = true
        for ch in s {
            if capitalizeNext, ch.isLetter {
                out.append(contentsOf: String(ch).uppercased())
                capitalizeNext = false
            } else {
                out.append(ch)
            }
            if ".!?".contains(ch) { capitalizeNext = true }
        }
        return out
    }
}
