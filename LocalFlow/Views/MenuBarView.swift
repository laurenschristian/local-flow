import SwiftUI
import Sparkle

struct MenuBarView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updateController = UpdateController.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(appState.status.color)
                    .frame(width: 8, height: 8)
                Text(appState.status.displayText)
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(settings.selectedModel.shortName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("•")
                    .foregroundColor(.secondary)
                Text(settings.selectedModel.qualityLabel)
                    .font(.caption)
                    .foregroundColor(settings.selectedModel.qualityColor)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Double-tap \(settings.triggerKey.displayName) to record")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Hold to continue, release to transcribe")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

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
        .frame(width: 280, height: 180) // Fixed size prevents constraint recalc
        .transaction { $0.animation = nil } // Disable animations
    }
}

#Preview {
    MenuBarView()
}
