import SwiftUI
import Sparkle

struct MenuBarView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updateController = UpdateController.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status
            HStack {
                Circle()
                    .fill(appState.status.color)
                    .frame(width: 8, height: 8)
                Text(appState.status.displayText)
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Instructions
            VStack(alignment: .leading, spacing: 4) {
                Text("Double-tap \(settings.triggerKey.displayName) to record")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Hold to continue, release to transcribe")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Last transcription
            if !appState.lastTranscription.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(appState.lastTranscription)
                        .font(.caption)
                        .lineLimit(3)
                }
            }

            Divider()

            // Actions
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Settings...") {
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                    }
                    .buttonStyle(.link)

                    Spacer()

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.link)
                }

                Button("Check for Updates...") {
                    updateController.checkForUpdates()
                }
                .buttonStyle(.link)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            appState.checkPermissions()
        }
    }

}

#Preview {
    MenuBarView()
}
