import Cocoa
import Carbon

class TextInserter {
    private let pasteboard = NSPasteboard.general

    func insertText(_ text: String, clipboardOnly: Bool = false) {
        print("[TextInserter] Inserting text: \(text.prefix(50))... (clipboardOnly: \(clipboardOnly))")

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if clipboardOnly {
            print("[TextInserter] Clipboard only mode - done")
            return
        }

        // Check if we have accessibility permission
        guard AXIsProcessTrusted() else {
            print("[TextInserter] ERROR: No accessibility permission - cannot paste")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.simulatePaste()
        }
    }

    private func saveClipboard() -> [NSPasteboard.PasteboardType: Data] {
        var contents: [NSPasteboard.PasteboardType: Data] = [:]

        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) {
                contents[type] = data
            }
        }

        return contents
    }

    private func restoreClipboard(_ contents: [NSPasteboard.PasteboardType: Data]) {
        guard !contents.isEmpty else { return }

        pasteboard.clearContents()

        for (type, data) in contents {
            pasteboard.setData(data, forType: type)
        }
    }

    private func simulatePaste() {
        print("[TextInserter] Simulating Cmd+V paste...")

        let vKeyCode: CGKeyCode = 9

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("[TextInserter] ERROR: Failed to create event source")
            return
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("[TextInserter] ERROR: Failed to create key events")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        print("[TextInserter] Paste events posted")
    }
}
