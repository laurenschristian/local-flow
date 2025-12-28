import Foundation
import SwiftUI

enum AppStatus: Equatable {
    case loading
    case idle
    case recording
    case transcribing
    case error(String)

    var displayText: String {
        switch self {
        case .loading: return "Loading model..."
        case .idle: return "Ready"
        case .recording: return "Recording..."
        case .transcribing: return "Transcribing..."
        case .error(let message): return "Error: \(message)"
        }
    }

    var color: Color {
        switch self {
        case .loading: return .orange
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
    }

    func checkPermissions() {
        isAccessibilityGranted = AXIsProcessTrusted()
        // Microphone permission is checked when we start recording
    }
}
