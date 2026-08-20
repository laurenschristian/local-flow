import Cocoa
import Carbon

class TextInserter {
    private let pasteboard = NSPasteboard.general

    func insertText(_ text: String, clipboardOnly: Bool = false) {
        print("[TextInserter] Inserting text: \(text.prefix(50))... (clipboardOnly: \(clipboardOnly))")

        if clipboardOnly {
            // User explicitly opted into clipboard mode: replace and stop.
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            print("[TextInserter] Clipboard only mode - done")
            return
        }

        guard AXIsProcessTrusted() else {
            print("[TextInserter] ERROR: No accessibility permission - cannot paste")
            // Best effort: leave the text on the clipboard so the user can still paste manually.
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return
        }

        // Save → set transcription → paste → restore. Without this the user's
        // previously copied content gets clobbered every time they dictate.
        let savedClipboard = saveClipboard()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.simulatePaste()
            // Slow targets (Electron, remote desktops) read the pasteboard late,
            // so hold the text long enough that they never paste the old value.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.pasteboard.changeCount == ourChangeCount else { return }
                self.restoreClipboard(savedClipboard)
            }
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
