import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var downloadProgress: Double = 0
    @State private var isDownloading: Bool = false
    @State private var downloadError: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            modelTab
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)

                LabeledContent("Double-tap speed") {
                    Slider(value: $settings.doubleTapInterval, in: 0.2...0.5, step: 0.05) {
                        Text("Interval")
                    }
                    Text("\(Int(settings.doubleTapInterval * 1000))ms")
                        .monospacedDigit()
                        .frame(width: 50)
                }
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Accessibility",
                    isGranted: AXIsProcessTrusted(),
                    action: openAccessibilitySettings
                )

                PermissionRow(
                    title: "Microphone",
                    isGranted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                    action: openMicrophoneSettings
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var modelTab: some View {
        Form {
            Section {
                Picker("Active Model", selection: $settings.selectedModel) {
                    ForEach(WhisperModel.allCases) { model in
                        HStack {
                            Text(model.displayName)
                            if settings.isModelDownloaded(model) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .tag(model)
                    }
                }
            }

            Section("Download Models") {
                ForEach(WhisperModel.allCases) { model in
                    ModelRow(
                        model: model,
                        isDownloaded: settings.isModelDownloaded(model),
                        isDownloading: isDownloading && settings.selectedModel == model,
                        progress: downloadProgress,
                        onDownload: { downloadModel(model) }
                    )
                }

                if let error = downloadError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("LocalFlow")
                .font(.title)

            Text("Version 0.1.0")
                .foregroundColor(.secondary)

            Text("Local voice dictation powered by Whisper")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Link("View on GitHub", destination: URL(string: "https://github.com/laurenschristian/local-wisper")!)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func downloadModel(_ model: WhisperModel) {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        Task {
            do {
                let destination = settings.modelsDirectory.appendingPathComponent(model.rawValue)

                let (asyncBytes, response) = try await URLSession.shared.bytes(from: model.downloadURL)

                let totalSize = response.expectedContentLength
                var downloadedSize: Int64 = 0

                let fileHandle = try FileHandle(forWritingTo: destination)
                defer { try? fileHandle.close() }

                // Create empty file first
                FileManager.default.createFile(atPath: destination.path, contents: nil)

                for try await byte in asyncBytes {
                    try fileHandle.write(contentsOf: [byte])
                    downloadedSize += 1

                    if totalSize > 0 {
                        let progress = Double(downloadedSize) / Double(totalSize)
                        await MainActor.run {
                            downloadProgress = progress
                        }
                    }
                }

                await MainActor.run {
                    isDownloading = false
                    downloadProgress = 1.0
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadError = error.localizedDescription
                }
            }
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}

struct PermissionRow: View {
    let title: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant Access") {
                    action()
                }
                .buttonStyle(.link)
            }
        }
    }
}

struct ModelRow: View {
    let model: WhisperModel
    let isDownloaded: Bool
    let isDownloading: Bool
    let progress: Double
    let onDownload: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.displayName)
                Text(formatSize(model.fileSize))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if isDownloading {
                ProgressView(value: progress)
                    .frame(width: 100)
            } else {
                Button("Download") {
                    onDownload()
                }
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

import AVFoundation

#Preview {
    SettingsView()
}
