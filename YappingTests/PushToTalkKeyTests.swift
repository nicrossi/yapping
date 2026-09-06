import CoreGraphics
import Testing
@testable import Yapping

struct PushToTalkKeyTests {
    @Test func modifierKeysCarryAFlag() {
        #expect(PushToTalkKey.rightControl.modifierFlag == .maskControl)
        #expect(PushToTalkKey.rightOption.modifierFlag == .maskAlternate)
        #expect(PushToTalkKey.rightCommand.modifierFlag == .maskCommand)
        #expect(PushToTalkKey.rightShift.modifierFlag == .maskShift)
        #expect(PushToTalkKey.rightControl.isModifier)
    }

    @Test func functionKeysHaveNoFlag() {
        for key in [PushToTalkKey.f13, .f14, .f15, .f16, .f17, .f18, .f19] {
            #expect(key.modifierFlag == nil)
            #expect(!key.isModifier)
        }
    }

    @Test func keycodesAreDistinctAndNotFn() {
        let codes = PushToTalkKey.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count)       // no duplicates
        #expect(!codes.contains(63))                   // never collides with Fn
    }

    @Test func roundTripsThroughRawValue() {
        for key in PushToTalkKey.allCases {
            #expect(PushToTalkKey(rawValue: key.rawValue) == key)
        }
    }
}

struct TriggerTrackerTests {
    @Test func firstDownPressesLastUpReleases() {
        var t = TriggerTracker()
        #expect(t.keyDown(63) == .pressed)
        #expect(t.keyUp(63) == .released)
    }

    @Test func overlappingTriggersStayPressedUntilLastRelease() {
        var t = TriggerTracker()
        #expect(t.keyDown(63) == .pressed)   // Fn down
        #expect(t.keyDown(105) == nil)       // F13 down while Fn held: no new press
        #expect(t.keyUp(63) == nil)          // Fn up but F13 still held: no release
        #expect(t.keyUp(105) == .released)   // last key up
    }

    @Test func autorepeatDownIsAbsorbed() {
        var t = TriggerTracker()
        #expect(t.keyDown(105) == .pressed)
        #expect(t.keyDown(105) == nil)       // repeat
        #expect(t.keyUp(105) == .released)
    }

    @Test func unknownKeyUpIsIgnored() {
        var t = TriggerTracker()
        #expect(t.keyUp(999) == nil)
    }

    @Test func resetReleasesOnlyWhenSomethingWasDown() {
        var t = TriggerTracker()
        #expect(t.reset() == nil)
        _ = t.keyDown(63)
        #expect(t.reset() == .released)
        #expect(t.reset() == nil)
    }
}
