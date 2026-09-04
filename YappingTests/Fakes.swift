import AVFoundation
import Foundation
@testable import Yapping

/// Engine that drains the audio stream and emits scripted updates, then a final.
final class FakeEngine: TranscriptionEngine, @unchecked Sendable {
    let id: EngineID = .speechAnalyzer
    var partials: [String]
    var finalText: String
    var prepareError: (any Error)?
    var transcribeError: (any Error)?
    private(set) var prepareCalls = 0

    init(partials: [String] = [], finalText: String = "", prepareError: (any Error)? = nil, transcribeError: (any Error)? = nil) {
        self.partials = partials
        self.finalText = finalText
        self.prepareError = prepareError
        self.transcribeError = transcribeError
    }

    func prepare() async throws {
        prepareCalls += 1
        if let prepareError { throw prepareError }
    }

    func transcribe(_ audio: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        let partials = partials, finalText = finalText, transcribeError = transcribeError
        return AsyncThrowingStream { continuation in
            let task = Task {
                for p in partials { continuation.yield(TranscriptUpdate(text: p, isFinal: false)) }
                for await _ in audio {}  // wait for key release
                if let transcribeError {
                    continuation.finish(throwing: transcribeError)
                    return
                }
                continuation.yield(TranscriptUpdate(text: finalText, isFinal: true))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

final class FakeProcessor: TextProcessor, @unchecked Sendable {
    let id: ProcessorID = .passthrough
    var available = true
    var transform: @Sendable (String) -> String = { $0.uppercased() }
    var error: (any Error)?
    private(set) var inputs: [String] = []

    func isAvailable() async -> Bool { available }
    func process(_ text: String, context: ProcessingContext) async throws -> String {
        inputs.append(text)
        if let error { throw error }
        return transform(text)
    }
}

final class FakeInserter: TextInserting, @unchecked Sendable {
    private(set) var inserted: [String] = []
    var error: (any Error)?
    func insert(_ text: String) async throws {
        if let error { throw error }
        inserted.append(text)
    }
}

struct TestError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}
