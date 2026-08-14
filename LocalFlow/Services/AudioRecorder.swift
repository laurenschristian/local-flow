import AVFoundation
import CoreAudio
import Foundation

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?

    // The audio tap callback writes to recordedSamples on a private CoreAudio
    // thread, while getCurrentSamples()/stopRecording() read it from other
    // queues. Swift Array is not thread-safe, so all access goes through this
    // lock. os_unfair_lock is the lowest-overhead primitive available; the
    // critical sections are tiny (one Array op each).
    private var recordedSamples: [Float] = []
    private var samplesLock = os_unfair_lock_s()

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

    // false = level metering only (settings meter); samples are discarded so a
    // long-open meter doesn't grow memory unbounded.
    private var collectSamples = true

    func startRecording(collectSamples: Bool = true) {
        self.collectSamples = collectSamples
        os_unfair_lock_lock(&samplesLock)
        recordedSamples.removeAll()
        recordedSamples.reserveCapacity(16000 * 30) // Pre-allocate for ~30 seconds
        os_unfair_lock_unlock(&samplesLock)
        currentLevel = 0.0

        // Fresh engine every start: a reused engine keeps stale AUHAL state after
        // the input device changes, and its cached formats go out of sync.
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode

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

        // outputFormat(forBus:) can report the PREVIOUS device's format after the
        // AUHAL device swap above (observed: 44.1kHz stale vs 16kHz real -> tap
        // delivers zero samples). Ask the AU for the actual hardware format instead.
        let inputFormat = Self.hardwareInputFormat(of: inputNode) ?? inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            print("Input device reports invalid format, not recording")
            return
        }

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
        if audioConverter == nil {
            print("Failed to create converter \(inputFormat) -> \(whisperFormat), not recording")
            return
        }

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

    /// The device's true input format, read from the AUHAL (input scope, bus 1).
    /// Unlike outputFormat(forBus:), this stays correct after a device swap.
    private static func hardwareInputFormat(of node: AVAudioInputNode) -> AVAudioFormat? {
        guard let audioUnit = node.audioUnit else { return nil }
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioUnitGetProperty(
            audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &asbd, &size
        )
        guard status == noErr, asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else { return nil }
        return AVAudioFormat(
            standardFormatWithSampleRate: asbd.mSampleRate,
            channels: AVAudioChannelCount(asbd.mChannelsPerFrame)
        )
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Calculate audio level using Accelerate framework would be faster,
        // but this is simple and runs on audio thread
        if let channelData = buffer.floatChannelData?[0], buffer.frameLength >= 4 {
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

        guard collectSamples,
              let converter = audioConverter,
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
        os_unfair_lock_lock(&samplesLock)
        recordedSamples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frameCount))
        os_unfair_lock_unlock(&samplesLock)
    }

    /// Snapshot of current samples for live transcription. Returns the tail
    /// only when `tailSeconds` is provided so we don't re-transcribe the
    /// entire buffer every tick (was O(N) per tick → quadratic CPU).
    func getCurrentSamples(tailSeconds: Double? = nil) -> [Float]? {
        os_unfair_lock_lock(&samplesLock)
        defer { os_unfair_lock_unlock(&samplesLock) }
        guard !recordedSamples.isEmpty else { return nil }
        if let tail = tailSeconds {
            let tailFrames = Int(tail * sampleRate)
            if recordedSamples.count > tailFrames {
                return Array(recordedSamples.suffix(tailFrames))
            }
        }
        return recordedSamples
    }

    func stopRecording() -> [Float]? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioConverter = nil
        currentLevel = 0.0

        os_unfair_lock_lock(&samplesLock)
        defer { os_unfair_lock_unlock(&samplesLock) }
        guard !recordedSamples.isEmpty else { return nil }
        let samples = recordedSamples
        recordedSamples.removeAll(keepingCapacity: false) // Release memory
        return samples
    }
}
