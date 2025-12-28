import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hotkeyManager: HotkeyManager!
    private var audioRecorder: AudioRecorder!
    private var whisperService: WhisperService!
    private var textInserter: TextInserter!

    @ObservedObject private var appState = AppState.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupServices()
        setupMenuBar()
        setupHotkey()
        loadModel()
    }

    private func setupServices() {
        audioRecorder = AudioRecorder()
        whisperService = WhisperService()
        textInserter = TextInserter()
        hotkeyManager = HotkeyManager()
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
            self?.startRecording()
        }

        hotkeyManager.onKeyUp = { [weak self] in
            self?.stopRecordingAndTranscribe()
        }

        hotkeyManager.startMonitoring()
    }

    private func loadModel() {
        Task {
            await MainActor.run {
                AppState.shared.status = .loading
            }

            let modelPath = Settings.shared.modelPath
            let success = await whisperService.loadModel(path: modelPath)

            await MainActor.run {
                AppState.shared.status = success ? .idle : .error("Failed to load model")
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
        guard AppState.shared.status == .idle else { return }

        AppState.shared.status = .recording
        updateMenuBarIcon(recording: true)
        audioRecorder.startRecording()
    }

    private func stopRecordingAndTranscribe() {
        guard AppState.shared.status == .recording else { return }

        AppState.shared.status = .transcribing
        updateMenuBarIcon(recording: false)

        guard let audioData = audioRecorder.stopRecording() else {
            AppState.shared.status = .error("No audio recorded")
            return
        }

        Task {
            let result = await whisperService.transcribe(audioData: audioData)

            await MainActor.run {
                switch result {
                case .success(let text):
                    if !text.isEmpty {
                        textInserter.insertText(text)
                    }
                    AppState.shared.status = .idle
                case .failure(let error):
                    AppState.shared.status = .error(error.localizedDescription)
                }
            }
        }
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
