import AVFoundation
import Foundation

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: AVAudioPCMBuffer?
    private var recordedSamples: [Float] = []

    private let sampleRate: Double = 16000 // Whisper expects 16kHz
    private let channelCount: AVAudioChannelCount = 1 // Mono

    init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
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
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
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
            print("Conversion error: \(error?.localizedDescription ?? "unknown")")
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

        guard !recordedSamples.isEmpty else {
            return nil
        }

        let samples = recordedSamples
        recordedSamples.removeAll()
        return samples
    }
}
