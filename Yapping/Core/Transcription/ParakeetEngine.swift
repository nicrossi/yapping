import AVFoundation
import FluidAudio
import os

/// NVIDIA Parakeet TDT 0.6B (v3, multilingual) via FluidAudio on CoreML.
/// Batch engine: buffers audio while the key is held, transcribes on release.
actor ParakeetEngine: TranscriptionEngine {
    nonisolated let id: EngineID = .parakeet

    private let locale: Locale
    private var manager: AsrManager?
    private var loading: Task<AsrManager, any Error>?
    private let logger = Logger(subsystem: "com.nicorossi.yapping", category: "parakeet")

    /// Ignore recordings shorter than this (samples at 16 kHz); the model hallucinates on near-silence.
    private static let minimumSamples = 16_000 / 4  // 250 ms

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func prepare() async throws {
        _ = try await loadedManager()
    }

    nonisolated func transcribe(_ audio: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let manager = try await self.loadedManager()
                    let samples = try await Self.collect(audio)
                    try Task.checkCancellation()

                    guard samples.count >= Self.minimumSamples else {
                        continuation.yield(TranscriptUpdate(text: "", isFinal: true))
                        continuation.finish()
                        return
                    }

                    var decoderState = TdtDecoderState.make()
                    let language = await self.languageHint
                    let result = try await manager.transcribe(samples, decoderState: &decoderState, language: language)
                    let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.logger.info(
                        "Parakeet: \(samples.count / 16_000, privacy: .public)s audio → \(text.count, privacy: .public) chars in \(result.processingTime, format: .fixed(precision: 2), privacy: .public)s"
                    )
                    continuation.yield(TranscriptUpdate(text: text, isFinal: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private var languageHint: Language? {
        locale.language.languageCode.flatMap { Language(rawValue: $0.identifier) }
    }

    private func loadedManager() async throws -> AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }

        let logger = self.logger
        let task = Task<AsrManager, any Error> {
            logger.info("Loading Parakeet v3 models (downloads on first use)")
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            logger.notice("Parakeet ready")
            return manager
        }
        loading = task
        defer { loading = nil }
        let manager = try await task.value
        self.manager = manager
        return manager
    }

    /// Drains the mic stream into 16 kHz mono Float32 samples.
    private static func collect(_ audio: AsyncStream<AudioChunk>) async throws -> [Float] {
        var samples: [Float] = []
        var converter: AVAudioConverter?
        for await chunk in audio {
            if Task.isCancelled { break }
            let converted = try AudioResampler.convert(chunk.buffer, to: AudioResampler.parakeetFormat, reusing: &converter)
            samples.append(contentsOf: AudioResampler.samples(of: converted))
        }
        return samples
    }
}
