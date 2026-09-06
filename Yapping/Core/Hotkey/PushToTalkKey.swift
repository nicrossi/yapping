import CoreGraphics

/// A key the user can pick as an extra push-to-talk trigger, alongside the always-on Fn key.
/// Only keys that type no character and have a clean hold/release are offered.
enum PushToTalkKey: String, CaseIterable, Codable, Sendable, Identifiable {
    case rightControl, rightOption, rightCommand, rightShift
    case f13, f14, f15, f16, f17, f18, f19

    var id: String { rawValue }

    /// macOS virtual keycode for this key.
    var keyCode: Int64 {
        switch self {
        case .rightCommand: 54
        case .rightShift: 60
        case .rightOption: 61
        case .rightControl: 62
        case .f13: 105
        case .f14: 107
        case .f15: 113
        case .f16: 106
        case .f17: 64
        case .f18: 79
        case .f19: 80
        }
    }

    /// The modifier bit set while this key is held, or nil for the function keys.
    var modifierFlag: CGEventFlags? {
        switch self {
        case .rightControl: .maskControl
        case .rightOption: .maskAlternate
        case .rightCommand: .maskCommand
        case .rightShift: .maskShift
        case .f13, .f14, .f15, .f16, .f17, .f18, .f19: nil
        }
    }

    /// Modifier keys are seen via `flagsChanged`; function keys via `keyDown`/`keyUp`.
    var isModifier: Bool { modifierFlag != nil }

    var displayName: String {
        switch self {
        case .rightControl: "Right Control"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .rightShift: "Right Shift"
        case .f13: "F13"
        case .f14: "F14"
        case .f15: "F15"
        case .f16: "F16"
        case .f17: "F17"
        case .f18: "F18"
        case .f19: "F19"
        }
    }
}

/// Turns per-key down/up edges from any number of triggers into one press/release for the session.
/// Recording starts when the first trigger goes down and stops when the last comes up, so Fn and an
/// extra key can overlap without cutting each other off.
struct TriggerTracker {
    enum Edge: Equatable { case pressed, released }

    private(set) var down: Set<Int64> = []

    /// A trigger key went down. Returns `.pressed` only on the first key down.
    mutating func keyDown(_ keyCode: Int64) -> Edge? {
        let wasEmpty = down.isEmpty
        down.insert(keyCode)
        return wasEmpty && !down.isEmpty ? .pressed : nil
    }

    /// A trigger key came up. Returns `.released` only when the last key comes up.
    mutating func keyUp(_ keyCode: Int64) -> Edge? {
        guard down.contains(keyCode) else { return nil }
        down.remove(keyCode)
        return down.isEmpty ? .released : nil
    }

    /// Everything let go at once (e.g. the tap was disabled). Returns `.released` if anything was down.
    mutating func reset() -> Edge? {
        guard !down.isEmpty else { return nil }
        down.removeAll()
        return .released
    }
}
