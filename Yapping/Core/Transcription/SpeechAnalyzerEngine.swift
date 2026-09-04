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

    func prepare() async throws {
        let resolved = try await resolveLocale()
        let transcriber = makeTranscriber(locale: resolved)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            logger.info("Ensuring speech assets for \(resolved.identifier, privacy: .public)")
            try await request.downloadAndInstall()
        }
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
                        for await chunk in audio {
                            if Task.isCancelled { break }
                            let converted = try AudioResampler.convert(chunk.buffer, to: targetFormat, reusing: &converter)
                            inputBuilder.yield(AnalyzerInput(buffer: converted))
                        }
                        inputBuilder.finish()
                    }

                    let collector = Task { () -> String in
                        var finalized = ""
                        for try await result in transcriber.results {
                            let text = String(result.text.characters)
                            if result.isFinal {
                                finalized += text
                                continuation.yield(TranscriptUpdate(text: finalized, isFinal: false))
                            } else {
                                continuation.yield(TranscriptUpdate(text: finalized + text, isFinal: false))
                            }
                        }
                        return finalized
                    }

                    try await analyzer.start(inputSequence: inputSequence)
                    try await feeder.value
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    let text = try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    logger.info("Final transcript: \(text.count, privacy: .public) chars")
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
