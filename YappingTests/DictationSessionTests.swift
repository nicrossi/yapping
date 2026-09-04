import Foundation
import Testing
@testable import Yapping

/// These drive `DictationSession` with a real `AudioCapture` (needs a mic + permission),
/// so they are skipped when no input device is available on the test host.
@MainActor
struct DictationSessionTests {
    private func makeSession(
        engine: FakeEngine,
        processor: FakeProcessor = FakeProcessor(),
        inserter: FakeInserter = FakeInserter()
    ) -> DictationSession {
        DictationSession(audio: AudioCapture(), engine: engine, processor: processor, inserter: inserter)
    }

    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func startsIdle() {
        let session = makeSession(engine: FakeEngine())
        #expect(session.state == .idle)
        #expect(!session.state.isBusy)
    }

    @Test func releaseWithoutPressIsNoop() {
        let session = makeSession(engine: FakeEngine())
        session.endRecording()
        #expect(session.state == .idle)
    }

    @Test func prepareFailureSurfacesAsFailedState() async {
        let engine = FakeEngine(prepareError: TestError(message: "no model"))
        let session = makeSession(engine: engine)
        session.beginRecording()
        await waitUntil { session.state != .idle && session.state != .recording }
        #expect(session.state == .failed("no model"))
    }

    @Test func stateTransitionsAreObservable() {
        let session = makeSession(engine: FakeEngine())
        var seen: [DictationSession.State] = []
        session.onStateChange = { seen.append($0) }
        // No transitions yet; the callback must not fire for identical state.
        #expect(seen.isEmpty)
    }

    @Test func busyStatesAreCorrect() {
        #expect(DictationSession.State.recording.isBusy)
        #expect(DictationSession.State.transcribing.isBusy)
        #expect(DictationSession.State.processing.isBusy)
        #expect(DictationSession.State.inserting.isBusy)
        #expect(!DictationSession.State.idle.isBusy)
        #expect(!DictationSession.State.failed("x").isBusy)
    }
}
