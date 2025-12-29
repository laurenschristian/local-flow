import Foundation
import ServiceManagement

import SwiftUI

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

    var shortName: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        }
    }

    var qualityLabel: String {
        switch self {
        case .tiny: return "Basic"
        case .base: return "Good"
        case .small: return "Better"
        case .medium: return "Best"
        }
    }

    var qualityColor: Color {
        switch self {
        case .tiny: return .orange
        case .base: return .yellow
        case .small: return .green
        case .medium: return .blue
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

enum TriggerKey: String, CaseIterable, Identifiable {
    case option = "option"
    case rightOption = "rightOption"
    case fn = "fn"
    case control = "control"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .option: return "Option (⌥)"
        case .rightOption: return "Right Option (⌥)"
        case .fn: return "Fn"
        case .control: return "Control (⌃)"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .option: return 58
        case .rightOption: return 61
        case .fn: return 63
        case .control: return 59
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

    @Published var triggerKey: TriggerKey {
        didSet {
            defaults.set(triggerKey.rawValue, forKey: "triggerKey")
            NotificationCenter.default.post(name: .triggerKeyChanged, object: nil)
        }
    }

    @Published var doubleTapInterval: Double {
        didSet {
            defaults.set(doubleTapInterval, forKey: "doubleTapInterval")
        }
    }

    @Published var punctuationMode: Bool {
        didSet {
            defaults.set(punctuationMode, forKey: "punctuationMode")
        }
    }

    @Published var clipboardMode: Bool {
        didSet {
            defaults.set(clipboardMode, forKey: "clipboardMode")
        }
    }

    @Published var soundFeedback: Bool {
        didSet {
            defaults.set(soundFeedback, forKey: "soundFeedback")
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }

    @Published var transcriptionHistory: [TranscriptionEntry] {
        didSet {
            saveHistory()
        }
    }

    // Stats
    @Published var wordsTranscribedToday: Int {
        didSet {
            defaults.set(wordsTranscribedToday, forKey: "wordsTranscribedToday")
            defaults.set(Date(), forKey: "statsDate")
        }
    }

    // Custom sounds
    @Published var customStartSoundPath: String? {
        didSet {
            defaults.set(customStartSoundPath, forKey: "customStartSoundPath")
        }
    }

    @Published var customStopSoundPath: String? {
        didSet {
            defaults.set(customStopSoundPath, forKey: "customStopSoundPath")
        }
    }

    // App-specific profiles
    @Published var appProfiles: [String: AppProfile] {
        didSet {
            saveAppProfiles()
        }
    }

    // Summary mode
    @Published var summaryModeEnabled: Bool {
        didSet {
            defaults.set(summaryModeEnabled, forKey: "summaryModeEnabled")
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

        let savedTriggerKey = defaults.string(forKey: "triggerKey") ?? TriggerKey.option.rawValue
        self.triggerKey = TriggerKey(rawValue: savedTriggerKey) ?? .option

        self.doubleTapInterval = defaults.double(forKey: "doubleTapInterval").nonZero ?? 0.3
        self.punctuationMode = defaults.bool(forKey: "punctuationMode")
        self.clipboardMode = defaults.bool(forKey: "clipboardMode")
        self.soundFeedback = defaults.object(forKey: "soundFeedback") as? Bool ?? true
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.transcriptionHistory = Self.loadHistory()

        // Load stats (reset if new day)
        let statsDate = defaults.object(forKey: "statsDate") as? Date ?? Date.distantPast
        if Calendar.current.isDateInToday(statsDate) {
            self.wordsTranscribedToday = defaults.integer(forKey: "wordsTranscribedToday")
        } else {
            self.wordsTranscribedToday = 0
        }

        // Custom sounds
        self.customStartSoundPath = defaults.string(forKey: "customStartSoundPath")
        self.customStopSoundPath = defaults.string(forKey: "customStopSoundPath")

        // App profiles
        self.appProfiles = Self.loadAppProfiles()

        // Summary mode
        self.summaryModeEnabled = defaults.bool(forKey: "summaryModeEnabled")
    }

    func addWordsToStats(_ count: Int) {
        wordsTranscribedToday += count
    }

    func profileForApp(_ bundleId: String) -> AppProfile? {
        appProfiles[bundleId]
    }

    func setProfile(_ profile: AppProfile, forApp bundleId: String) {
        appProfiles[bundleId] = profile
    }

    private func saveAppProfiles() {
        if let data = try? JSONEncoder().encode(appProfiles) {
            defaults.set(data, forKey: "appProfiles")
        }
    }

    private static func loadAppProfiles() -> [String: AppProfile] {
        guard let data = UserDefaults.standard.data(forKey: "appProfiles"),
              let profiles = try? JSONDecoder().decode([String: AppProfile].self, from: data) else {
            return [:]
        }
        return profiles
    }

    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let path = modelsDirectory.appendingPathComponent(model.rawValue).path
        return FileManager.default.fileExists(atPath: path)
    }

    func hasAnyModel() -> Bool {
        WhisperModel.allCases.contains { isModelDownloaded($0) }
    }

    func firstAvailableModel() -> WhisperModel? {
        WhisperModel.allCases.first { isModelDownloaded($0) }
    }

    func addToHistory(_ text: String) {
        let entry = TranscriptionEntry(text: text, timestamp: Date())
        transcriptionHistory.insert(entry, at: 0)
        if transcriptionHistory.count > 50 {
            transcriptionHistory = Array(transcriptionHistory.prefix(50))
        }
    }

    func clearHistory() {
        transcriptionHistory = []
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[LocalFlow] Failed to update launch at login: \(error)")
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(transcriptionHistory) {
            defaults.set(data, forKey: "transcriptionHistory")
        }
    }

    private static func loadHistory() -> [TranscriptionEntry] {
        guard let data = UserDefaults.standard.data(forKey: "transcriptionHistory"),
              let history = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) else {
            return []
        }
        return history
    }
}

struct TranscriptionEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date

    init(text: String, timestamp: Date) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
    }
}

struct AppProfile: Codable, Equatable {
    var punctuationMode: Bool
    var clipboardMode: Bool
    var summaryMode: Bool

    static let `default` = AppProfile(
        punctuationMode: false,
        clipboardMode: false,
        summaryMode: false
    )
}

extension Notification.Name {
    static let triggerKeyChanged = Notification.Name("triggerKeyChanged")
    static let customSoundsChanged = Notification.Name("customSoundsChanged")
}

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
