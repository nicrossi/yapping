import Foundation
import Observation
import os

/// Orchestrates one push-to-talk cycle:
/// key down → capture + stream to engine → key up → finalize → process → insert.
@MainActor
@Observable
final class DictationSession {
    enum State: Equatable, Sendable {
        case idle
        case recording
        case transcribing
        case processing
        case inserting
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .idle, .failed: false
            default: true
            }
        }
    }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    /// Microphone level 0...1 while recording.
    private(set) var level: Float = 0
    /// Live transcript preview while recording/transcribing.
    private(set) var partialTranscript = ""
    private(set) var lastInsertedText = ""

    var onStateChange: ((State) -> Void)?

    var engine: any TranscriptionEngine
    var processor: any TextProcessor
    var inserter: any TextInserting

    private let audio: AudioCapture
    private var pipeline: Task<Void, Never>?
    private var failureReset: Task<Void, Never>?
    private var recordingStartedAt: ContinuousClock.Instant?
    private let logger = Logger(subsystem: "com.nicorossi.yapping", category: "session")

    /// Presses shorter than this are treated as accidental taps.
    static let minimumHold: Duration = .milliseconds(150)
    static let failureDisplayDuration: Duration = .seconds(2.5)

    init(
        audio: AudioCapture,
        engine: any TranscriptionEngine,
        processor: any TextProcessor,
        inserter: any TextInserting
    ) {
        self.audio = audio
        self.engine = engine
        self.processor = processor
        self.inserter = inserter
        audio.onLevel = { [weak self] value in
            Task { @MainActor [weak self] in self?.level = value }
        }
    }

    /// Pre-loads the engine and audio stack so the first press is snappy.
    /// - Returns: the error if the engine could not be prepared (e.g. model download failed).
    @discardableResult
    func warmUp() async -> (any Error)? {
        audio.warmUp()
        do {
            try await engine.prepare()
            return nil
        } catch {
            logger.error("Engine warm-up failed: \(error.localizedDescription, privacy: .public)")
            return error
        }
    }

    func beginRecording() {
        if state.isBusy {
            logger.info("Press while busy (\(String(describing: self.state), privacy: .public)); cancelling in-flight work")
            cancel()
        }
        failureReset?.cancel()
        partialTranscript = ""
        level = 0
        recordingStartedAt = .now

        let engine = self.engine
        pipeline = Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.prepare()
                let stream = try audio.start()
                state = .recording

                var finalText = ""
                for try await update in engine.transcribe(stream) {
                    if update.isFinal {
                        finalText = update.text
                    } else {
                        partialTranscript = update.text
                    }
                }
                try Task.checkCancellation()

                let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    logger.notice("Empty transcript; nothing to insert")
                    finish()
                    return
                }

                state = .processing
                let processed = await runProcessor(on: text)
                try Task.checkCancellation()

                state = .inserting
                try await inserter.insert(processed)
                lastInsertedText = processed
                logger.notice("Inserted \(processed.count, privacy: .public) chars")
                finish()
            } catch is CancellationError {
                finish()
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    func endRecording() {
        guard let startedAt = recordingStartedAt else { return }
        recordingStartedAt = nil
        let held = ContinuousClock.now - startedAt
        if held < Self.minimumHold {
            logger.info("Hold too short (\(held, privacy: .public)); ignoring")
            cancel()
            return
        }
        guard state == .recording else { return }
        state = .transcribing
        audio.stop()  // ends the audio stream → engine finalizes
    }

    func cancel() {
        pipeline?.cancel()
        pipeline = nil
        audio.stop()
        finish()
    }

    // MARK: - Private

    private func runProcessor(on text: String) async -> String {
        guard await processor.isAvailable() else { return text }
        let front = FrontmostApp.current()
        let context = ProcessingContext(appName: front.name, bundleID: front.bundleID)
        do {
            return try await processor.process(text, context: context)
        } catch {
            logger.error("Processor failed, falling back to raw text: \(error.localizedDescription, privacy: .public)")
            return text
        }
    }

    private func finish() {
        audio.stop()
        recordingStartedAt = nil
        level = 0
        partialTranscript = ""
        state = .idle
    }

    private func fail(_ message: String) {
        audio.stop()
        recordingStartedAt = nil
        level = 0
        state = .failed(message)
        logger.error("Session failed: \(message, privacy: .public)")
        failureReset = Task { [weak self] in
            try? await Task.sleep(for: Self.failureDisplayDuration)
            guard !Task.isCancelled else { return }
            self?.partialTranscript = ""
            self?.state = .idle
        }
    }
}
