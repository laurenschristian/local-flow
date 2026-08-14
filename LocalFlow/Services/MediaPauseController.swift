import AppKit

/// Pauses Spotify/Apple Music while recording and resumes only what it paused.
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

    private init() {}

    func pauseForRecording() {
        queue.async {
            var paused: [Player] = []
            for player in Self.players where self.isRunning(player.bundleId) {
                if self.runScript("tell application \"\(player.appName)\" to player state as string") == "playing" {
                    _ = self.runScript("tell application \"\(player.appName)\" to pause")
                    paused.append(player)
                }
            }
            self.pausedPlayers = paused
        }
    }

    func resumeAfterRecording() {
        queue.async {
            for player in self.pausedPlayers where self.isRunning(player.bundleId) {
                _ = self.runScript("tell application \"\(player.appName)\" to play")
            }
            self.pausedPlayers = []
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
}
