import AVFoundation
import CoreAudio
import Foundation

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var recordedSamples: [Float] = []

    var currentLevel: Float = 0.0
    var onLevelUpdate: ((Float) -> Void)?

    private let sampleRate: Double = 16000 // Whisper expects 16kHz
    private let channelCount: AVAudioChannelCount = 1

    init() {
        audioEngine = AVAudioEngine()
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func startRecording() {
        recordedSamples.removeAll()
        recordedSamples.reserveCapacity(16000 * 30) // Pre-allocate for ~30 seconds
        currentLevel = 0.0

        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode

        // Apply user-chosen input device to the AUHAL before reading the format,
        // since outputFormat(forBus:) reflects whichever device the unit is bound to.
        if let uid = Settings.shared.selectedInputDeviceUID,
           let deviceID = AudioDeviceManager.deviceID(forUID: uid),
           let audioUnit = inputNode.audioUnit {
            var id = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                print("Failed to set input device (\(status)), falling back to system default")
            }
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            print("Failed to create audio format")
            return
        }

        // Create converter once, reuse for all buffers
        audioConverter = AVAudioConverter(from: inputFormat, to: whisperFormat)

        // Defensive: AVAudioEngine raises an NSException (→ SIGABRT, uncatchable in Swift)
        // if a tap is already installed on this bus. Can happen after a stop that didn't
        // fully tear down, or if the input device changed mid-session.
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Calculate audio level using Accelerate framework would be faster,
        // but this is simple and runs on audio thread
        if let channelData = buffer.floatChannelData?[0] {
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in stride(from: 0, to: frames, by: 4) { // Sample every 4th frame
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frames / 4))
            let level = min(1.0, rms * 5)

            DispatchQueue.main.async { [weak self] in
                self?.currentLevel = level
                self?.onLevelUpdate?(level)
            }
        }

        guard let converter = audioConverter,
              let outputFormat = converter.outputFormat as AVAudioFormat? else { return }

        let ratio = outputFormat.sampleRate / converter.inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1)

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else { return }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil,
              let channelData = convertedBuffer.floatChannelData?[0] else { return }

        let frameCount = Int(convertedBuffer.frameLength)
        recordedSamples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frameCount))
    }

    /// Get current samples without stopping (for live transcription)
    func getCurrentSamples() -> [Float]? {
        guard !recordedSamples.isEmpty else { return nil }
        return recordedSamples
    }

    func stopRecording() -> [Float]? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioConverter = nil
        currentLevel = 0.0

        guard !recordedSamples.isEmpty else {
            return nil
        }

        let samples = recordedSamples
        recordedSamples.removeAll(keepingCapacity: false) // Release memory
        return samples
    }
}
