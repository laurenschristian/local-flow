import Cocoa
import SwiftUI
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hotkeyManager: HotkeyManager!
    private var audioRecorder: AudioRecorder!
    private var whisperService: WhisperService!
    private var textInserter: TextInserter!

    private var startSound: NSSound?
    private var stopSound: NSSound?

    @ObservedObject private var appState = AppState.shared
    private let settings = Settings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupServices()
        setupSounds()
        setupMenuBar()
        setupHotkey()
        loadModel()

        print("[LocalFlow] App launched - double-tap \(settings.triggerKey.displayName) to record")
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
        startSound = NSSound(named: "Tink")
        stopSound = NSSound(named: "Pop")
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
                    AppState.shared.status = .error("Failed to load model")
                }
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
            AppState.shared.status = .error("No audio recorded")
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
                    AppState.shared.status = .error(error.localizedDescription)
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
