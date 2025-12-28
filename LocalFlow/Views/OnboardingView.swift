import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false
    @ObservedObject private var modelDownloader = ModelDownloader.shared
    @ObservedObject private var settings = Settings.shared

    var onComplete: () -> Void

    private let steps = ["Welcome", "Accessibility", "Microphone", "Model", "Ready"]

    var body: some View {
        VStack(spacing: 0) {
            // Content - no TabView to avoid double indicators
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
        .frame(width: 500, height: 400)
        .onAppear {
            checkPermissions()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("Welcome to LocalFlow")
                .font(.title)
                .fontWeight(.semibold)

            Text("Voice-to-text that runs entirely on your Mac.\nNo internet required, completely private.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()

            Button("Get Started") {
                withAnimation { currentStep = 1 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer().frame(height: 40)
        }
        .padding()
    }

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Accessibility Permission")
                .font(.title2)
                .fontWeight(.semibold)

            Text("LocalFlow needs accessibility access to:\n• Detect your hotkey (double-tap Option)\n• Insert transcribed text into apps")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if accessibilityGranted {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.headline)
            } else {
                Button("Open System Settings") {
                    openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)

                Text("After granting access, click Refresh below")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation { currentStep = 0 }
                }

                Spacer()

                if !accessibilityGranted {
                    Button("Refresh") {
                        checkPermissions()
                    }
                }

                Button("Continue") {
                    withAnimation { currentStep = 2 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!accessibilityGranted)
            }

            Spacer().frame(height: 20)
        }
        .padding()
    }

    private var microphoneStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "mic.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Microphone Permission")
                .font(.title2)
                .fontWeight(.semibold)

            Text("LocalFlow needs microphone access to\nrecord your voice for transcription.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if microphoneGranted {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.headline)
            } else {
                Button("Grant Microphone Access") {
                    requestMicrophonePermission()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation { currentStep = 1 }
                }

                Spacer()

                Button("Continue") {
                    withAnimation { currentStep = 3 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!microphoneGranted)
            }

            Spacer().frame(height: 20)
        }
        .padding()
    }

    private var modelStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cpu.fill")
                .font(.system(size: 60))
                .foregroundColor(.purple)

            Text("Download Speech Model")
                .font(.title2)
                .fontWeight(.semibold)

            if settings.hasAnyModel() {
                Label("Model Ready", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.headline)

                Text("Using \(settings.selectedModel.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if modelDownloader.isDownloading {
                VStack(spacing: 12) {
                    ProgressView(value: modelDownloader.progress)
                        .frame(width: 200)

                    Text("Downloading Base model... \(Int(modelDownloader.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Download the Base model (~142MB) to get started.\nYou can switch models later in Settings.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                Button("Download Model") {
                    Task {
                        await modelDownloader.downloadModel(.base)
                    }
                }
                .buttonStyle(.borderedProminent)

                if let error = modelDownloader.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            HStack {
                Button("Back") {
                    withAnimation { currentStep = 2 }
                }

                Spacer()

                Button("Continue") {
                    withAnimation { currentStep = 4 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.hasAnyModel())
            }

            Spacer().frame(height: 20)
        }
        .padding()
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                Label("Double-tap Option key to start recording", systemImage: "keyboard")
                Label("Hold while speaking", systemImage: "waveform")
                Label("Release to transcribe", systemImage: "text.cursor")
            }
            .font(.body)

            Spacer()

            Button("Start Using LocalFlow") {
                UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer().frame(height: 40)
        }
        .padding()
    }

    private func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                microphoneGranted = granted
            }
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
