import Foundation
import Observation
import os

/// Orchestrates one push-to-talk cycle:
/// key down → capture + stream to engine → key up → finalize → process → insert.
///
/// Overlapping presses are handled by a generation counter. A press that arrives while a previous
/// dictation is *finalizing* (transcribing/processing/inserting) does not cancel it — the old
/// pipeline still runs to completion and inserts its text — while the new recording starts
/// immediately and takes over the UI and microphone. Only the newest generation may mutate the
/// visible state or touch the audio engine.
@MainActor
@Observable
final class DictationSession {
    enum State: Equatable, Sendable {
        case idle
        case recording
        case transcribing
        case processing
        case inserting
        /// Brief confirmation shown after a successful insert.
        case done
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .idle, .failed, .done: false
            default: true
            }
        }
    }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    /// Microphone level 0...1 while recording.
    private(set) var level: Float = 0
    /// Loudest level seen during the current recording; used to tell "silence" from "no speech".
    private var peakLevel: Float = 0
    /// Most recent levels, oldest first, for the scrolling waveform. Fixed length.
    private(set) var levelHistory: [Float] = Array(repeating: 0, count: DictationSession.historyLength)
    static let historyLength = 24
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
    private var autoStopTask: Task<Void, Never>?
    private var recordingStartedAt: ContinuousClock.Instant?
    private var releasedAt: ContinuousClock.Instant?
    /// Incremented for each new recording; only the current generation owns the UI and mic.
    private var generation = 0
    private let logger = Logger(subsystem: "com.nicorossi.yapping", category: "session")

    /// Presses shorter than this are treated as accidental taps.
    static let minimumHold: Duration = .milliseconds(150)
    static let failureDisplayDuration: Duration = .seconds(2.5)
    static let doneDisplayDuration: Duration = .milliseconds(650)
    /// Peak level (0...1) below which a recording is considered dead silence.
    static let silenceThreshold: Float = 0.15  // ≈ -42 dBFS; real speech peaks 0.4+
    /// Safety backstop: auto-finalize a recording that somehow never receives a key release.
    static let maxRecordingDuration: Duration = .seconds(150)

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
            Task { @MainActor [weak self] in
                guard let self else { return }
                level = value
                peakLevel = max(peakLevel, value)
                levelHistory.removeFirst()
                levelHistory.append(value)
            }
        }
    }

    /// Pre-loads the engine and audio stack so the first press is snappy.
    /// - Returns: the error if the engine could not be prepared (e.g. model download failed).
    @discardableResult
    func warmUp() async -> (any Error)? {
        audio.warmUp()
        await processor.prepare()
        do {
            try await engine.prepare()
            return nil
        } catch {
            logger.error("Engine warm-up failed: \(error.localizedDescription, privacy: .public)")
            return error
        }
    }

    func beginRecording() {
        switch state {
        case .recording:
            // Still capturing (a missed release or double-down): it owns the mic, so discard it.
            logger.info("Press while still recording; discarding the previous capture")
            pipeline?.cancel()
            audio.stop()
        case .transcribing, .processing, .inserting:
            // Finalizing: leave it running so it still inserts. It no longer owns the mic.
            logger.info("Press during finalize; queuing new recording behind it")
        case .idle, .done, .failed:
            break
        }

        failureReset?.cancel()
        autoStopTask?.cancel()
        generation += 1
        let gen = generation

        partialTranscript = ""
        level = 0
        peakLevel = 0
        levelHistory = Array(repeating: 0, count: Self.historyLength)
        recordingStartedAt = .now

        let engine = self.engine
        pipeline = Task { [weak self] in
            guard let self else { return }
            do {
                let pressedAt = ContinuousClock.now
                // Mic first so the user's first word isn't lost; prepare() is a no-op once warmed.
                let stream = try audio.start()
                setState(.recording, gen: gen)
                scheduleAutoStop(gen: gen)
                let captureDelay = ContinuousClock.now - pressedAt
                try await engine.prepare()

                var finalText = ""
                for try await update in engine.transcribe(stream) {
                    if update.isFinal {
                        finalText = update.text
                    } else if gen == generation {
                        partialTranscript = update.text
                    }
                }
                try Task.checkCancellation()
                let finalAt = ContinuousClock.now
                let finalizeDelay = releasedAt.map { finalAt - $0 }

                let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    if peakLevel < Self.silenceThreshold, gen == generation {
                        logger.notice("Empty transcript and no mic signal (peak \(self.peakLevel, privacy: .public))")
                        fail(Copy.micMuted, gen: gen)
                    } else {
                        logger.notice("Empty transcript; nothing to insert")
                        finish(gen: gen)
                    }
                    return
                }

                setState(.processing, gen: gen)
                let processed = await runProcessor(on: text)
                try Task.checkCancellation()
                let processedAt = ContinuousClock.now

                setState(.inserting, gen: gen)
                try await inserter.insert(processed)
                let insertedAt = ContinuousClock.now
                lastInsertedText = processed
                logger.notice(
                    "Inserted \(processed.count, privacy: .public) chars · capture-start \(Self.ms(captureDelay), privacy: .public)ms · release→final \(Self.ms(finalizeDelay), privacy: .public)ms · cleanup \(Self.ms(processedAt - finalAt), privacy: .public)ms · insert \(Self.ms(insertedAt - processedAt), privacy: .public)ms · release→pasted \(Self.ms(self.releasedAt.map { insertedAt - $0 }), privacy: .public)ms"
                )
                celebrate(gen: gen)
            } catch is CancellationError {
                finish(gen: gen)
            } catch {
                fail(error.localizedDescription, gen: gen)
            }
        }
    }

    func endRecording() {
        guard let startedAt = recordingStartedAt else { return }
        recordingStartedAt = nil
        autoStopTask?.cancel()
        let held = ContinuousClock.now - startedAt
        if held < Self.minimumHold {
            logger.info("Hold too short (\(held, privacy: .public)); ignoring")
            cancel()
            return
        }
        guard state == .recording else { return }
        releasedAt = .now
        state = .transcribing
        audio.stop()  // ends the audio stream → engine finalizes
    }

    /// Cancels the current recording/pipeline and returns to idle. Detached older pipelines
    /// (queued behind this one) are left to finish inserting.
    func cancel() {
        pipeline?.cancel()
        pipeline = nil
        autoStopTask?.cancel()
        audio.stop()
        recordingStartedAt = nil
        level = 0
        partialTranscript = ""
        state = .idle
    }

    // MARK: - Private

    private static func ms(_ d: Duration?) -> Int {
        guard let d else { return -1 }
        return Int(d / .milliseconds(1))
    }

    /// Only the current generation may change the visible state.
    private func setState(_ newState: State, gen: Int) {
        guard gen == generation else { return }
        state = newState
    }

    private func scheduleAutoStop(gen: Int) {
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: Self.maxRecordingDuration)
            guard let self, !Task.isCancelled, gen == generation, state == .recording else { return }
            logger.notice("Auto-stopping recording at max duration")
            endRecording()
        }
    }

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

    private func finish(gen: Int) {
        guard gen == generation else { return }  // a detached older pipeline: leave UI/mic alone
        audio.stop()
        autoStopTask?.cancel()
        recordingStartedAt = nil
        level = 0
        partialTranscript = ""
        state = .idle
    }

    /// Flash `.done`, then return to idle unless a new press has started.
    private func celebrate(gen: Int) {
        guard gen == generation else { return }
        audio.stop()
        autoStopTask?.cancel()
        recordingStartedAt = nil
        level = 0
        partialTranscript = ""
        state = .done
        failureReset = Task { [weak self] in
            try? await Task.sleep(for: Self.doneDisplayDuration)
            guard !Task.isCancelled, self?.state == .done else { return }
            self?.state = .idle
        }
    }

    private func fail(_ message: String, gen: Int) {
        guard gen == generation else { return }
        audio.stop()
        autoStopTask?.cancel()
        recordingStartedAt = nil
        level = 0
        state = .failed(message)
        logger.error("Session failed: \(message, privacy: .public)")
        failureReset = Task { [weak self] in
            try? await Task.sleep(for: Self.failureDisplayDuration)
            guard !Task.isCancelled, self?.state == .failed(message) else { return }
            self?.partialTranscript = ""
            self?.state = .idle
        }
    }
}
