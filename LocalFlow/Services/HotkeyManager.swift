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
    private var doubleTapAt: Date?
    private var pendingStopWork: DispatchWorkItem?
    private var triggerKeyObserver: NSObjectProtocol?
    private var tripleTapPending: Bool = false
    private var healthCheckTimer: Timer?

    // Toggle mode is meant for long dictation, so its watchdog is generous.
    private var maxHoldDuration: TimeInterval {
        recordingMode == .toggle ? 900 : 300
    }

    private var recordingMode: RecordingMode {
        Settings.shared.recordingMode
    }

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
                resetHoldState()
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
        }

        if !CGEvent.tapIsEnabled(tap: tap) {
            print("[HotkeyManager] Event tap was disabled - re-enabling...")
            CGEvent.tapEnable(tap: tap, enable: true)
            // Reset state since we may have missed key release events
            let wasHolding = isHolding
            resetHoldState()
            if wasHolding {
                print("[HotkeyManager] Resetting stuck isHolding state")
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
            }
        }
    }

    /// Drops all tap/hold tracking. Called whenever the app refuses or aborts a
    /// recording so the manager never believes a recording is running that isn't.
    func resetHoldState() {
        isHolding = false
        holdStartTime = nil
        doubleTapAt = nil
        pendingStopWork?.cancel()
        pendingStopWork = nil
        tapTimes.removeAll()
    }

    func stopMonitoring() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        pendingStopWork?.cancel()
        pendingStopWork = nil
        doubleTapAt = nil

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
            resetHoldState()
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
                    // Third quick tap upgrades the double-tap to a triple-tap:
                    // drop the pending stop from the quick release and re-paste.
                    print("[HotkeyManager] TRIPLE-TAP DETECTED!")
                    pendingStopWork?.cancel()
                    pendingStopWork = nil
                    tapTimes.removeAll()
                    doubleTapAt = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.onTripleTap?()
                    }
                } else if recentTaps.count == 2 {
                    // Double-tap: start recording (hold to continue).
                    // Keep tapTimes so a third tap can still become a triple-tap.
                    // A deferred stop from a previous quick release must die here,
                    // or it would stop this new recording milliseconds after start.
                    pendingStopWork?.cancel()
                    pendingStopWork = nil
                    print("[HotkeyManager] DOUBLE-TAP DETECTED!")
                    isHolding = true
                    holdStartTime = Date()
                    doubleTapAt = now
                    DispatchQueue.main.async { [weak self] in
                        self?.onDoubleTap?()
                    }
                }
            } else if isKeyPressed && isHolding && recordingMode == .toggle {
                // Toggle mode: recording is active and the key was pressed again.
                let sinceDouble = doubleTapAt.map { Date().timeIntervalSince($0) } ?? .infinity
                isHolding = false
                holdStartTime = nil
                doubleTapAt = nil
                tapTimes.removeAll()
                if sinceDouble < doubleTapThreshold {
                    // Third quick tap right after the double-tap: triple-tap re-paste
                    print("[HotkeyManager] TRIPLE-TAP DETECTED (toggle)!")
                    DispatchQueue.main.async { [weak self] in
                        self?.onTripleTap?()
                    }
                } else {
                    print("[HotkeyManager] Toggle stop")
                    DispatchQueue.main.async { [weak self] in
                        self?.onKeyUp?()
                    }
                }
            } else if !isKeyPressed && isHolding {
                // Toggle mode ignores releases; only the next press stops.
                guard recordingMode == .hold else {
                    return Unmanaged.passUnretained(event)
                }
                isHolding = false
                holdStartTime = nil
                let sinceDouble = doubleTapAt.map { Date().timeIntervalSince($0) } ?? .infinity
                if sinceDouble < doubleTapThreshold {
                    // Released almost instantly: wait one threshold for a possible
                    // third tap before finalizing, so triple-tap stays reachable.
                    print("[HotkeyManager] Quick release - deferring stop briefly")
                    let work = DispatchWorkItem { [weak self] in
                        self?.pendingStopWork = nil
                        self?.doubleTapAt = nil
                        self?.onKeyUp?()
                    }
                    pendingStopWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapThreshold, execute: work)
                } else {
                    print("[HotkeyManager] Key released - stopping")
                    doubleTapAt = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.onKeyUp?()
                    }
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
