import Cocoa
import SwiftUI
import AVFoundation
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up whisper context synchronously before C++ statics are destroyed
        // This prevents the ggml_metal_rsets_free assertion failure
        hotkeyManager?.stopMonitoring()
        liveTranscriptionTask?.cancel()

        // Synchronously unload the model to free Metal resources properly
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await whisperService?.unloadModel()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
    }

    private func shouldShowOnboarding() -> Bool {
        let completed = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        if !completed { return true }

        // Check if critical permissions are missing (e.g., after update)
        let hasAccessibility = AXIsProcessTrusted()
        let hasModel = settings.hasAnyModel()

        // Only re-show onboarding if accessibility is missing (required for hotkey)
        // Don't reset the flag - just show the flow to fix the missing permission
        if !hasAccessibility || !hasModel {
            return true
        }

        return false
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
        window.isReleasedWhenClosed = false

        // Set size first, then center
        window.setContentSize(NSSize(width: 520, height: 440))
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

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

        // Microphone picker (populated lazily on open)
        let micItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        micItem.tag = 4
        micItem.submenu = buildMicrophoneSubmenu()
        menu.addItem(micItem)

        menu.addItem(NSMenuItem.separator())

        // Instructions
        let instructionItem = NSMenuItem(title: "Double-tap \(settings.triggerKey.displayName) to record", action: nil, keyEquivalent: "")
        instructionItem.isEnabled = false
        instructionItem.tag = 5
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

        menu.delegate = self
        self.statusItem.menu = menu

        // Update status periodically
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateMenuStatus()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Refresh the mic submenu so newly-connected devices (e.g. AirPods) appear.
        if let micItem = menu.item(withTag: 4) {
            micItem.submenu = buildMicrophoneSubmenu()
        }
        if let modelItem = menu.item(withTag: 2) {
            modelItem.title = "Model: \(settings.selectedModel.shortName)"
        }
        if let instructionItem = menu.item(withTag: 5) {
            instructionItem.title = "Double-tap \(settings.triggerKey.displayName) to record"
        }
    }

    private func buildMicrophoneSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let currentUID = settings.selectedInputDeviceUID

        let systemItem = NSMenuItem(
            title: "System Default",
            action: #selector(selectMicrophone(_:)),
            keyEquivalent: ""
        )
        systemItem.target = self
        systemItem.representedObject = NSNull()
        systemItem.state = (currentUID == nil) ? NSControl.StateValue.on : .off
        submenu.addItem(systemItem)

        let devices = AudioDeviceManager.inputDevices()
        if !devices.isEmpty {
            submenu.addItem(NSMenuItem.separator())
            for device in devices {
                let item = NSMenuItem(
                    title: device.name,
                    action: #selector(selectMicrophone(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device.uid
                item.state = (currentUID == device.uid) ? NSControl.StateValue.on : .off
                submenu.addItem(item)
            }
        }

        return submenu
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        if sender.representedObject is NSNull {
            settings.selectedInputDeviceUID = nil
        } else if let uid = sender.representedObject as? String {
            settings.selectedInputDeviceUID = uid
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
        // We keep a strong reference and reopen this window; the default
        // release-on-close would make the second open a use-after-free.
        window.isReleasedWhenClosed = false
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
            self?.cancelRecordingIfNeeded()
            self?.quickRepaste()
        }

        hotkeyManager.startMonitoring()
        print("[LocalFlow] Hotkey monitoring started")
    }

    /// A triple-tap arrives right after its own double-tap started a recording;
    /// discard that accidental recording without transcribing it.
    private func cancelRecordingIfNeeded() {
        guard AppState.shared.status == .recording else { return }
        liveTranscriptionTask?.cancel()
        liveTranscriptionTask = nil
        _ = audioRecorder.stopRecording()
        updateMenuBarIcon(recording: false)
        RecordingOverlayController.shared.hide()
        AppState.shared.status = .idle
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
        // An error state must not brick the hotkey: recover to idle and record.
        if case .error = AppState.shared.status {
            AppState.shared.status = .idle
        }
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
            try? await Task.sleep(for: .seconds(1.5))

            // Live preview transcribes a rolling tail (not the full buffer) so
            // CPU stays bounded regardless of recording length. The final
            // transcription on stop still uses the complete audio.
            let livePreviewWindowSeconds = 8.0

            while !Task.isCancelled && AppState.shared.status == .recording {
                if let samples = audioRecorder.getCurrentSamples(tailSeconds: livePreviewWindowSeconds),
                   samples.count > 16000 {
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
            failWithError(.noAudioRecorded)
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
                        self.failWithError(.modelLoadFailed)
                    }
                    return
                }
            }

            await MainActor.run {
                AppState.shared.status = .transcribing
            }

            let result = await whisperService.transcribe(audioData: audioData, onSegment: nil)

            switch result {
            case .success(var text):
                print("[LocalFlow] Transcription: \(text)")
                if self.isLikelyHallucination(text: text, audio: audioData) {
                    print("[LocalFlow] Dropped likely silence-hallucination: \(text)")
                    text = ""
                }

                let (effective, commandsOn, cleanupOn) = await MainActor.run {
                    (self.effectiveSettings(), self.settings.spokenCommandsEnabled, self.settings.cleanupModeEnabled)
                }

                if !text.isEmpty {
                    if commandsOn {
                        text = SpokenCommands.apply(to: text)
                    }
                    // Cleanup can take a moment; the overlay stays in
                    // "Processing" until the final text is ready.
                    if cleanupOn && !text.isEmpty {
                        text = await CleanupService.cleanup(text)
                    }
                    if effective.punctuation {
                        text = self.addPunctuation(text)
                    }
                    if effective.summary {
                        text = self.formatAsSummary(text)
                    }
                }

                await MainActor.run {
                    RecordingOverlayController.shared.hide()
                    if !text.isEmpty {
                        let wordCount = text.split(separator: " ").count
                        self.settings.addWordsToStats(wordCount)

                        AppState.shared.lastTranscription = text
                        self.settings.addToHistory(text)
                        self.textInserter.insertText(text, clipboardOnly: effective.clipboard)
                    }
                    AppState.shared.status = .idle
                    self.activeAppBundleId = nil
                }
            case .failure(let error):
                print("[LocalFlow] Transcription error: \(error)")
                await MainActor.run {
                    RecordingOverlayController.shared.hide()
                    self.failWithError(.transcriptionFailed)
                }
            }
        }
    }

    /// Show an error briefly, then recover to idle so the hotkey keeps working.
    private func failWithError(_ error: AppError) {
        AppState.shared.status = .error(error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if case .error = AppState.shared.status {
                AppState.shared.status = .idle
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

    // Whisper memorized end-of-video phrases from YouTube subtitles in its
    // training data and emits them as confident transcripts when the audio is
    // silent. We drop these when the audio energy is below a speech threshold.
    private static let hallucinationPhrases: Set<String> = [
        "thank you", "thank you.", "thanks for watching", "thanks for watching.",
        "thanks for watching!", "thank you for watching", "thank you for watching.",
        "thank you for watching!", "thanks", "thanks.", "thank you!",
        "you", "you.", ".", "...", "bye", "bye.", "goodbye", "goodbye.",
        "subtitles by the amara.org community",
        "please subscribe", "like and subscribe",
    ]

    private func isLikelyHallucination(text: String, audio: [Float]) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        guard Self.hallucinationPhrases.contains(normalized) else { return false }

        // Match a known hallucination phrase. Confirm by checking audio energy:
        // if the recording was effectively silent, this is definitely a hallucination.
        guard !audio.isEmpty else { return true }
        var sumSquares: Float = 0
        for sample in audio { sumSquares += sample * sample }
        let rms = sqrt(sumSquares / Float(audio.count))
        // Empirical: real speech RMS is typically > 0.01; ambient noise sits well below.
        return rms < 0.005
    }
}
