import Cocoa
import Carbon

class HotkeyManager {
    var onDoubleTap: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastOptionPressTime: Date?
    private var isHolding: Bool = false

    private let doubleTapThreshold: TimeInterval = 0.4 // Increased for easier detection

    func startMonitoring() {
        // Check accessibility permissions silently - NO prompt
        let trusted = AXIsProcessTrusted()

        print("[HotkeyManager] Accessibility trusted: \(trusted)")

        if !trusted {
            print("[HotkeyManager] WARNING: Accessibility permission NOT granted - hotkeys won't work!")
            // Don't return - still try to create event tap, it just won't work
        }

        // Create event tap for modifier key changes
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        print("[HotkeyManager] Creating event tap...")

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HotkeyManager] ERROR: Failed to create event tap!")
            print("[HotkeyManager] This usually means accessibility permission is not properly granted.")
            return
        }

        print("[HotkeyManager] Event tap created successfully")

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("[HotkeyManager] Event tap enabled and added to run loop")
            print("[HotkeyManager] Ready! Double-tap Option key to start recording")
        }
    }

    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        print("[HotkeyManager] Monitoring stopped")
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it was disabled (can happen under heavy load)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                print("[HotkeyManager] Re-enabled event tap")
            }
            return Unmanaged.passUnretained(event)
        }

        // Handle flagsChanged for modifier keys like Option
        if type == .flagsChanged {
            let flags = event.flags
            let optionPressed = flags.contains(.maskAlternate)

            if optionPressed && !isHolding {
                // Option key pressed
                let now = Date()
                print("[HotkeyManager] Option key pressed")

                if let lastPress = lastOptionPressTime,
                   now.timeIntervalSince(lastPress) < doubleTapThreshold {
                    // Double tap detected - start recording
                    print("[HotkeyManager] DOUBLE-TAP DETECTED!")
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
                print("[HotkeyManager] Option key released - stopping")
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
