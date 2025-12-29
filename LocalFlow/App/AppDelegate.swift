import Cocoa
import SwiftUI
import AVFoundation
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var audioRecorder: AudioRecorder!
    private var whisperService: WhisperService!
    private var textInserter: TextInserter!
    private var downloadCancellable: AnyCancellable?

    private var startSound: NSSound?
    private var stopSound: NSSound?

    @ObservedObject private var appState = AppState.shared
    private let settings = Settings.shared

    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var liveTranscriptionTask: Task<Void, Never>?
    private var soundsObserver: NSObjectProtocol?
    private var activeAppBundleId: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupServices()
        setupSounds()
        setupSoundsObserver()
        setupMenuBar()

        if shouldShowOnboarding() {
            showOnboarding()
        } else {
            completeStartup()
        }

        print("[LocalFlow] App launched - double-tap \(settings.triggerKey.displayName) to record")
    }

    private func shouldShowOnboarding() -> Bool {
        let completed = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        if !completed { return true }

        // Also show if permissions were revoked (e.g., after update)
        let hasAccessibility = AXIsProcessTrusted()
        let hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let hasModel = settings.hasAnyModel()

        if !hasAccessibility || !hasMicrophone {
            // Permissions revoked - reset onboarding flag to show setup again
            UserDefaults.standard.set(false, forKey: "onboardingCompleted")
            return true
        }

        return !hasModel
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView { [weak self] in
            // Delay close to avoid constraint update race
            DispatchQueue.main.async {
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                self?.completeStartup()
            }
        }

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to LocalFlow"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window
    }

    private func completeStartup() {
        setupHotkey()
        checkAndLoadModel()
    }

    private func checkAndLoadModel() {
        if settings.hasAnyModel() {
            if let available = settings.firstAvailableModel(), !settings.isModelDownloaded(settings.selectedModel) {
                settings.selectedModel = available
            }
            loadModel()
        } else {
            downloadDefaultModel()
        }
    }

    private func downloadDefaultModel() {
        let defaultModel = WhisperModel.base
        print("[LocalFlow] No model found, downloading \(defaultModel.displayName)...")

        Task { @MainActor in
            AppState.shared.status = .downloading(progress: 0)
        }

        downloadCancellable = ModelDownloader.shared.$progress
            .receive(on: DispatchQueue.main)
            .sink { progress in
                if ModelDownloader.shared.isDownloading {
                    AppState.shared.status = .downloading(progress: progress)
                }
            }

        Task {
            let success = await ModelDownloader.shared.downloadModel(defaultModel)

            await MainActor.run {
                downloadCancellable?.cancel()

                if success {
                    settings.selectedModel = defaultModel
                    loadModel()
                } else {
                    AppState.shared.status = .error(.modelDownloadFailed)
                }
            }
        }
    }

    private func setupServices() {
        audioRecorder = AudioRecorder()
        whisperService = WhisperService()
        textInserter = TextInserter()
        hotkeyManager = HotkeyManager()

        audioRecorder.onLevelUpdate = { level in
            RecordingOverlayController.shared.updateAudioLevel(level)
        }
    }

    private func setupSounds() {
        // Try custom sounds first, fall back to bundled sounds
        if let customPath = settings.customStartSoundPath,
           FileManager.default.fileExists(atPath: customPath) {
            startSound = NSSound(contentsOfFile: customPath, byReference: true)
        } else if let startURL = Bundle.main.url(forResource: "start", withExtension: "wav") {
            startSound = NSSound(contentsOf: startURL, byReference: true)
        }

        if let customPath = settings.customStopSoundPath,
           FileManager.default.fileExists(atPath: customPath) {
            stopSound = NSSound(contentsOfFile: customPath, byReference: true)
        } else if let stopURL = Bundle.main.url(forResource: "stop", withExtension: "wav") {
            stopSound = NSSound(contentsOf: stopURL, byReference: true)
        }
    }

    func reloadSounds() {
        setupSounds()
    }

    private func setupSoundsObserver() {
        soundsObserver = NotificationCenter.default.addObserver(
            forName: .customSoundsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadSounds()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "LocalFlow")
        }

        let menu = NSMenu()

        // Status item
        let statusItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
        statusItem.tag = 1
        menu.addItem(statusItem)

        // Model info
        let modelItem = NSMenuItem(title: "Model: \(settings.selectedModel.shortName)", action: nil, keyEquivalent: "")
        modelItem.tag = 2
        menu.addItem(modelItem)

        // Stats
        let statsItem = NSMenuItem(title: "Words today: 0", action: nil, keyEquivalent: "")
        statsItem.tag = 3
        menu.addItem(statsItem)

        menu.addItem(NSMenuItem.separator())

        // Instructions
        let instructionItem = NSMenuItem(title: "Double-tap \(settings.triggerKey.displayName) to record", action: nil, keyEquivalent: "")
        instructionItem.isEnabled = false
        menu.addItem(instructionItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Check for updates
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit LocalFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        self.statusItem.menu = menu

        // Update status periodically
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateMenuStatus()
        }
    }

    private func updateMenuStatus() {
        guard let menu = statusItem.menu else { return }
        if let statusItem = menu.item(withTag: 1) {
            statusItem.title = appState.status.displayText
        }
        if let statsItem = menu.item(withTag: 3) {
            statsItem.title = "Words today: \(settings.wordsTranscribedToday)"
        }
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "LocalFlow Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    @objc private func checkForUpdates() {
        UpdateController.shared.checkForUpdates()
    }

    private func setupHotkey() {
        hotkeyManager.onDoubleTap = { [weak self] in
            print("[LocalFlow] Double-tap detected! Starting recording...")
            self?.startRecording()
        }

        hotkeyManager.onKeyUp = { [weak self] in
            print("[LocalFlow] Key released! Stopping recording...")
            self?.stopRecordingAndTranscribe()
        }

        hotkeyManager.onTripleTap = { [weak self] in
            self?.quickRepaste()
        }

        hotkeyManager.startMonitoring()
        print("[LocalFlow] Hotkey monitoring started")
    }

    private func quickRepaste() {
        let lastText = AppState.shared.lastTranscription
        guard !lastText.isEmpty else {
            print("[LocalFlow] Triple-tap: No previous transcription to re-paste")
            return
        }

        print("[LocalFlow] Triple-tap: Re-pasting last transcription")
        textInserter.insertText(lastText, clipboardOnly: settings.clipboardMode)
    }

    private func loadModel() {
        Task {
            await MainActor.run {
                AppState.shared.status = .loading
            }

            let modelPath = settings.modelPath
            print("[LocalFlow] Loading model from: \(modelPath)")
            let success = await whisperService.loadModel(path: modelPath)

            if success {
                await warmupModel()
            }

            await MainActor.run {
                if success {
                    print("[LocalFlow] Model loaded and ready")
                    AppState.shared.status = .idle
                } else {
                    print("[LocalFlow] Failed to load model")
                    AppState.shared.status = .error(.modelLoadFailed)
                }
            }
        }
    }

    private func warmupModel() async {
        // Run a quick transcription with minimal audio to prime the model
        // This makes the first real transcription faster
        let sampleRate = 16000
        let duration = 0.1 // 100ms of silence
        let sampleCount = Int(Double(sampleRate) * duration)
        let silentAudio = [Float](repeating: 0.0, count: sampleCount)

        print("[LocalFlow] Warming up model...")
        _ = await whisperService.transcribe(audioData: silentAudio, onSegment: nil)
        print("[LocalFlow] Model warmup complete")
    }

    private func startRecording() {
        guard AppState.shared.status == .idle else {
            print("[LocalFlow] Cannot start recording - status is \(AppState.shared.status)")
            return
        }

        // Capture the frontmost app for app-specific profiles
        activeAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let bundleId = activeAppBundleId {
            print("[LocalFlow] Recording for app: \(bundleId)")
        }

        if settings.soundFeedback {
            startSound?.play()
        }

        print("[LocalFlow] Recording started")
        AppState.shared.status = .recording
        updateMenuBarIcon(recording: true)
        RecordingOverlayController.shared.show()
        RecordingOverlayController.shared.updateStatus(.recording)
        audioRecorder.startRecording()
        startLiveTranscription()
    }

    private func startLiveTranscription() {
        liveTranscriptionTask?.cancel()
        liveTranscriptionTask = Task {
            // Wait a bit before first transcription to accumulate audio
            try? await Task.sleep(for: .seconds(1.5))

            while !Task.isCancelled && AppState.shared.status == .recording {
                if let samples = audioRecorder.getCurrentSamples(), samples.count > 16000 { // At least 1 second
                    // Run transcription in background
                    let result = await whisperService.transcribe(audioData: samples, onSegment: nil)
                    if case .success(let text) = result, !text.isEmpty {
                        await MainActor.run {
                            RecordingOverlayController.shared.updatePartialText(text)
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(1.0))
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        guard AppState.shared.status == .recording else {
            print("[LocalFlow] Cannot stop - not recording")
            return
        }

        // Stop live transcription
        liveTranscriptionTask?.cancel()
        liveTranscriptionTask = nil

        if settings.soundFeedback {
            stopSound?.play()
        }

        print("[LocalFlow] Stopping recording and transcribing...")
        AppState.shared.status = .transcribing
        updateMenuBarIcon(recording: false)
        RecordingOverlayController.shared.updateStatus(.transcribing)

        guard let audioData = audioRecorder.stopRecording() else {
            print("[LocalFlow] No audio data recorded")
            AppState.shared.status = .error(.noAudioRecorded)
            RecordingOverlayController.shared.hide()
            return
        }

        print("[LocalFlow] Got \(audioData.count) audio samples, transcribing...")

        Task {
            // Reload model if it was unloaded due to idle timeout
            if await !whisperService.modelLoaded {
                print("[LocalFlow] Reloading model...")
                await MainActor.run {
                    AppState.shared.status = .loading
                }
                let loaded = await whisperService.loadModel(path: settings.modelPath)
                if !loaded {
                    await MainActor.run {
                        RecordingOverlayController.shared.hide()
                        AppState.shared.status = .error(.modelLoadFailed)
                    }
                    return
                }
            }

            await MainActor.run {
                AppState.shared.status = .transcribing
            }

            let result = await whisperService.transcribe(audioData: audioData, onSegment: nil)

            await MainActor.run {
                RecordingOverlayController.shared.hide()

                switch result {
                case .success(var text):
                    print("[LocalFlow] Transcription: \(text)")
                    if !text.isEmpty {
                        let effective = self.effectiveSettings()

                        if effective.punctuation {
                            text = self.addPunctuation(text)
                        }

                        if effective.summary {
                            text = self.formatAsSummary(text)
                        }

                        // Track stats
                        let wordCount = text.split(separator: " ").count
                        self.settings.addWordsToStats(wordCount)

                        AppState.shared.lastTranscription = text
                        self.settings.addToHistory(text)
                        self.textInserter.insertText(text, clipboardOnly: effective.clipboard)
                    }
                    AppState.shared.status = .idle
                    self.activeAppBundleId = nil
                case .failure(let error):
                    print("[LocalFlow] Transcription error: \(error)")
                    AppState.shared.status = .error(.transcriptionFailed)
                }
            }
        }
    }

    private func effectiveSettings() -> (punctuation: Bool, clipboard: Bool, summary: Bool) {
        if let bundleId = activeAppBundleId,
           let profile = settings.profileForApp(bundleId) {
            return (profile.punctuationMode, profile.clipboardMode, profile.summaryMode)
        }
        return (settings.punctuationMode, settings.clipboardMode, settings.summaryModeEnabled)
    }

    private func addPunctuation(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.isEmpty { return result }

        let firstChar = result.removeFirst()
        result = String(firstChar).uppercased() + result

        let lastChar = result.last ?? Character(" ")
        if !".!?".contains(lastChar) {
            result += "."
        }

        return result
    }

    private func formatAsSummary(_ text: String) -> String {
        let sentences = text
            .replacingOccurrences(of: "? ", with: "?|")
            .replacingOccurrences(of: ". ", with: ".|")
            .replacingOccurrences(of: "! ", with: "!|")
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if sentences.count <= 1 {
            return text
        }

        return sentences.map { "• \($0)" }.joined(separator: "\n")
    }

    private func updateMenuBarIcon(recording: Bool) {
        DispatchQueue.main.async { [weak self] in
            let imageName = recording ? "waveform.circle.fill" : "waveform"
            self?.statusItem.button?.image = NSImage(
                systemSymbolName: imageName,
                accessibilityDescription: "LocalFlow"
            )
        }
    }
}
