import AVFoundation
import Speech
import os

/// Apple's on-device `SpeechAnalyzer` (macOS 26+). Streams volatile partials while recording,
/// then finalizes when the audio stream ends.
final class SpeechAnalyzerEngine: TranscriptionEngine {
    let id: EngineID = .speechAnalyzer
    private let locale: Locale
    private let logger = Logger(subsystem: "com.nicorossi.yapping", category: "speech")

    init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Locale actually used after matching against `SpeechTranscriber.supportedLocales`.
    private let resolvedLocale = OSAllocatedUnfairLock<Locale?>(initialState: nil)

    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    static func installedLocales() async -> [Locale] {
        await SpeechTranscriber.installedLocales
    }

    private let prepared = OSAllocatedUnfairLock(initialState: false)

    func prepare() async throws {
        if prepared.withLock({ $0 }) { return }
        let resolved = try await resolveLocale()
        let transcriber = makeTranscriber(locale: resolved)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            logger.notice("Ensuring speech assets for \(resolved.identifier, privacy: .public)")
            try await request.downloadAndInstall()
        }
        prepared.withLock { $0 = true }
    }

    private func resolveLocale() async throws -> Locale {
        if let cached = resolvedLocale.withLock({ $0 }) { return cached }
        let supported = await Self.supportedLocales()
        guard let resolved = LocaleResolver.resolve(preferred: locale, from: supported) else {
            throw TranscriptionError.unsupportedLocale(locale)
        }
        if resolved.identifier(.bcp47) != locale.identifier(.bcp47) {
            logger.info("Locale \(self.locale.identifier, privacy: .public) → \(resolved.identifier, privacy: .public)")
        }
        resolvedLocale.withLock { $0 = resolved }
        return resolved
    }

    func transcribe(_ audio: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        let logger = self.logger
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let locale = try await resolveLocale()
                    let transcriber = makeTranscriber(locale: locale)
                    let analyzer = SpeechAnalyzer(modules: [transcriber])
                    guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                        throw TranscriptionError.noAudioFormat
                    }

                    let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)

                    let feeder = Task {
                        var converter: AVAudioConverter?
                        var chunks = 0
                        var frames: AVAudioFrameCount = 0
                        var peak: Float = 0
                        for await chunk in audio {
                            if Task.isCancelled { break }
                            peak = max(peak, chunk.buffer.normalizedLevel())
                            let converted = try AudioResampler.convert(chunk.buffer, to: targetFormat, reusing: &converter)
                            chunks += 1
                            frames += converted.frameLength
                            inputBuilder.yield(AnalyzerInput(buffer: converted))
                        }
                        inputBuilder.finish()
                        let seconds = Double(frames) / targetFormat.sampleRate
                        logger.info("Fed \(chunks, privacy: .public) chunks, \(seconds, format: .fixed(precision: 2), privacy: .public)s @ \(targetFormat.sampleRate, privacy: .public) Hz to analyzer; peak level \(peak, format: .fixed(precision: 2), privacy: .public); target format \(targetFormat, privacy: .public)")
                    }

                    let collector = Task { () -> String in
                        var finalized = ""
                        var volatile = ""
                        for try await result in transcriber.results {
                            let text = String(result.text.characters)
                            logger.debug("result final=\(result.isFinal, privacy: .public): \(text, privacy: .public)")
                            if result.isFinal {
                                finalized += text
                                volatile = ""
                            } else {
                                volatile = text
                            }
                            continuation.yield(TranscriptUpdate(text: finalized + volatile, isFinal: false))
                        }
                        if !volatile.isEmpty {
                            // The analyzer ended with an unfinalized tail; keep it rather than lose words.
                            logger.notice("Keeping unfinalized tail (\(volatile.count, privacy: .public) chars)")
                            finalized += volatile
                        }
                        return finalized
                    }

                    try await analyzer.start(inputSequence: inputSequence)
                    try await feeder.value
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    let text = try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    logger.notice("Final transcript: \(text.count, privacy: .public) chars")
                    continuation.yield(TranscriptUpdate(text: text, isFinal: true))
                    continuation.finish()
                } catch {
                    logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }
}
