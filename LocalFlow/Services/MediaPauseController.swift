import AppKit
import CoreAudio

/// Pauses whatever is playing while recording and resumes only what it paused.
/// Spotify and Music are scripted directly; everything else (browsers, SoundCloud,
/// video apps) answers the system play/pause key.
final class MediaPauseController {
    static let shared = MediaPauseController()

    private struct Player {
        let bundleId: String
        let appName: String
    }

    private static let players = [
        Player(bundleId: "com.spotify.client", appName: "Spotify"),
        Player(bundleId: "com.apple.Music", appName: "Music"),
    ]

    private let queue = DispatchQueue(label: "com.localflow.media-pause", qos: .userInitiated)
    private var pausedPlayers: [Player] = []
    private var pausedViaMediaKey = false

    private init() {}

    func pauseForRecording() {
        // Sample before our own start sound reaches the output device.
        let playingPIDs = Self.audioProducingPIDs()
        queue.async {
            var paused: [Player] = []
            for player in Self.players where self.isRunning(player.bundleId) {
                if self.runScript("tell application \"\(player.appName)\" to player state as string") == "playing" {
                    _ = self.runScript("tell application \"\(player.appName)\" to pause")
                    paused.append(player)
                }
            }
            self.pausedPlayers = paused
            self.pausedViaMediaKey = false

            guard paused.isEmpty, !playingPIDs.isEmpty else { return }
            Self.sendPlayPauseKey()
            guard Self.canAuditProcessAudio else {
                self.pausedViaMediaKey = true
                return
            }
            Thread.sleep(forTimeInterval: 0.4)
            let now = Self.audioProducingPIDs()
            // Keep the toggle only if it silenced something and started nothing;
            // otherwise the key hit an unrelated app, so press it back.
            if playingPIDs.subtracting(now).isEmpty || !now.subtracting(playingPIDs).isEmpty {
                Self.sendPlayPauseKey()
            } else {
                self.pausedViaMediaKey = true
            }
        }
    }

    func resumeAfterRecording() {
        queue.async {
            for player in self.pausedPlayers where self.isRunning(player.bundleId) {
                _ = self.runScript("tell application \"\(player.appName)\" to play")
            }
            self.pausedPlayers = []
            if self.pausedViaMediaKey {
                Self.sendPlayPauseKey()
                self.pausedViaMediaKey = false
            }
        }
    }

    private func isRunning(_ bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    private func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            print("[LocalFlow] Media pause script error: \(error)")
            return nil
        }
        return result?.stringValue
    }

    // MARK: - System play/pause key

    private static func sendPlayPauseKey() {
        for isDown in [true, false] {
            let state = isDown ? 0x0A00 : 0x0B00
            let data1 = (16 << 16) | state  // 16 = NX_KEYTYPE_PLAY
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Which processes are making sound

    private static var canAuditProcessAudio: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    /// PIDs of other apps currently playing audio. Falls back to a yes/no answer
    /// (an opaque PID) on macOS versions without the per-process audio API.
    private static func audioProducingPIDs() -> Set<pid_t> {
        guard #available(macOS 14.4, *) else {
            return isOutputDeviceRunning() ? [-1] : []
        }
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return [] }

        var objects = [AudioObjectID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &dataSize, &objects
        ) == noErr else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: Set<pid_t> = []
        for object in objects where processProperty(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1 {
            if let pid = processProperty(object, kAudioProcessPropertyPID, as: pid_t.self), pid != ownPID {
                result.insert(pid)
            }
        }
        return result
    }

    @available(macOS 14.4, *)
    private static func processProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        var value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }

    private static func isOutputDeviceRunning() -> Bool {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &size, &device
        ) == noErr, device != kAudioObjectUnknown else { return false }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}
