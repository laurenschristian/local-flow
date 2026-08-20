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
        queue.async { self.resume() }
    }

    /// Blocking variant for app termination, where a queued resume would never
    /// run and would leave the user's music paused for good.
    func resumeAfterRecordingNow() {
        queue.sync { self.resume() }
    }

    private func resume() {
        for player in pausedPlayers where isRunning(player.bundleId) {
            _ = runScript("tell application \"\(player.appName)\" to play")
        }
        pausedPlayers = []
        if pausedViaMediaKey {
            Self.sendPlayPauseKey()
            pausedViaMediaKey = false
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
        let processes: [AudioObjectID] = AudioDeviceManager.propertyList(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: Set<pid_t> = []
        for process in processes {
            guard AudioDeviceManager.property(process, kAudioProcessPropertyIsRunningOutput) == UInt32(1),
                  let pid: pid_t = AudioDeviceManager.property(process, kAudioProcessPropertyPID),
                  pid != ownPID else { continue }
            result.insert(pid)
        }
        return result
    }

    private static func isOutputDeviceRunning() -> Bool {
        guard let device: AudioObjectID = AudioDeviceManager.property(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice
        ), device != kAudioObjectUnknown else { return false }
        let running: UInt32? = AudioDeviceManager.property(device, kAudioDevicePropertyDeviceIsRunningSomewhere)
        return (running ?? 0) != 0
    }
}
