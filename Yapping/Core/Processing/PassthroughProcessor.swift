import Foundation

struct PassthroughProcessor: TextProcessor {
    let id: ProcessorID = .passthrough
    func isAvailable() async -> Bool { true }
    func process(_ text: String, context: ProcessingContext) async throws -> String { text }
}
