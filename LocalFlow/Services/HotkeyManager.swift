import Cocoa
import Carbon

class HotkeyManager {
    var onDoubleTap: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastOptionPressTime: Date?
    private var isHolding: Bool = false

    private let doubleTapThreshold: TimeInterval = 0.3
    private let optionKeyCode: CGKeyCode = 58 // Right Option key

    func startMonitoring() {
        // Request accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !trusted {
            print("Accessibility permission required")
            return
        }

        // Create event tap for key events
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Handle flagsChanged for modifier keys like Option
        if type == .flagsChanged {
            let flags = event.flags
            let optionPressed = flags.contains(.maskAlternate)

            if optionPressed && !isHolding {
                // Option key pressed
                let now = Date()

                if let lastPress = lastOptionPressTime,
                   now.timeIntervalSince(lastPress) < doubleTapThreshold {
                    // Double tap detected - start recording
                    isHolding = true
                    lastOptionPressTime = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.onDoubleTap?()
                    }
                } else {
                    // First tap
                    lastOptionPressTime = now
                }
            } else if !optionPressed && isHolding {
                // Option key released while holding - stop recording
                isHolding = false
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    deinit {
        stopMonitoring()
    }
}
