import AVFoundation
import os

/// A copied PCM buffer handed off the realtime audio thread. Never mutated after creation.
struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

enum AudioCaptureError: LocalizedError {
    case noInputDevice
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "No microphone available."
        case .alreadyRunning: "Audio capture already running."
        }
    }
}

/// Captures microphone audio into an `AsyncStream<AudioChunk>` and reports input level.
@MainActor
final class AudioCapture {
    /// Called on the audio thread with a 0...1 level, ~10–20 times per second.
    var onLevel: (@Sendable (Float) -> Void)?

    private(set) var isRunning = false
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private let logger = Logger(subsystem: "com.nicorossi.yapping", category: "audio")

    /// Pre-allocates engine resources so the first `start()` is fast.
    func warmUp() {
        _ = engine.inputNode
        engine.prepare()
    }

    func start() throws -> AsyncStream<AudioChunk> {
        guard !isRunning else { throw AudioCaptureError.alreadyRunning }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioCaptureError.noInputDevice }

        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .bufferingNewest(256))
        let onLevel = self.onLevel
        // `@Sendable` keeps the closure nonisolated: it runs on the realtime audio thread, and a
        // MainActor-inherited closure would trap on the runtime isolation check (SIGTRAP).
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
            if let copy = buffer.deepCopy() {
                continuation.yield(AudioChunk(buffer: copy))
            }
            if let onLevel { onLevel(buffer.normalizedLevel()) }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            continuation.finish()
            throw error
        }
        self.continuation = continuation
        isRunning = true
        logger.notice("Capture started: \(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch")
        return stream
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        isRunning = false
        logger.notice("Capture stopped")
    }
}

extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        copy.frameLength = frameLength
        let src = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (s, d) in zip(src, dst) {
            guard let sData = s.mData, let dData = d.mData else { continue }
            memcpy(dData, sData, Int(min(s.mDataByteSize, d.mDataByteSize)))
        }
        return copy
    }

    /// RMS of the first channel mapped from roughly -50 dBFS...0 dBFS onto 0...1.
    func normalizedLevel() -> Float {
        guard let data = floatChannelData, frameLength > 0 else { return 0 }
        let samples = UnsafeBufferPointer(start: data[0], count: Int(frameLength))
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(frameLength)).squareRoot()
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db + 50) / 50))
    }
}
