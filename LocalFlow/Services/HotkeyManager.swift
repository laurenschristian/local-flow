import Cocoa
import Carbon

class HotkeyManager {
    var onDoubleTap: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onTripleTap: (() -> Void)?  // Quick re-paste

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapTimes: [Date] = []
    private var isHolding: Bool = false
    private var holdStartTime: Date?
    private var triggerKeyObserver: NSObjectProtocol?
    private var tripleTapPending: Bool = false
    private var healthCheckTimer: Timer?
    private let maxHoldDuration: TimeInterval = 300 // 5 minutes max recording

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

        // Health check timer - re-enables tap if macOS disabled it
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.ensureTapEnabled()
        }
    }

    private func ensureTapEnabled() {
        guard let tap = eventTap else { return }

        // Check for stuck holding state (exceeded max duration)
        if isHolding, let startTime = holdStartTime {
            if Date().timeIntervalSince(startTime) > maxHoldDuration {
                print("[HotkeyManager] Hold exceeded max duration - forcing release")
                isHolding = false
                holdStartTime = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
        }

        if !CGEvent.tapIsEnabled(tap: tap) {
            print("[HotkeyManager] Event tap was disabled - re-enabling...")
            CGEvent.tapEnable(tap: tap, enable: true)
            // Reset state since we may have missed key release events
            if isHolding {
                print("[HotkeyManager] Resetting stuck isHolding state")
                isHolding = false
                holdStartTime = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
            tapTimes.removeAll()
        }
    }

    func stopMonitoring() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil

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
        isHolding = false
        holdStartTime = nil
        tapTimes.removeAll()
        print("[HotkeyManager] Monitoring stopped")
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("[HotkeyManager] Event tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input") - re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            // Reset state since we may have missed events
            let wasHolding = isHolding
            isHolding = false
            holdStartTime = nil
            tapTimes.removeAll()
            if wasHolding {
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            let flags = event.flags
            let isKeyPressed = isModifierKeyPressed(flags: flags, triggerKey: currentTriggerKey)

            if isKeyPressed && !isHolding {
                let now = Date()

                // Clean up old taps outside the threshold window
                tapTimes = tapTimes.filter { now.timeIntervalSince($0) < doubleTapThreshold * 2 }
                tapTimes.append(now)

                // Count recent taps within threshold
                let recentTaps = tapTimes.filter { now.timeIntervalSince($0) < doubleTapThreshold }

                if recentTaps.count >= 3 {
                    // Triple-tap: quick re-paste (no hold needed)
                    print("[HotkeyManager] TRIPLE-TAP DETECTED!")
                    tapTimes.removeAll()
                    DispatchQueue.main.async { [weak self] in
                        self?.onTripleTap?()
                    }
                } else if recentTaps.count == 2 {
                    // Double-tap: start recording (hold to continue)
                    print("[HotkeyManager] DOUBLE-TAP DETECTED!")
                    isHolding = true
                    holdStartTime = Date()
                    tapTimes.removeAll()
                    DispatchQueue.main.async { [weak self] in
                        self?.onDoubleTap?()
                    }
                }
            } else if !isKeyPressed && isHolding {
                print("[HotkeyManager] Key released - stopping")
                isHolding = false
                holdStartTime = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func isModifierKeyPressed(flags: CGEventFlags, triggerKey: TriggerKey) -> Bool {
        // Check that ONLY the trigger modifier is pressed (not part of a combo like Cmd+Opt+F)
        let hasCommand = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        let hasControl = flags.contains(.maskControl)
        let hasOption = flags.contains(.maskAlternate)

        switch triggerKey {
        case .option, .rightOption:
            // Option must be pressed, but Command/Shift/Control must NOT be pressed
            return hasOption && !hasCommand && !hasShift && !hasControl
        case .control:
            // Control must be pressed, but Command/Shift/Option must NOT be pressed
            return hasControl && !hasCommand && !hasShift && !hasOption
        case .fn:
            // Fn must be pressed alone
            return flags.contains(.maskSecondaryFn) && !hasCommand && !hasShift && !hasControl && !hasOption
        }
    }

    deinit {
        stopMonitoring()
    }
}
