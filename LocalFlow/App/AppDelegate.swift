import Cocoa
import SwiftUI
import AVFoundation
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelPopover: NSPopover?
    private var modelChangeCancellable: AnyCancellable?
    private var loadedModelPath: String?
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
        MediaPauseController.shared.resumeAfterRecordingNow()

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

        // Reload when the model changes from any UI, so the switch takes
        // effect immediately instead of after the next idle unload.
        modelChangeCancellable = settings.$selectedModel
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.settings.modelPath != self.loadedModelPath else { return }
                    guard self.settings.isModelDownloaded(self.settings.selectedModel) else { return }
                    self.loadModel()
                }
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
            button.action = #selector(togglePanel)
            button.target = self
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: MenuBarPanelView(
            onPaste: { [weak self] text in
                self?.panelPopover?.performClose(nil)
                // Give focus a beat to return to the previous app before pasting.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.textInserter.insertText(text, clipboardOnly: Settings.shared.clipboardMode)
                }
            },
            onOpenSettings: { [weak self] in
                self?.panelPopover?.performClose(nil)
                self?.openSettings()
            },
            onCheckUpdates: { [weak self] in
                self?.panelPopover?.performClose(nil)
                UpdateController.shared.checkForUpdates()
            },
            onQuit: { NSApp.terminate(nil) }
        ))
        panelPopover = popover
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button, let popover = panelPopover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
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
        MediaPauseController.shared.resumeAfterRecording()
        updateMenuBarIcon(recording: false)
        RecordingOverlayController.shared.hide()
        AppState.shared.status = .idle
        activeAppBundleId = nil
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
        loadedModelPath = settings.modelPath
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
            // The hotkey manager already entered its holding state; drop it so
            // the following release doesn't act on a recording that never started.
            hotkeyManager.resetHoldState()
            return
        }

        // Capture the frontmost app for app-specific profiles
        activeAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let bundleId = activeAppBundleId {
            print("[LocalFlow] Recording for app: \(bundleId)")
        }

        if settings.pauseMediaWhileRecording {
            MediaPauseController.shared.pauseForRecording()
        }

        if settings.soundFeedback {
            startSound?.play()
        }

        // The engine can fail to start (device vanished mid-tap, invalid format,
        // converter failure). Never enter .recording in that case: the old code
        // showed a live overlay over a dead mic and the user lost the dictation.
        guard audioRecorder.startRecording() else {
            print("[LocalFlow] Audio engine failed to start")
            if settings.pauseMediaWhileRecording {
                MediaPauseController.shared.resumeAfterRecording()
            }
            hotkeyManager.resetHoldState()
            activeAppBundleId = nil
            failWithError(.recordingFailed)
            return
        }

        print("[LocalFlow] Recording started")
        AppState.shared.status = .recording
        updateMenuBarIcon(recording: true)
        RecordingOverlayController.shared.show()
        RecordingOverlayController.shared.updateStatus(.recording)
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

            while !Task.isCancelled {
                let isRecording = await MainActor.run { AppState.shared.status == .recording }
                guard isRecording else { break }
                if let samples = audioRecorder.getCurrentSamples(tailSeconds: livePreviewWindowSeconds),
                   samples.count > 16000 {
                    let result = await whisperService.transcribe(audioData: samples, onSegment: nil)
                    // Re-check after the (slow) transcribe: without this, a stop or
                    // new recording mid-flight got stale preview text painted over it.
                    if case .success(let text) = result, !text.isEmpty, !Task.isCancelled {
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
        MediaPauseController.shared.resumeAfterRecording()
        RecordingOverlayController.shared.updateStatus(.transcribing)

        guard let rawAudio = audioRecorder.stopRecording() else {
            print("[LocalFlow] No audio data recorded")
            failWithError(.noAudioRecorded)
            RecordingOverlayController.shared.hide()
            return
        }

        let audioData = settings.trimSilenceEnabled ? SilenceTrimmer.trim(rawAudio) : rawAudio
        if audioData.count < rawAudio.count {
            let saved = Double(rawAudio.count - audioData.count) / 16000.0
            print("[LocalFlow] Silence trim removed \(String(format: "%.1f", saved))s of audio")
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
                if HallucinationFilter.isLikelyHallucination(text: text, audio: audioData) {
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
                        text = TranscriptionFormatter.punctuate(text)
                    }
                    if effective.summary {
                        text = TranscriptionFormatter.bulletSummary(text)
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
