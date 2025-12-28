import Foundation
import SwiftUI
import AVFoundation

enum AppError: Equatable {
    case noMicrophone
    case noAccessibility
    case noModel
    case modelLoadFailed
    case modelDownloadFailed
    case recordingFailed
    case transcriptionFailed
    case noAudioRecorded
    case unknown(String)

    var message: String {
        switch self {
        case .noMicrophone:
            return "Microphone access required"
        case .noAccessibility:
            return "Accessibility access required"
        case .noModel:
            return "No speech model installed"
        case .modelLoadFailed:
            return "Failed to load speech model"
        case .modelDownloadFailed:
            return "Failed to download model"
        case .recordingFailed:
            return "Could not start recording"
        case .transcriptionFailed:
            return "Transcription failed"
        case .noAudioRecorded:
            return "No audio detected"
        case .unknown(let msg):
            return msg
        }
    }

    var suggestion: String {
        switch self {
        case .noMicrophone:
            return "Grant microphone access in System Settings"
        case .noAccessibility:
            return "Grant accessibility access in System Settings"
        case .noModel:
            return "Download a model in Settings → Model"
        case .modelLoadFailed:
            return "Try re-downloading the model"
        case .modelDownloadFailed:
            return "Check your internet connection and try again"
        case .recordingFailed:
            return "Check microphone permissions"
        case .transcriptionFailed:
            return "Try speaking more clearly"
        case .noAudioRecorded:
            return "Hold the key while speaking"
        case .unknown:
            return "Try restarting the app"
        }
    }
}

enum AppStatus: Equatable {
    case loading
    case downloading(progress: Double)
    case idle
    case recording
    case transcribing
    case error(AppError)

    var displayText: String {
        switch self {
        case .loading: return "Loading model..."
        case .downloading(let progress): return "Downloading model... \(Int(progress * 100))%"
        case .idle: return "Ready"
        case .recording: return "Recording..."
        case .transcribing: return "Transcribing..."
        case .error(let error): return error.message
        }
    }

    var color: Color {
        switch self {
        case .loading: return .orange
        case .downloading: return .orange
        case .idle: return .green
        case .recording: return .red
        case .transcribing: return .blue
        case .error: return .red
        }
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var status: AppStatus = .loading
    @Published var lastTranscription: String = ""
    @Published var isAccessibilityGranted: Bool = false
    @Published var isMicrophoneGranted: Bool = false

    private init() {
        checkPermissions()
        setupNotifications()
        requestMicrophonePermission()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermissions()
            }
        }
    }

    func checkPermissions() {
        // Check silently - no prompts
        isAccessibilityGranted = AXIsProcessTrusted()

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        isMicrophoneGranted = micStatus == .authorized
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                self?.isMicrophoneGranted = granted
            }
        }
    }
}
