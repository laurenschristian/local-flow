import SwiftUI

/// Custom menu bar dropdown shown from an NSPopover instead of an NSMenu.
struct MenuBarPanelView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var settings = Settings.shared
    @State private var inputDevices: [AudioInputDevice] = []

    let onPaste: (String) -> Void
    let onOpenSettings: () -> Void
    let onCheckUpdates: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PanelDivider()
            controls
            PanelDivider()
            recentSection
            PanelDivider()
            footer
        }
        .frame(width: 320)
        .onAppear { inputDevices = AudioDeviceManager.inputDevices() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(appState.status.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text("LocalFlow")
                    .font(.system(size: 13, weight: .semibold))
                Text(appState.status.displayText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(settings.wordsTranscribedToday)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text("words today")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 8) {
            PanelRow(label: "Microphone") {
                Picker("", selection: micBinding) {
                    Text("System Default").tag("")
                    ForEach(inputDevices, id: \.uid) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 160)
            }

            PanelRow(label: "Model") {
                Picker("", selection: $settings.selectedModel) {
                    ForEach(downloadedModels) { model in
                        Text(model.shortName).tag(model)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 160)
            }

            HStack {
                Text("Record")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Double-tap \(settings.triggerKey.displayName)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var micBinding: Binding<String> {
        Binding(
            get: { settings.selectedInputDeviceUID ?? "" },
            set: { settings.selectedInputDeviceUID = $0.isEmpty ? nil : $0 }
        )
    }

    private var downloadedModels: [WhisperModel] {
        let downloaded = WhisperModel.allCases.filter { settings.isModelDownloaded($0) }
        // Selected model must be in the picker even if its file went missing.
        if !downloaded.contains(settings.selectedModel) {
            return downloaded + [settings.selectedModel]
        }
        return downloaded
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !settings.transcriptionHistory.isEmpty {
                    Text("click to paste")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)

            if settings.transcriptionHistory.isEmpty {
                Text("No transcriptions yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(settings.transcriptionHistory.prefix(5)) { entry in
                        RecentRow(entry: entry) { onPaste(entry.text) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 0) {
            FooterButton(title: "Settings", action: onOpenSettings)
            FooterDivider()
            FooterButton(title: "Updates", action: onCheckUpdates)
            FooterDivider()
            FooterButton(title: "Quit", action: onQuit)
        }
        .frame(height: 36)
    }
}

// MARK: - Components

private struct PanelRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            content
        }
    }
}

private struct RecentRow: View {
    let entry: TranscriptionEntry
    let action: () -> Void
    @State private var isHovering = false

    private var preview: String {
        entry.text.replacingOccurrences(of: "\n", with: " ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(preview)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(entry.text)
    }
}

private struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isHovering ? Color.primary.opacity(0.06) : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct FooterDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 16)
    }
}

private struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}
