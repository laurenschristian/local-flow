import Cocoa
import SwiftUI
import AVFoundation
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupServices()
        setupSounds()
        setupMenuBar()

        if shouldShowOnboarding() {
            showOnboarding()
        } else {
            completeStartup()
        }

        print("[LocalFlow] App launched - double-tap \(settings.triggerKey.displayName) to record")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up whisper context before exit to prevent Metal crash
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await whisperService.unloadModel()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
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
        if let startURL = Bundle.main.url(forResource: "start", withExtension: "wav") {
            startSound = NSSound(contentsOf: startURL, byReference: true)
        }
        if let stopURL = Bundle.main.url(forResource: "stop", withExtension: "wav") {
            stopSound = NSSound(contentsOf: stopURL, byReference: true)
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "LocalFlow")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
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

        hotkeyManager.startMonitoring()
        print("[LocalFlow] Hotkey monitoring started")
    }

    private func loadModel() {
        Task {
            await MainActor.run {
                AppState.shared.status = .loading
            }

            let modelPath = settings.modelPath
            print("[LocalFlow] Loading model from: \(modelPath)")
            let success = await whisperService.loadModel(path: modelPath)

            await MainActor.run {
                if success {
                    print("[LocalFlow] Model loaded successfully")
                    AppState.shared.status = .idle
                } else {
                    print("[LocalFlow] Failed to load model")
                    AppState.shared.status = .error(.modelLoadFailed)
                }
            }
        }
    }

    @objc private func togglePopover() {
        guard statusItem.button != nil else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Ensure we're not in middle of a layout pass
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let button = self.statusItem.button else { return }
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    private func startRecording() {
        guard AppState.shared.status == .idle else {
            print("[LocalFlow] Cannot start recording - status is \(AppState.shared.status)")
            return
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
    }

    private func stopRecordingAndTranscribe() {
        guard AppState.shared.status == .recording else {
            print("[LocalFlow] Cannot stop - not recording")
            return
        }

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
            let result = await whisperService.transcribe(audioData: audioData)

            await MainActor.run {
                RecordingOverlayController.shared.hide()

                switch result {
                case .success(var text):
                    print("[LocalFlow] Transcription: \(text)")
                    if !text.isEmpty {
                        if settings.punctuationMode {
                            text = addPunctuation(text)
                        }

                        AppState.shared.lastTranscription = text
                        settings.addToHistory(text)
                        textInserter.insertText(text, clipboardOnly: settings.clipboardMode)
                    }
                    AppState.shared.status = .idle
                case .failure(let error):
                    print("[LocalFlow] Transcription error: \(error)")
                    AppState.shared.status = .error(.transcriptionFailed)
                }
            }
        }
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
