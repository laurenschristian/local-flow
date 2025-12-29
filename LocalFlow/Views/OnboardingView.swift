import SwiftUI
import AVFoundation
import ApplicationServices

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false
    @State private var permissionCheckTimer: Timer?
    @ObservedObject private var modelDownloader = ModelDownloader.shared
    @ObservedObject private var settings = Settings.shared

    var onComplete: () -> Void

    private let steps = ["Welcome", "Accessibility", "Microphone", "Model", "Ready"]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: accessibilityStep
                case 2: microphoneStep
                case 3: modelStep
                case 4: readyStep
                default: welcomeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 440)
        .onAppear {
            checkPermissions()
        }
        .onDisappear {
            permissionCheckTimer?.invalidate()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 24) {
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
                    .frame(width: 88, height: 88)
                    .shadow(color: AppStyle.Colors.brand.opacity(0.4), radius: 20, y: 8)

                Image(systemName: "waveform")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text("Welcome to LocalFlow")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Text("Voice-to-text that runs entirely on your Mac.\nNo internet required, completely private.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Get Started") {
                withAnimation(.easeInOut(duration: 0.25)) { currentStep = 1 }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppStyle.Colors.brand)
            .controlSize(.large)

            Spacer().frame(height: 40)
        }
        .padding(32)
    }

    private var accessibilityStep: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "hand.raised.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.orange)
            }

            VStack(spacing: 8) {
                Text("Accessibility Permission")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("LocalFlow needs accessibility access to detect\nyour hotkey and insert transcribed text.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            if accessibilityGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Permission Granted")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 16) {
                    Button("Request Access") {
                        requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppStyle.Colors.brand)
                    .controlSize(.large)

                    // Help text for updates
                    VStack(spacing: 6) {
                        Text("A system dialog will appear.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                            Text("Updating? You may need to remove the old entry first.")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.25)) { currentStep = 0 }
                }

                Spacer()

                Button("Continue") {
                    withAnimation(.easeInOut(duration: 0.25)) { currentStep = 2 }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppStyle.Colors.brand)
                .disabled(!accessibilityGranted)
            }

            Spacer().frame(height: 20)
        }
        .padding(32)
        .onAppear {
            startPermissionPolling()
        }
        .onDisappear {
            permissionCheckTimer?.invalidate()
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                Text("Microphone Permission")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("LocalFlow needs microphone access to\nrecord your voice for transcription.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            if microphoneGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Permission Granted")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.vertical, 8)
            } else {
                Button("Grant Microphone Access") {
                    requestMicrophonePermission()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppStyle.Colors.brand)
                .controlSize(.large)
            }

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.25)) { currentStep = 1 }
                }

                Spacer()

                Button("Continue") {
                    withAnimation(.easeInOut(duration: 0.25)) { currentStep = 3 }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppStyle.Colors.brand)
                .disabled(!microphoneGranted)
            }

            Spacer().frame(height: 20)
        }
        .padding(32)
    }

    private var modelStep: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "cpu.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.purple)
            }

            VStack(spacing: 8) {
                Text("Download Speech Model")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                if settings.hasAnyModel() {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Model Ready")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.green)
                    }

                    Text("Using \(settings.selectedModel.shortName)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else if modelDownloader.isDownloading {
                    VStack(spacing: 14) {
                        ProgressView(value: modelDownloader.progress)
                            .frame(width: 220)
                            .tint(AppStyle.Colors.brand)

                        Text("Downloading Base model... \(Int(modelDownloader.progress * 100))%")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Download the Base model (~142MB) to get started.\nYou can switch models later in Settings.")
                        .multilineTextAlignment(.center)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    Button("Download Model") {
                        Task {
                            await modelDownloader.downloadModel(.base)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppStyle.Colors.brand)
                    .controlSize(.large)

                    if let error = modelDownloader.error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.25)) { currentStep = 2 }
                }

                Spacer()

                Button("Continue") {
                    withAnimation(.easeInOut(duration: 0.25)) { currentStep = 4 }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppStyle.Colors.brand)
                .disabled(!settings.hasAnyModel())
            }

            Spacer().frame(height: 20)
        }
        .padding(32)
    }

    private var readyStep: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
            }

            Text("You're All Set!")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 14) {
                InstructionRow(icon: "keyboard", text: "Double-tap Option key to start recording")
                InstructionRow(icon: "waveform", text: "Hold while speaking")
                InstructionRow(icon: "text.cursor", text: "Release to transcribe and paste")
            }
            .padding(.horizontal, 20)

            Spacer()

            Button("Start Using LocalFlow") {
                UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppStyle.Colors.brand)
            .controlSize(.large)

            Spacer().frame(height: 40)
        }
        .padding(32)
    }

    // MARK: - Helpers

    private func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func startPermissionPolling() {
        // Poll for accessibility permission changes since there's no notification for it
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let wasGranted = accessibilityGranted
            accessibilityGranted = AXIsProcessTrusted()

            // Auto-advance if permission was just granted
            if !wasGranted && accessibilityGranted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep = 2
                    }
                }
            }
        }
    }

    private func requestAccessibilityPermission() {
        // This triggers the native macOS accessibility permission dialog
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                microphoneGranted = granted
                if granted {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentStep = 3
                        }
                    }
                }
            }
        }
    }
}

struct InstructionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppStyle.Colors.brand)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 14))
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
