import Cocoa
import Carbon

class HotkeyManager {
    var onDoubleTap: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastKeyPressTime: Date?
    private var isHolding: Bool = false
    private var triggerKeyObserver: NSObjectProtocol?

    private var doubleTapThreshold: TimeInterval {
        Settings.shared.doubleTapInterval
    }

    private var currentTriggerKey: TriggerKey {
        Settings.shared.triggerKey
    }

    func startMonitoring() {
        let trusted = AXIsProcessTrusted()
        print("[HotkeyManager] Accessibility trusted: \(trusted)")

        if !trusted {
            print("[HotkeyManager] WARNING: Accessibility permission NOT granted - hotkeys won't work!")
        }

        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        print("[HotkeyManager] Creating event tap for \(currentTriggerKey.displayName)...")

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
            return
        }

        print("[HotkeyManager] Event tap created successfully")

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("[HotkeyManager] Ready! Double-tap \(currentTriggerKey.displayName) to start recording")
        }

        triggerKeyObserver = NotificationCenter.default.addObserver(
            forName: .triggerKeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[HotkeyManager] Trigger key changed to \(self?.currentTriggerKey.displayName ?? "unknown")")
        }
    }

    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        if let observer = triggerKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        eventTap = nil
        runLoopSource = nil
        triggerKeyObserver = nil
        print("[HotkeyManager] Monitoring stopped")
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            let flags = event.flags
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isKeyPressed = isModifierKeyPressed(flags: flags, triggerKey: currentTriggerKey)

            if isKeyPressed && !isHolding {
                let now = Date()

                if let lastPress = lastKeyPressTime,
                   now.timeIntervalSince(lastPress) < doubleTapThreshold {
                    print("[HotkeyManager] DOUBLE-TAP DETECTED!")
                    isHolding = true
                    lastKeyPressTime = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.onDoubleTap?()
                    }
                } else {
                    lastKeyPressTime = now
                }
            } else if !isKeyPressed && isHolding {
                print("[HotkeyManager] Key released - stopping")
                isHolding = false
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func isModifierKeyPressed(flags: CGEventFlags, triggerKey: TriggerKey) -> Bool {
        switch triggerKey {
        case .option, .rightOption:
            return flags.contains(.maskAlternate)
        case .control:
            return flags.contains(.maskControl)
        case .fn:
            return flags.contains(.maskSecondaryFn)
        }
    }

    deinit {
        stopMonitoring()
    }
}
