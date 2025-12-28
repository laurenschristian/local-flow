import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny = "ggml-tiny.en.bin"
    case base = "ggml-base.en.bin"
    case small = "ggml-small.en.bin"
    case medium = "ggml-medium.en.bin"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (75MB) - Fastest"
        case .base: return "Base (142MB) - Fast"
        case .small: return "Small (466MB) - Recommended"
        case .medium: return "Medium (1.5GB) - Accurate"
        }
    }

    var downloadURL: URL {
        let base = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
        return URL(string: base + rawValue)!
    }

    var fileSize: Int64 {
        switch self {
        case .tiny: return 75_000_000
        case .base: return 142_000_000
        case .small: return 466_000_000
        case .medium: return 1_500_000_000
        }
    }
}

class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var selectedModel: WhisperModel {
        didSet {
            defaults.set(selectedModel.rawValue, forKey: "selectedModel")
        }
    }

    @Published var doubleTapInterval: Double {
        didSet {
            defaults.set(doubleTapInterval, forKey: "doubleTapInterval")
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            // TODO: Implement launch at login via SMAppService
        }
    }

    var modelPath: String {
        let modelsDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("LocalFlow/Models")

        return modelsDir.appendingPathComponent(selectedModel.rawValue).path
    }

    var modelsDirectory: URL {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("LocalFlow/Models")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        let savedModel = defaults.string(forKey: "selectedModel") ?? WhisperModel.small.rawValue
        self.selectedModel = WhisperModel(rawValue: savedModel) ?? .small
        self.doubleTapInterval = defaults.double(forKey: "doubleTapInterval").nonZero ?? 0.3
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
    }

    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let path = modelsDirectory.appendingPathComponent(model.rawValue).path
        return FileManager.default.fileExists(atPath: path)
    }
}

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
