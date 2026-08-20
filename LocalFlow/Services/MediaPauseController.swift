import AppKit
import CoreAudio
import Darwin

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
    private var outputRateAtPause: Float64?

    private init() {}

    func pauseForRecording() {
        let playing = Self.playingMediaApps()
        let outputRate = AudioDeviceManager.defaultOutputSampleRate()
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
            self.outputRateAtPause = outputRate

            // Whatever we could not script (browsers, video apps) only answers the
            // media key. Apps keep their audio stream open for seconds after
            // pausing, so the press cannot be verified: press once, press back later.
            let unscripted = playing.subtracting(paused.map(\.bundleId))
            guard !unscripted.isEmpty else { return }
            print("[LocalFlow] Media: play/pause key for \(unscripted.sorted().joined(separator: ", "))")
            Self.sendPlayPauseKey()
            self.pausedViaMediaKey = true
        }
    }

    func resumeAfterRecording() {
        queue.async { self.resume(waitForOutput: true) }
    }

    /// Blocking variant for app termination, where a queued resume would never
    /// run and would leave the user's music paused for good.
    func resumeAfterRecordingNow() {
        queue.sync { self.resume(waitForOutput: false) }
    }

    private func resume(waitForOutput: Bool) {
        if waitForOutput { waitForOutputDevice() }
        for player in pausedPlayers where isRunning(player.bundleId) {
            _ = runScript("tell application \"\(player.appName)\" to play")
        }
        pausedPlayers = []
        if pausedViaMediaKey {
            Self.sendPlayPauseKey()
            pausedViaMediaKey = false
        }
    }

    /// A headset that just lent its mic comes back at call-mode sample rate;
    /// resuming into that gives silence, so let the output device settle first.
    private func waitForOutputDevice() {
        guard let expected = outputRateAtPause else { return }
        outputRateAtPause = nil
        for _ in 0..<15 {
            if AudioDeviceManager.defaultOutputSampleRate() == expected { return }
            Thread.sleep(forTimeInterval: 0.1)
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

    // MARK: - Which media apps are making sound

    private static let mediaBundleIds: Set<String> = [
        "com.spotify.client", "com.apple.Music", "com.apple.TV", "com.apple.podcasts",
        "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
        "org.mozilla.firefox", "company.thebrowser.Browser", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "org.videolan.vlc", "com.colliderli.iina",
        "com.apple.QuickTimePlayerX", "com.plexapp.plexamp", "tv.plex.desktop",
    ]

    /// Bundle ids of media apps currently playing. Communication apps are left
    /// out on purpose: pressing the media key during a call would start music.
    private static func playingMediaApps() -> Set<String> {
        guard #available(macOS 14.4, *) else { return [] }
        let processes: [AudioObjectID] = AudioDeviceManager.propertyList(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: Set<String> = []
        for process in processes {
            guard AudioDeviceManager.property(process, kAudioProcessPropertyIsRunningOutput) == UInt32(1),
                  let pid: pid_t = AudioDeviceManager.property(process, kAudioProcessPropertyPID),
                  pid != ownPID, let bundleId = owningBundleId(of: pid) else { continue }
            if mediaBundleIds.contains(bundleId) {
                result.insert(bundleId)
            } else {
                print("[LocalFlow] Media: ignoring audio from \(bundleId)")
            }
        }
        return result
    }

    /// Browsers play through helper processes, so walk the path back to the .app.
    private static func owningBundleId(of pid: pid_t) -> String? {
        if let app = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier { return app }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        if path.contains("WebKit") { return "com.apple.Safari" }
        guard let range = path.range(of: ".app/") else { return nil }
        return Bundle(path: String(path[path.startIndex..<range.lowerBound]) + ".app")?.bundleIdentifier
    }
}
