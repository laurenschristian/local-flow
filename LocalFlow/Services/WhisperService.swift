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
        print("Model loaded successfully")
        return true
    }

    func transcribe(audioData: [Float]) async -> Result<String, WhisperError> {
        guard isModelLoaded, let ctx = context else {
            return .failure(.modelNotLoaded)
        }

        guard !audioData.isEmpty else {
            return .failure(.invalidAudioData)
        }

        // Set up transcription parameters
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.language = "en".withCString { strdup($0) }
        params.n_threads = Int32(ProcessInfo.processInfo.activeProcessorCount)
        params.suppress_blank = true
        params.suppress_non_speech_tokens = true

        // Run transcription
        let result = audioData.withUnsafeBufferPointer { buffer in
            whisper_full(ctx, params, buffer.baseAddress, Int32(audioData.count))
        }

        // Free the duplicated language string
        if let lang = params.language {
            free(UnsafeMutablePointer(mutating: lang))
        }

        guard result == 0 else {
            return .failure(.transcriptionFailed("whisper_full returned \(result)"))
        }

        // Extract transcription
        let segmentCount = whisper_full_n_segments(ctx)
        var transcription = ""

        for i in 0..<segmentCount {
            if let text = whisper_full_get_segment_text(ctx, i) {
                transcription += String(cString: text)
            }
        }

        return .success(transcription.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func unloadModel() {
        if let ctx = context {
            whisper_free(ctx)
            context = nil
        }
        isModelLoaded = false
    }

    deinit {
        if let ctx = context {
            whisper_free(ctx)
        }
    }
}

// MARK: - whisper.cpp C Interface
// These declarations match the whisper.cpp C API
// The actual implementation comes from linking against libwhisper

typealias whisper_context = OpaquePointer

struct whisper_context_params {
    var use_gpu: Bool
    var flash_attn: Bool
    var gpu_device: Int32
    var dtw_token_timestamps: Bool
    var dtw_aheads_preset: Int32
    var dtw_n_top: Int32
    var dtw_aheads: OpaquePointer?
    var dtw_mem_size: Int

    init() {
        use_gpu = true
        flash_attn = false
        gpu_device = 0
        dtw_token_timestamps = false
        dtw_aheads_preset = 0
        dtw_n_top = 0
        dtw_aheads = nil
        dtw_mem_size = 0
    }
}

struct whisper_full_params {
    var strategy: Int32
    var n_threads: Int32
    var n_max_text_ctx: Int32
    var offset_ms: Int32
    var duration_ms: Int32
    var translate: Bool
    var no_context: Bool
    var no_timestamps: Bool
    var single_segment: Bool
    var print_special: Bool
    var print_progress: Bool
    var print_realtime: Bool
    var print_timestamps: Bool
    var token_timestamps: Bool
    var thold_pt: Float
    var thold_ptsum: Float
    var max_len: Int32
    var split_on_word: Bool
    var max_tokens: Int32
    var debug_mode: Bool
    var audio_ctx: Int32
    var tdrz_enable: Bool
    var suppress_regex: UnsafePointer<CChar>?
    var initial_prompt: UnsafePointer<CChar>?
    var prompt_tokens: UnsafePointer<Int32>?
    var prompt_n_tokens: Int32
    var language: UnsafePointer<CChar>?
    var detect_language: Bool
    var suppress_blank: Bool
    var suppress_non_speech_tokens: Bool
    var temperature: Float
    var max_initial_ts: Float
    var length_penalty: Float
    var temperature_inc: Float
    var entropy_thold: Float
    var logprob_thold: Float
    var no_speech_thold: Float
    var greedy: whisper_greedy_params
    var beam_search: whisper_beam_search_params
    var new_segment_callback: (@convention(c) (OpaquePointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void)?
    var new_segment_callback_user_data: UnsafeMutableRawPointer?
    var progress_callback: (@convention(c) (OpaquePointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void)?
    var progress_callback_user_data: UnsafeMutableRawPointer?
    var encoder_begin_callback: (@convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Bool)?
    var encoder_begin_callback_user_data: UnsafeMutableRawPointer?
    var abort_callback: (@convention(c) (UnsafeMutableRawPointer?) -> Bool)?
    var abort_callback_user_data: UnsafeMutableRawPointer?
}

struct whisper_greedy_params {
    var best_of: Int32
}

struct whisper_beam_search_params {
    var beam_size: Int32
    var patience: Float
}

let WHISPER_SAMPLING_GREEDY: Int32 = 0

// These functions are provided by libwhisper when linked
@_silgen_name("whisper_context_default_params")
func whisper_context_default_params() -> whisper_context_params

@_silgen_name("whisper_init_from_file_with_params")
func whisper_init_from_file_with_params(_ path: UnsafePointer<CChar>, _ params: whisper_context_params) -> OpaquePointer?

@_silgen_name("whisper_free")
func whisper_free(_ ctx: OpaquePointer)

@_silgen_name("whisper_full_default_params")
func whisper_full_default_params(_ strategy: Int32) -> whisper_full_params

@_silgen_name("whisper_full")
func whisper_full(_ ctx: OpaquePointer, _ params: whisper_full_params, _ samples: UnsafePointer<Float>?, _ n_samples: Int32) -> Int32

@_silgen_name("whisper_full_n_segments")
func whisper_full_n_segments(_ ctx: OpaquePointer) -> Int32

@_silgen_name("whisper_full_get_segment_text")
func whisper_full_get_segment_text(_ ctx: OpaquePointer, _ i_segment: Int32) -> UnsafePointer<CChar>?
