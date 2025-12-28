import AVFoundation
import Foundation

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var recordedSamples: [Float] = []

    // Audio level for visualization (0.0 to 1.0)
    var currentLevel: Float = 0.0
    var onLevelUpdate: ((Float) -> Void)?

    private let sampleRate: Double = 16000 // Whisper expects 16kHz
    private let channelCount: AVAudioChannelCount = 1 // Mono

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
        currentLevel = 0.0

        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create format for Whisper: 16kHz mono float32
        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            print("Failed to create audio format")
            return
        }

        // Install tap to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, from: inputFormat, to: whisperFormat)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        from inputFormat: AVAudioFormat,
        to outputFormat: AVAudioFormat
    ) {
        // Calculate audio level from input buffer
        if let channelData = buffer.floatChannelData?[0] {
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frames))
            let level = min(1.0, rms * 5) // Scale up for visibility

            DispatchQueue.main.async { [weak self] in
                self?.currentLevel = level
                self?.onLevelUpdate?(level)
            }
        }

        // Convert to Whisper format if needed
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return
        }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else {
            return
        }

        // Append samples
        if let channelData = convertedBuffer.floatChannelData?[0] {
            let samples = Array(UnsafeBufferPointer(
                start: channelData,
                count: Int(convertedBuffer.frameLength)
            ))
            recordedSamples.append(contentsOf: samples)
        }
    }

    func stopRecording() -> [Float]? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        currentLevel = 0.0

        guard !recordedSamples.isEmpty else {
            return nil
        }

        let samples = recordedSamples
        recordedSamples.removeAll()
        return samples
    }
}
