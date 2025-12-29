import Foundation

enum WhisperError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case invalidAudioData

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model not loaded"
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .invalidAudioData:
            return "Invalid audio data"
        }
    }
}

actor WhisperService {
    private var context: OpaquePointer?
    private var isModelLoaded: Bool = false
    private var lastUsedTime: Date = Date()
    private var idleUnloadTask: Task<Void, Never>?

    private static let idleTimeout: TimeInterval = 300 // 5 minutes

    var modelLoaded: Bool { isModelLoaded }

    func loadModel(path: String) async -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            print("Model file not found at: \(path)")
            return false
        }

        // Initialize whisper context with default parameters
        var params = whisper_context_default_params()

        // Use Metal acceleration on Apple Silicon
        #if arch(arm64)
        params.use_gpu = true
        #endif

        guard let ctx = whisper_init_from_file_with_params(path, params) else {
            print("Failed to initialize whisper context")
            return false
        }

        // Clean up previous context if any
        if let oldContext = context {
            whisper_free(oldContext)
        }

        context = ctx
        isModelLoaded = true
        lastUsedTime = Date()
        startIdleTimer()
        print("Model loaded successfully")
        return true
    }

    private func startIdleTimer() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self = self else { return }
                let shouldUnload = await self.checkIdleTimeout()
                if shouldUnload {
                    await self.unloadModel()
                    return
                }
            }
        }
    }

    private func checkIdleTimeout() -> Bool {
        let elapsed = Date().timeIntervalSince(lastUsedTime)
        if elapsed > Self.idleTimeout && isModelLoaded {
            print("[WhisperService] Unloading model after \(Int(elapsed))s idle")
            return true
        }
        return false
    }

    func transcribe(audioData: [Float]) async -> Result<String, WhisperError> {
        await transcribe(audioData: audioData, onSegment: nil)
    }

    func transcribe(audioData: [Float], onSegment: ((String) -> Void)?) async -> Result<String, WhisperError> {
        guard isModelLoaded, let ctx = context else {
            return .failure(.modelNotLoaded)
        }

        guard !audioData.isEmpty else {
            return .failure(.invalidAudioData)
        }

        lastUsedTime = Date()

        // Set up transcription parameters
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.n_threads = Int32(min(8, ProcessInfo.processInfo.activeProcessorCount))
        params.suppress_blank = true
        params.suppress_nst = true

        // Run transcription with English language
        let result = "en".withCString { langPtr in
            params.language = langPtr
            return audioData.withUnsafeBufferPointer { buffer in
                whisper_full(ctx, params, buffer.baseAddress, Int32(audioData.count))
            }
        }

        guard result == 0 else {
            return .failure(.transcriptionFailed("whisper_full returned \(result)"))
        }

        // Extract transcription with streaming callbacks
        let segmentCount = whisper_full_n_segments(ctx)
        var transcription = ""

        for i in 0..<segmentCount {
            if let text = whisper_full_get_segment_text(ctx, i) {
                let segment = String(cString: text)
                transcription += segment
                // Call the segment callback on main thread
                if let callback = onSegment {
                    let currentText = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
                    DispatchQueue.main.async {
                        callback(currentText)
                    }
                }
            }
        }

        return .success(transcription.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func unloadModel() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        if let ctx = context {
            whisper_free(ctx)
            context = nil
        }
        isModelLoaded = false
        print("[WhisperService] Model unloaded")
    }

    deinit {
        if let ctx = context {
            whisper_free(ctx)
        }
    }
}
