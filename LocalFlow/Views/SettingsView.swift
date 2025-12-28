import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var downloadProgress: Double = 0
    @State private var isDownloading: Bool = false
    @State private var downloadError: String?

    var body: some View {
        TabView {
            permissionsTab
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            hotkeyTab
                .tabItem {
                    Label("Hotkey", systemImage: "command")
                }

            modelTab
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }

            historyTab
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 360)
    }

    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    private var permissionsTab: some View {
        Form {
            Section {
                Text("LocalFlow requires these permissions to function properly.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Section("Required Permissions") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility")
                            .font(.headline)
                        Text("Detect hotkey and insert text into apps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant Access") {
                            openAccessibilitySettings()
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Microphone")
                            .font(.headline)
                        Text("Record your voice for transcription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if microphoneGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant Access") {
                            openMicrophoneSettings()
                        }
                    }
                }
            }

            Section {
                Button("Refresh Status") {
                    accessibilityGranted = AXIsProcessTrusted()
                    microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    private var generalTab: some View {
        Form {
            Section("Transcription") {
                Toggle("Auto-punctuation", isOn: $settings.punctuationMode)
                    .help("Automatically add periods, commas, and other punctuation")

                Toggle("Clipboard only", isOn: $settings.clipboardMode)
                    .help("Copy to clipboard without auto-pasting")
            }

            Section("Feedback") {
                Toggle("Sound effects", isOn: $settings.soundFeedback)
                    .help("Play sounds when recording starts and stops")
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var hotkeyTab: some View {
        Form {
            Section("Trigger Key") {
                Picker("Activation key", selection: $settings.triggerKey) {
                    ForEach(TriggerKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Double-tap and hold the selected key to start recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Timing") {
                LabeledContent("Double-tap speed") {
                    Slider(value: $settings.doubleTapInterval, in: 0.2...0.5, step: 0.05) {
                        Text("Interval")
                    }
                    Text("\(Int(settings.doubleTapInterval * 1000))ms")
                        .monospacedDigit()
                        .frame(width: 50)
                }

                Text("Lower values require faster double-taps")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

    private var historyTab: some View {
        VStack {
            if settings.transcriptionHistory.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock",
                    description: Text("Your recent transcriptions will appear here")
                )
            } else {
                List {
                    ForEach(settings.transcriptionHistory) { entry in
                        HistoryRow(entry: entry)
                    }
                }
                .listStyle(.inset)

                HStack {
                    Spacer()
                    Button("Clear History") {
                        settings.clearHistory()
                    }
                    .buttonStyle(.link)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("LocalFlow")
                .font(.title)

            Text("Version 0.1.0")
                .foregroundColor(.secondary)

            Text("Local voice dictation powered by Whisper")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Link("View on GitHub", destination: URL(string: "https://github.com/laurenschristian/local-flow")!)
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
                FileManager.default.createFile(atPath: destination.path, contents: nil)

                let (asyncBytes, response) = try await URLSession.shared.bytes(from: model.downloadURL)

                let totalSize = response.expectedContentLength
                var downloadedSize: Int64 = 0

                let fileHandle = try FileHandle(forWritingTo: destination)
                defer { try? fileHandle.close() }

                var buffer = [UInt8]()
                buffer.reserveCapacity(65536)

                for try await byte in asyncBytes {
                    buffer.append(byte)
                    downloadedSize += 1

                    if buffer.count >= 65536 {
                        try fileHandle.write(contentsOf: buffer)
                        buffer.removeAll(keepingCapacity: true)

                        if totalSize > 0 {
                            let progress = Double(downloadedSize) / Double(totalSize)
                            await MainActor.run {
                                downloadProgress = progress
                            }
                        }
                    }
                }

                if !buffer.isEmpty {
                    try fileHandle.write(contentsOf: buffer)
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

struct HistoryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .lineLimit(2)

            Text(entry.timestamp, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            }
        }
    }
}

#Preview {
    SettingsView()
}
