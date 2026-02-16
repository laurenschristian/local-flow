import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import ApplicationServices

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var modelDownloader = ModelDownloader.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false
    @State private var permissionTimer: Timer?
    @Environment(\.colorScheme) private var colorScheme

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
            // Gradient glass sidebar
            sidebar
                .frame(width: 200)

            // Content area
            ScrollView {
                contentView
                    .padding(28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppStyle.Colors.windowBackground)
        }
        .frame(width: 680, height: 520)
        .onAppear {
            checkPermissions()
            startPermissionPolling()
        }
        .onDisappear {
            permissionTimer?.invalidate()
        }
    }

    private func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            accessibilityGranted = AXIsProcessTrusted()
            microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ZStack {
            // Glass background
            SidebarGlassBackground()

            VStack(spacing: 0) {
                // App branding
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)

                        Image(systemName: "waveform")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text("LocalFlow")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    // Status pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(accessibilityGranted && microphoneGranted ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(accessibilityGranted && microphoneGranted ? "Ready" : "Setup needed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.1))
                    )
                }
                .padding(.top, 24)
                .padding(.bottom, 20)

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                // Navigation
                VStack(spacing: 4) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        SidebarNavButton(
                            title: tab.rawValue,
                            icon: tab.icon,
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()

                // Stats footer
                VStack(spacing: 4) {
                    Text("\(settings.wordsTranscribedToday)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("words today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Content

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
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Permissions", icon: "lock.shield.fill")

            GlassCard {
                PermissionRow(
                    title: "Accessibility",
                    description: "Detect hotkey and insert text",
                    isGranted: accessibilityGranted,
                    action: openAccessibilitySettings
                )

                CardDivider()

                PermissionRow(
                    title: "Microphone",
                    description: "Record voice for transcription",
                    isGranted: microphoneGranted,
                    action: openMicrophoneSettings
                )
            }

            SectionHeader(title: "Language", icon: "globe")

            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcription language")
                            .font(.system(size: 13, weight: .medium))
                        Text("Language spoken in your recordings")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("", selection: $settings.language) {
                        ForEach(TranscriptionLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            SectionHeader(title: "Transcription", icon: "text.bubble.fill")

            GlassCard {
                SettingsToggle(
                    title: "Auto-punctuation",
                    description: "Add periods and capitalize sentences",
                    isOn: $settings.punctuationMode
                )

                CardDivider()

                SettingsToggle(
                    title: "Clipboard only",
                    description: "Copy text without auto-pasting",
                    isOn: $settings.clipboardMode
                )

                CardDivider()

                SettingsToggle(
                    title: "Summary mode",
                    description: "Format as bullet points",
                    isOn: $settings.summaryModeEnabled
                )
            }

            SectionHeader(title: "Sound & Startup", icon: "speaker.wave.2.fill")

            GlassCard {
                SettingsToggle(
                    title: "Sound effects",
                    description: "Play sounds when recording",
                    isOn: $settings.soundFeedback
                )

                if settings.soundFeedback {
                    CardDivider()

                    SoundPickerRow(
                        label: "Start sound",
                        path: $settings.customStartSoundPath
                    )

                    SoundPickerRow(
                        label: "Stop sound",
                        path: $settings.customStopSoundPath
                    )
                }

                CardDivider()

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
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Trigger Key", icon: "command")

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
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

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Double-tap speed")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(Int(settings.doubleTapInterval * 1000))ms")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(AppStyle.Colors.adaptiveAccent(for: colorScheme))
                    }

                    Slider(value: $settings.doubleTapInterval, in: 0.2...0.5, step: 0.05)
                        .tint(AppStyle.Colors.adaptiveTint(for: colorScheme))

                    Text("Lower = faster taps required")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Model

    private var modelContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Whisper Model", icon: "cpu.fill")

            GlassCard {
                VStack(spacing: 0) {
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
                            CardDivider()
                        }
                    }
                }
            }

            if let error = modelDownloader.error {
                HintCard(icon: "exclamationmark.triangle.fill", text: error, isError: true)
            }

            if WhisperModel.allCases.contains(where: { settings.hasLegacyModel($0) }) {
                HintCard(
                    icon: "arrow.triangle.2.circlepath",
                    text: "Models have been updated to support multiple languages. Please download the new multilingual model to continue. Old English-only models can be safely removed."
                )
            }

            HintCard(
                icon: "info.circle.fill",
                text: "Larger models are more accurate but slower. Small is recommended for most users. All models support 99+ languages."
            )
        }
    }

    // MARK: - Apps

    private var appsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "App-Specific Settings", icon: "app.badge.fill")

            if settings.appProfiles.isEmpty {
                GlassCard {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(AppStyle.Colors.adaptiveAccent(for: colorScheme).opacity(0.1))
                                .frame(width: 64, height: 64)
                            Image(systemName: "app.badge")
                                .font(.system(size: 28))
                                .foregroundColor(AppStyle.Colors.adaptiveAccent(for: colorScheme))
                        }

                        VStack(spacing: 6) {
                            Text("No app profiles yet")
                                .font(.system(size: 15, weight: .semibold))

                            Text("Create custom settings for specific apps")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        Button(action: showAppPicker) {
                            Label("Add App Profile", systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppStyle.Colors.adaptiveTint(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.appProfiles.keys.sorted()), id: \.self) { bundleId in
                            if let profile = settings.appProfiles[bundleId] {
                                AppProfileRow(
                                    bundleId: bundleId,
                                    profile: profile,
                                    onUpdate: { settings.setProfile($0, forApp: bundleId) },
                                    onDelete: { settings.appProfiles.removeValue(forKey: bundleId) }
                                )

                                if bundleId != settings.appProfiles.keys.sorted().last {
                                    CardDivider()
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
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                SectionHeader(title: "Recent Transcriptions", icon: "clock.fill")
                Spacer()
                if !settings.transcriptionHistory.isEmpty {
                    Button("Clear All") {
                        settings.clearHistory()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                }
            }

            if settings.transcriptionHistory.isEmpty {
                GlassCard {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(AppStyle.Colors.adaptiveAccent(for: colorScheme).opacity(0.1))
                                .frame(width: 64, height: 64)
                            Image(systemName: "clock")
                                .font(.system(size: 28))
                                .foregroundColor(AppStyle.Colors.adaptiveAccent(for: colorScheme))
                        }

                        VStack(spacing: 6) {
                            Text("No transcriptions yet")
                                .font(.system(size: 15, weight: .semibold))

                            Text("Your recent transcriptions will appear here")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(settings.transcriptionHistory.prefix(10)) { entry in
                            HistoryRow(entry: entry)

                            if entry.id != settings.transcriptionHistory.prefix(10).last?.id {
                                CardDivider()
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

        return VStack(spacing: 28) {
            Spacer()

            // Logo with glow
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppStyle.Colors.brand, AppStyle.Colors.brand.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: AppStyle.Colors.brand.opacity(0.5), radius: 24, y: 8)

                Image(systemName: "waveform")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text("LocalFlow")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("Version \(version) (Build \(build))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Text("Local voice dictation powered by Whisper")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    UpdateController.shared.checkForUpdates()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                        Text("Check for Updates")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppStyle.Colors.adaptiveTint(for: colorScheme))

                Link(destination: URL(string: "https://github.com/laurenschristian/local-flow")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                        Text("Star on GitHub")
                            .font(.system(size: 13, weight: .medium))
                    }
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
        // Trigger native macOS accessibility permission dialog
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}

// MARK: - Glass Components

struct SidebarGlassBackground: View {
    var body: some View {
        ZStack {
            // Gradient base
            LinearGradient(
                colors: [
                    AppStyle.Colors.brand,
                    AppStyle.Colors.brand.opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Noise texture overlay
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.1)

            // Edge highlight
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark
                    ? Color.white.opacity(0.06)
                    : Color.white.opacity(0.8))
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(colorScheme == .dark ? 0.5 : 0.3)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [.white.opacity(0.2), .white.opacity(0.05), .clear]
                            : [.black.opacity(0.1), .black.opacity(0.05), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.08),
            radius: colorScheme == .dark ? 8 : 4,
            y: colorScheme == .dark ? 4 : 2
        )
    }
}

struct CardDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 12)
    }
}

struct SidebarNavButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? .white.opacity(0.2) : .clear)
            )
            .foregroundColor(.white.opacity(isSelected ? 1 : 0.75))
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppStyle.Colors.adaptiveAccent(for: colorScheme))
            Text(title)
                .font(.system(size: 14, weight: .bold))
        }
    }
}

struct HintCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let text: String
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isError ? .red : AppStyle.Colors.adaptiveAccent(for: colorScheme))

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isError
                    ? Color.red.opacity(colorScheme == .dark ? 0.15 : 0.1)
                    : (colorScheme == .dark ? Color.white.opacity(0.08) : AppStyle.Colors.brand.opacity(0.08)))
        )
    }
}

struct SettingsToggle: View {
    @Environment(\.colorScheme) private var colorScheme
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
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(AppStyle.Colors.adaptiveTint(for: colorScheme))
    }
}

struct PermissionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Granted")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
            } else {
                Button("Request Access", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(AppStyle.Colors.adaptiveTint(for: colorScheme))
                    .controlSize(.small)
            }
        }
    }
}

struct TriggerKeyOption: View {
    @Environment(\.colorScheme) private var colorScheme
    let key: TriggerKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected
                            ? AppStyle.Colors.adaptiveAccent(for: colorScheme)
                            : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)))
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                    }
                }

                Text(key.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

struct ModelOptionRow: View {
    @Environment(\.colorScheme) private var colorScheme
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
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected
                                ? AppStyle.Colors.adaptiveAccent(for: colorScheme)
                                : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)))
                            .frame(width: 24, height: 24)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .black : .white)
                        }
                    }
                    .opacity(isDownloaded ? 1 : 0.4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.shortName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isDownloaded ? .primary : .secondary)

                        HStack(spacing: 6) {
                            Text(model.qualityLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(model.qualityColor)

                            Text("•")
                                .foregroundStyle(.tertiary)

                            Text(formatSize(model.fileSize))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isDownloaded)

            Spacer()

            if isDownloaded {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Ready")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
            } else if isDownloading {
                ProgressView(value: progress)
                    .frame(width: 80)
                    .tint(AppStyle.Colors.adaptiveTint(for: colorScheme))
            } else {
                Button("Download", action: onDownload)
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct SoundPickerRow: View {
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
                    .foregroundStyle(.secondary)
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
        .padding(.vertical, 6)
    }
}

struct AppProfileRow: View {
    @Environment(\.colorScheme) private var colorScheme
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
        VStack(spacing: 14) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    if let icon = appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 32, height: 32)
                    }

                    Text(appName)
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 10) {
                    Toggle("Auto-punctuation", isOn: Binding(
                        get: { profile.punctuationMode },
                        set: { onUpdate(AppProfile(punctuationMode: $0, clipboardMode: profile.clipboardMode, summaryMode: profile.summaryMode)) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(AppStyle.Colors.adaptiveTint(for: colorScheme))

                    Toggle("Clipboard only", isOn: Binding(
                        get: { profile.clipboardMode },
                        set: { onUpdate(AppProfile(punctuationMode: profile.punctuationMode, clipboardMode: $0, summaryMode: profile.summaryMode)) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(AppStyle.Colors.adaptiveTint(for: colorScheme))

                    Toggle("Summary mode", isOn: Binding(
                        get: { profile.summaryMode },
                        set: { onUpdate(AppProfile(punctuationMode: profile.punctuationMode, clipboardMode: profile.clipboardMode, summaryMode: $0)) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(AppStyle.Colors.adaptiveTint(for: colorScheme))

                    Button("Remove Profile", role: .destructive, action: onDelete)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                }
                .font(.system(size: 12))
                .padding(.leading, 44)
            }
        }
    }
}

struct HistoryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(.system(size: 13))
                .lineLimit(2)

            Text(entry.timestamp, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

#Preview {
    SettingsView()
}
