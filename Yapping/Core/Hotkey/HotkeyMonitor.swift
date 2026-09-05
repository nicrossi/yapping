import AppKit
import ApplicationServices
import CoreGraphics
import os

/// Watches the Fn key globally and reports press/release.
///
/// The CGEventTap runs on a dedicated high-priority thread with its own run loop, never the
/// main run loop. This is deliberate: a listen-only tap on the main run loop gets starved
/// whenever the main thread is busy (SwiftUI layout, audio engine start/stop, model work),
/// and macOS then disables it by timeout — dropping the Fn-release that fires during the stall
/// and leaving a recording running forever. A dedicated thread keeps event delivery immune to
/// UI work. Requires Accessibility trust.
@MainActor
final class HotkeyMonitor {
    enum Event: Sendable { case pressed, released }

    var onEvent: ((Event) -> Void)?
    private(set) var isRunning = false

    private var tapThread: HotkeyTapThread?
    private let logger = Logger(subsystem: "com.nicorossi.yapping", category: "hotkey")

    /// - Returns: `false` when the tap could not be created (almost always: Accessibility not granted).
    @discardableResult
    func start() -> Bool {
        guard tapThread == nil else { return true }
        guard AXIsProcessTrusted() else {
            logger.info("Accessibility not granted; not starting tap")
            return false
        }
        let handler: @Sendable (Event) -> Void = { [weak self] event in
            // Deliver on the main queue, preserving order (single serial source → FIFO).
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onEvent?(event) }
            }
        }
        let thread = HotkeyTapThread(handler: handler)
        guard thread.startAndWaitUntilReady() else {
            logger.error("CGEventTap creation failed (Accessibility revoked?)")
            return false
        }
        tapThread = thread
        isRunning = true
        logger.notice("Fn hotkey tap started")
        return true
    }

    func stop() {
        tapThread?.stop()
        tapThread = nil
        isRunning = false
    }
}

/// Owns the CGEventTap and its run loop on a private thread. Not main-actor isolated:
/// `fnIsDown` is touched only from the tap callback (its own thread), and `handler` hops to main.
private final class HotkeyTapThread: @unchecked Sendable {
    private let handler: @Sendable (HotkeyMonitor.Event) -> Void
    private var thread: Thread?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var fnIsDown = false
    private var didCreateTap = false
    private let ready = DispatchSemaphore(value: 0)

    private static let fnKeyCode: Int64 = 63

    init(handler: @escaping @Sendable (HotkeyMonitor.Event) -> Void) {
        self.handler = handler
    }

    /// Spins up the thread and blocks until the tap is created (or failed). Returns success.
    func startAndWaitUntilReady() -> Bool {
        let thread = Thread { [weak self] in self?.threadMain() }
        thread.name = "com.nicorossi.yapping.hotkey"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        ready.wait()
        return didCreateTap
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    private func threadMain() {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,   // we never modify Fn; listen-only can't add input latency
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: userInfo
        ) else {
            ready.signal()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let rl = CFRunLoopGetCurrent()
        CFRunLoopAddSource(rl, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
        self.runLoop = rl
        didCreateTap = true
        ready.signal()

        CFRunLoopRun()

        // Reached only after stop() calls CFRunLoopStop.
        if let source = self.source { CFRunLoopRemoveSource(rl, source, .commonModes) }
        if let tap = self.tap { CFMachPortInvalidate(tap) }
        self.tap = nil
        self.source = nil
        self.runLoop = nil
    }

    /// Runs on the tap thread.
    fileprivate func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // A disable while the key is held almost certainly means we lost the release.
            // End the gesture rather than let a recording run forever.
            if fnIsDown {
                fnIsDown = false
                handler(.released)
            }
        case .flagsChanged:
            guard keyCode == Self.fnKeyCode else { return }
            let down = flags.contains(.maskSecondaryFn)
            guard down != fnIsDown else { return }
            fnIsDown = down
            handler(down ? .pressed : .released)
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
        let thread = Unmanaged<HotkeyTapThread>.fromOpaque(userInfo).takeUnretainedValue()
        // Pull Sendable scalars out of the (non-Sendable) CGEvent before handing off.
        thread.handle(type: type, keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags)
    }
    return Unmanaged.passUnretained(event)  // ignored for listen-only taps
}
