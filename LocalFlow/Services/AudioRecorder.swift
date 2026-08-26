import AVFoundation
import CoreAudio
import Foundation

class AudioRecorder {
    private var audioEngine: AVAudioEngine?

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

    // collectSamples=false: level metering only (settings meter); samples are
    // discarded so a long-open meter doesn't grow memory unbounded.
    // Returns false when the engine could not start; callers must not enter a
    // recording state in that case.
    @discardableResult
    func startRecording(collectSamples: Bool = true) -> Bool {
        os_unfair_lock_lock(&samplesLock)
        recordedSamples.removeAll()
        recordedSamples.reserveCapacity(16000 * 30) // Pre-allocate for ~30 seconds
        os_unfair_lock_unlock(&samplesLock)
        currentLevel = 0.0

        // Fresh engine every start: a reused engine keeps stale AUHAL state after
        // the input device changes, and its cached formats go out of sync.
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return false }

        let inputNode = audioEngine.inputNode

        if let deviceID = AudioDeviceManager.recordingDeviceID(),
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
            return false
        }

        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            print("Failed to create audio format")
            return false
        }

        // Create converter once, reuse for all buffers
        guard let converter = AVAudioConverter(from: inputFormat, to: whisperFormat) else {
            print("Failed to create converter \(inputFormat) -> \(whisperFormat), not recording")
            return false
        }

        // Defensive: AVAudioEngine raises an NSException (→ SIGABRT, uncatchable in Swift)
        // if a tap is already installed on this bus. Can happen after a stop that didn't
        // fully tear down, or if the input device changed mid-session.
        inputNode.removeTap(onBus: 0)

        // The converter is captured by the tap closure, not stored on self: the tap
        // runs on a CoreAudio thread and must never race a property write from stop.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: collectSamples ? converter : nil)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
            inputNode.removeTap(onBus: 0)
            return false
        }
        return true
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

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?) {
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

        guard let converter else { return }
        let outputFormat = converter.outputFormat

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
        currentLevel = 0.0

        os_unfair_lock_lock(&samplesLock)
        defer { os_unfair_lock_unlock(&samplesLock) }
        guard !recordedSamples.isEmpty else { return nil }
        let samples = recordedSamples
        recordedSamples.removeAll(keepingCapacity: false) // Release memory
        return samples
    }
}
