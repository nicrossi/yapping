import AppKit
import Testing
@testable import Yapping

@MainActor
struct PasteboardSnapshotTests {
    @Test func snapshotRestoresStringContents() {
        let pb = NSPasteboard(name: NSPasteboard.Name("yapping.test.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("before", forType: .string)

        let snapshot = PasteboardSnapshot(pb)
        pb.clearContents()
        pb.setString("during", forType: .string)
        #expect(pb.string(forType: .string) == "during")

        snapshot.restore(to: pb)
        #expect(pb.string(forType: .string) == "before")
    }

    @Test func emptySnapshotRestoresToEmpty() {
        let pb = NSPasteboard(name: NSPasteboard.Name("yapping.test.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()

        let snapshot = PasteboardSnapshot(pb)
        #expect(snapshot.isEmpty)
        pb.setString("during", forType: .string)
        snapshot.restore(to: pb)
        #expect(pb.string(forType: .string) == nil)
    }
}

struct PassthroughProcessorTests {
    @Test func returnsInputUnchanged() async throws {
        let out = try await PassthroughProcessor().process("  hi there ", context: ProcessingContext())
        #expect(out == "  hi there ")
    }
}
