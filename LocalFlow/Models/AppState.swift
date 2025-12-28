import Foundation
import SwiftUI
import AVFoundation

enum AppStatus: Equatable {
    case loading
    case downloading(progress: Double)
    case idle
    case recording
    case transcribing
    case error(String)

    var displayText: String {
        switch self {
        case .loading: return "Loading model..."
        case .downloading(let progress): return "Downloading model... \(Int(progress * 100))%"
        case .idle: return "Ready"
        case .recording: return "Recording..."
        case .transcribing: return "Transcribing..."
        case .error(let message): return "Error: \(message)"
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
