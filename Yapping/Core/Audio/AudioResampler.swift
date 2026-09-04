@preconcurrency import AVFoundation

enum AudioResamplerError: LocalizedError {
    case converterUnavailable
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .converterUnavailable: "Could not create an audio converter."
        case .conversionFailed: "Audio conversion failed."
        }
    }
}

/// Converts PCM buffers between formats, reusing an `AVAudioConverter` across calls.
enum AudioResampler {
    static let parakeetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    static func convert(
        _ buffer: AVAudioPCMBuffer,
        to format: AVAudioFormat,
        reusing converter: inout AVAudioConverter?
    ) throws -> AVAudioPCMBuffer {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            guard let made = AVAudioConverter(from: buffer.format, to: format) else {
                throw AudioResamplerError.converterUnavailable
            }
            converter = made
        }
        guard let converter else { throw AudioResamplerError.converterUnavailable }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudioResamplerError.conversionFailed
        }

        // The input block is invoked synchronously inside `convert`, so this is not actually concurrent.
        nonisolated(unsafe) var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: out, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let conversionError { throw conversionError }
        if status == .error { throw AudioResamplerError.conversionFailed }
        return out
    }

    /// First-channel samples of a Float32 buffer.
    static func samples(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }
}
