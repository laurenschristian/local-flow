import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var modelDownloader = ModelDownloader.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case hotkey = "Hotkey"
        case model = "Model"
        case apps = "Apps"
        case history = "History"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .hotkey: return "command"
            case .model: return "cpu.fill"
            case .apps: return "app.badge.fill"
            case .history: return "clock.fill"
            case .about: return "info.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
                .frame(width: 180)

            // Content
            ScrollView {
                contentView
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 640, height: 480)
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    private var sidebar: some View {
        VStack(spacing: 4) {
            // App branding
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppStyle.Colors.brand)
                        .frame(width: 48, height: 48)
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text("LocalFlow")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                // Permissions status
                HStack(spacing: 6) {
                    Circle()
                        .fill(accessibilityGranted && microphoneGranted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(accessibilityGranted && microphoneGranted ? "Ready" : "Setup needed")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 16)

            // Navigation items
            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SidebarButton(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()

            // Stats at bottom
            VStack(spacing: 4) {
                Text("\(settings.wordsTranscribedToday)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(AppStyle.Colors.brand)
                Text("words today")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .general:
            generalContent
        case .hotkey:
            hotkeyContent
        case .model:
            modelContent
        case .apps:
            appsContent
        case .history:
            historyContent
        case .about:
            aboutContent
        }
    }

    // MARK: - General

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Permissions", icon: "lock.shield.fill")

            SettingsCard {
                PermissionRow(
                    title: "Accessibility",
                    description: "Detect hotkey and insert text",
                    isGranted: accessibilityGranted,
                    action: openAccessibilitySettings
                )

                Divider().padding(.vertical, 8)

                PermissionRow(
                    title: "Microphone",
                    description: "Record voice for transcription",
                    isGranted: microphoneGranted,
                    action: openMicrophoneSettings
                )
            }

            SectionHeader(title: "Transcription", icon: "text.bubble.fill")

            SettingsCard {
                SettingsToggle(
                    title: "Auto-punctuation",
                    description: "Add periods and capitalize sentences",
                    isOn: $settings.punctuationMode
                )

                Divider().padding(.vertical, 8)

                SettingsToggle(
                    title: "Clipboard only",
                    description: "Copy text without auto-pasting",
                    isOn: $settings.clipboardMode
                )

                Divider().padding(.vertical, 8)

                SettingsToggle(
                    title: "Summary mode",
                    description: "Format as bullet points",
                    isOn: $settings.summaryModeEnabled
                )
            }

            SectionHeader(title: "Sound & Startup", icon: "speaker.wave.2.fill")

            SettingsCard {
                SettingsToggle(
                    title: "Sound effects",
                    description: "Play sounds when recording",
                    isOn: $settings.soundFeedback
                )

                if settings.soundFeedback {
                    Divider().padding(.vertical, 8)

                    SoundPickerRowStyled(
                        label: "Start sound",
                        path: $settings.customStartSoundPath
                    )

                    SoundPickerRowStyled(
                        label: "Stop sound",
                        path: $settings.customStopSoundPath
                    )
                }

                Divider().padding(.vertical, 8)

                SettingsToggle(
                    title: "Launch at login",
                    description: "Start LocalFlow automatically",
                    isOn: $settings.launchAtLogin
                )
            }
        }
    }

    // MARK: - Hotkey

    private var hotkeyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Trigger Key", icon: "command")

            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(TriggerKey.allCases) { key in
                        TriggerKeyOption(
                            key: key,
                            isSelected: settings.triggerKey == key
                        ) {
                            settings.triggerKey = key
                        }
                    }
                }
            }

            HintCard(
                icon: "lightbulb.fill",
                text: "Double-tap and hold to record. Triple-tap to re-paste last transcription."
            )

            SectionHeader(title: "Timing", icon: "timer")

            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Double-tap speed")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(Int(settings.doubleTapInterval * 1000))ms")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppStyle.Colors.brand)
                    }

                    Slider(value: $settings.doubleTapInterval, in: 0.2...0.5, step: 0.05)
                        .tint(AppStyle.Colors.brand)

                    Text("Lower = faster taps required")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Model

    private var modelContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Active Model", icon: "cpu.fill")

            SettingsCard {
                VStack(spacing: 12) {
                    ForEach(WhisperModel.allCases) { model in
                        ModelOptionRow(
                            model: model,
                            isSelected: settings.selectedModel == model,
                            isDownloaded: settings.isModelDownloaded(model),
                            isDownloading: modelDownloader.isDownloading && modelDownloader.currentModel == model,
                            progress: modelDownloader.progress,
                            onSelect: {
                                if settings.isModelDownloaded(model) {
                                    settings.selectedModel = model
                                }
                            },
                            onDownload: {
                                Task { await modelDownloader.downloadModel(model) }
                            }
                        )

                        if model != WhisperModel.allCases.last {
                            Divider()
                        }
                    }
                }
            }

            if let error = modelDownloader.error {
                HintCard(icon: "exclamationmark.triangle.fill", text: error, isError: true)
            }

            HintCard(
                icon: "info.circle.fill",
                text: "Larger models are more accurate but slower. Small is recommended for most users."
            )
        }
    }

    // MARK: - Apps

    private var appsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "App-Specific Settings", icon: "app.badge.fill")

            if settings.appProfiles.isEmpty {
                SettingsCard {
                    VStack(spacing: 16) {
                        Image(systemName: "app.badge")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)

                        Text("No app profiles yet")
                            .font(.system(size: 14, weight: .medium))

                        Text("Create custom settings for specific apps")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Button(action: showAppPicker) {
                            Label("Add App Profile", systemImage: "plus")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppStyle.Colors.brand)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                SettingsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.appProfiles.keys.sorted()), id: \.self) { bundleId in
                            if let profile = settings.appProfiles[bundleId] {
                                AppProfileRowStyled(
                                    bundleId: bundleId,
                                    profile: profile,
                                    onUpdate: { settings.setProfile($0, forApp: bundleId) },
                                    onDelete: { settings.appProfiles.removeValue(forKey: bundleId) }
                                )

                                if bundleId != settings.appProfiles.keys.sorted().last {
                                    Divider().padding(.vertical, 8)
                                }
                            }
                        }
                    }
                }

                Button(action: showAppPicker) {
                    Label("Add App Profile", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - History

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                SectionHeader(title: "Recent Transcriptions", icon: "clock.fill")
                Spacer()
                if !settings.transcriptionHistory.isEmpty {
                    Button("Clear All") {
                        settings.clearHistory()
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                }
            }

            if settings.transcriptionHistory.isEmpty {
                SettingsCard {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)

                        Text("No transcriptions yet")
                            .font(.system(size: 14, weight: .medium))

                        Text("Your recent transcriptions will appear here")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                SettingsCard {
                    VStack(spacing: 0) {
                        ForEach(settings.transcriptionHistory.prefix(10)) { entry in
                            HistoryRowStyled(entry: entry)

                            if entry.id != settings.transcriptionHistory.prefix(10).last?.id {
                                Divider().padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - About

    private var aboutContent: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        return VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppStyle.Colors.brand, AppStyle.Colors.brand.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "waveform")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: AppStyle.Colors.brand.opacity(0.4), radius: 20, y: 10)

            VStack(spacing: 8) {
                Text("LocalFlow")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Version \(version) (Build \(build))")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Text("Local voice dictation powered by Whisper")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Spacer()

            HStack(spacing: 16) {
                Link(destination: URL(string: "https://github.com/laurenschristian/local-flow")!) {
                    Label("GitHub", systemImage: "link")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func showAppPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Select an application"

        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url),
           let bundleId = bundle.bundleIdentifier {
            settings.setProfile(.default, forApp: bundleId)
        }
    }

    private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}

// MARK: - Components

struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppStyle.Colors.brand : Color.clear)
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppStyle.Colors.brand)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

struct HintCard: View {
    let icon: String
    let text: String
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isError ? .red : AppStyle.Colors.brand)

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isError ? Color.red.opacity(0.1) : AppStyle.Colors.brand.opacity(0.05))
        )
    }
}

struct SettingsToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(AppStyle.Colors.brand)
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            } else {
                Button("Grant", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(AppStyle.Colors.brand)
                    .controlSize(.small)
            }
        }
    }
}

struct TriggerKeyOption: View {
    let key: TriggerKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? AppStyle.Colors.brand : Color(nsColor: .quaternaryLabelColor))
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                Text(key.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.primary)

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

struct ModelOptionRow: View {
    let model: WhisperModel
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let progress: Double
    let onSelect: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? AppStyle.Colors.brand : Color(nsColor: .quaternaryLabelColor))
                            .frame(width: 24, height: 24)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .opacity(isDownloaded ? 1 : 0.3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.shortName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isDownloaded ? .primary : .secondary)

                        Text(model.qualityLabel)
                            .font(.system(size: 11))
                            .foregroundColor(model.qualityColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isDownloaded)

            Spacer()

            if isDownloaded {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
            } else if isDownloading {
                ProgressView(value: progress)
                    .frame(width: 80)
                    .tint(AppStyle.Colors.brand)
            } else {
                Button("Download", action: onDownload)
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

struct SoundPickerRowStyled: View {
    let label: String
    @Binding var path: String?

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))

            Spacer()

            if let path = path {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Button("Reset") {
                    self.path = nil
                    NotificationCenter.default.post(name: .customSoundsChanged, object: nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.link)
            }

            Button("Choose...") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.audio]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    self.path = url.path
                    NotificationCenter.default.post(name: .customSoundsChanged, object: nil)
                }
            }
            .font(.system(size: 12))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

struct AppProfileRowStyled: View {
    let bundleId: String
    let profile: AppProfile
    let onUpdate: (AppProfile) -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false

    private var appName: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url),
           let name = bundle.infoDictionary?["CFBundleName"] as? String {
            return name
        }
        return bundleId.components(separatedBy: ".").last ?? bundleId
    }

    private var appIcon: NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    if let icon = appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 28, height: 28)
                    }

                    Text(appName)
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    Toggle("Auto-punctuation", isOn: Binding(
                        get: { profile.punctuationMode },
                        set: { onUpdate(AppProfile(punctuationMode: $0, clipboardMode: profile.clipboardMode, summaryMode: profile.summaryMode)) }
                    ))
                    .toggleStyle(.switch)
                    .tint(AppStyle.Colors.brand)

                    Toggle("Clipboard only", isOn: Binding(
                        get: { profile.clipboardMode },
                        set: { onUpdate(AppProfile(punctuationMode: profile.punctuationMode, clipboardMode: $0, summaryMode: profile.summaryMode)) }
                    ))
                    .toggleStyle(.switch)
                    .tint(AppStyle.Colors.brand)

                    Toggle("Summary mode", isOn: Binding(
                        get: { profile.summaryMode },
                        set: { onUpdate(AppProfile(punctuationMode: profile.punctuationMode, clipboardMode: profile.clipboardMode, summaryMode: $0)) }
                    ))
                    .toggleStyle(.switch)
                    .tint(AppStyle.Colors.brand)

                    Button("Remove Profile", role: .destructive, action: onDelete)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 12))
                .padding(.leading, 36)
            }
        }
    }
}

struct HistoryRowStyled: View {
    let entry: TranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(.system(size: 13))
                .lineLimit(2)

            Text(entry.timestamp, style: .relative)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
