import SwiftUI

struct MenuBarView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var settings = Settings.shared

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
                Text("Double-tap Option key to record")
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

            // Permissions status
            if !appState.isAccessibilityGranted {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Accessibility access required")
                        .font(.caption)
                }
                .onTapGesture {
                    openAccessibilitySettings()
                }
            }

            // Actions
            HStack {
                Button("Settings...") {
                    openSettings()
                }
                .buttonStyle(.link)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
            }
        }
        .padding()
        .frame(width: 260)
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    MenuBarView()
}
