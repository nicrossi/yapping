import AppKit
import CoreGraphics
import os

/// Watches the Fn key globally via a CGEventTap and reports press/release.
/// Requires Accessibility trust. Events pass through unmodified.
@MainActor
final class HotkeyMonitor {
    enum Event: Sendable { case pressed, released }

    var onEvent: ((Event) -> Void)?
    private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsDown = false
    private let logger = Logger(subsystem: "com.nicorossi.yapping", category: "hotkey")

    private static let fnKeyCode: Int64 = 63

    /// - Returns: `false` when the tap could not be created (almost always: Accessibility not granted).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: userInfo
        ) else {
            logger.error("CGEventTap creation failed (Accessibility not granted?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        isRunning = true
        logger.notice("Fn hotkey tap started")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        isRunning = false
        fnIsDown = false
    }

    fileprivate func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            logger.warning("Event tap disabled by system; re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            guard keyCode == Self.fnKeyCode else { return }
            let down = flags.contains(.maskSecondaryFn)
            guard down != fnIsDown else { return }
            fnIsDown = down
            onEvent?(down ? .pressed : .released)
        default:
            break
        }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        // Pull Sendable scalars out of the (non-Sendable) CGEvent before crossing into the actor.
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        // The tap's run loop source lives on the main run loop, so this runs on the main thread.
        MainActor.assumeIsolated { monitor.handle(type: type, keyCode: keyCode, flags: flags) }
    }
    return Unmanaged.passUnretained(event)
}
