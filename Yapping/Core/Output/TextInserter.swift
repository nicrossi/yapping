import AppKit
import CoreGraphics
import os

protocol TextInserting: Sendable {
    @MainActor func insert(_ text: String) async throws
}

/// Inserts text into the focused app by temporarily placing it on the pasteboard,
/// synthesizing ⌘V, then restoring whatever was there before.
struct PasteboardTextInserter: TextInserting {
    var restoreDelay: Duration = .milliseconds(250)

    @MainActor
    func insert(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        Self.postCommandV()

        try await Task.sleep(for: restoreDelay)
        // Only restore if nobody else touched the pasteboard in the meantime.
        if pasteboard.changeCount == ourChangeCount {
            snapshot.restore(to: pasteboard)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

/// Deep copy of the pasteboard contents so they can be put back after we paste.
@MainActor
struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    var isEmpty: Bool { items.isEmpty }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
