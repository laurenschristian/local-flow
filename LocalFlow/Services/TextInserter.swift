import Cocoa
import Carbon

class TextInserter {
    private let pasteboard = NSPasteboard.general

    func insertText(_ text: String) {
        // Save current clipboard contents
        let savedContents = saveClipboard()

        // Copy transcription to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            // Simulate Cmd+V
            self?.simulatePaste()

            // Restore original clipboard after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.restoreClipboard(savedContents)
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
        // Create key down event for 'V' with Command modifier
        let vKeyCode: CGKeyCode = 9 // 'V' key

        guard let keyDownEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: vKeyCode,
            keyDown: true
        ) else { return }

        keyDownEvent.flags = .maskCommand
        keyDownEvent.post(tap: .cghidEventTap)

        // Create key up event
        guard let keyUpEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: vKeyCode,
            keyDown: false
        ) else { return }

        keyUpEvent.flags = .maskCommand
        keyUpEvent.post(tap: .cghidEventTap)
    }
}
