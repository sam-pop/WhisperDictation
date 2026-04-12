import Foundation

/// Context passed to the C callback for streaming segment output
private final class SegmentCallbackContext {
    let onSegment: (String) -> Void
    let context: OpaquePointer

    init(context: OpaquePointer, onSegment: @escaping (String) -> Void) {
        self.context = context
        self.onSegment = onSegment
    }
}

/// C-compatible callback for new_segment_callback
private func segmentCallback(
    _ ctx: OpaquePointer?,
    _ state: OpaquePointer?,
    _ nNew: Int32,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let userData, let ctx else { return }
    let callbackCtx = Unmanaged<SegmentCallbackContext>.fromOpaque(userData).takeUnretainedValue()

    let totalSegments = whisper_full_n_segments(ctx)
    for i in (totalSegments - nNew)..<totalSegments {
        if let text = whisper_full_get_segment_text(ctx, i) {
            let segment = String(cString: text).trimmingCharacters(in: .whitespaces)
            if !segment.isEmpty {
                callbackCtx.onSegment(segment)
            }
        }
    }
}

final class WhisperBridge: @unchecked Sendable {
    private let context: OpaquePointer
    private let queue = DispatchQueue(label: "com.whisperdictation.whisper", qos: .userInitiated)
    private let vadModelPath: String?

    private static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    init(modelPath: String) throws {
        var contextParams = whisper_context_default_params()
        contextParams.use_gpu = Self.isAppleSilicon
        contextParams.flash_attn = Self.isAppleSilicon

        fputs("[WhisperBridge] Loading model: \(modelPath)\n", stderr)

        guard let ctx = whisper_init_from_file_with_params(modelPath, contextParams) else {
            throw WhisperError.modelLoadFailed(modelPath)
        }
        self.context = ctx

        let vadPath = ModelManager.shared.vadModelPath()
        self.vadModelPath = vadPath
        fputs("[WhisperBridge] Model loaded | GPU: \(Self.isAppleSilicon) | VAD: \(vadPath != nil)\n", stderr)
    }

    deinit {
        whisper_free(context)
    }

    // MARK: - GPU Pre-warming

    /// Run a tiny dummy inference to JIT-compile Metal shaders.
    /// Call once after model load so the first real inference isn't slower.
    func warmup() {
        queue.sync {
            let silence = [Float](repeating: 0, count: 8000) // 0.5s of silence
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.n_threads = 1
            params.single_segment = true
            params.no_context = true
            let langCStr = strdup("en")
            params.language = UnsafePointer(langCStr)
            defer { free(langCStr) }

            silence.withUnsafeBufferPointer { ptr in
                _ = whisper_full(context, params, ptr.baseAddress, Int32(silence.count))
            }
            fputs("[WhisperBridge] GPU pre-warmed\n", stderr)
        }
    }

    // MARK: - Streaming Transcription

    /// Transcribe with streaming: calls `onSegment` as each text segment is decoded.
    /// Returns the full concatenated transcription when complete.
    func transcribe(
        audioBuffer: [Float],
        prompt: String = "",
        onSegment: ((String) -> Void)? = nil
    ) -> String {
        queue.sync {
            let startTime = CFAbsoluteTimeGetCurrent()
            let audioDuration = Double(audioBuffer.count) / 16000.0

            // Adaptive decoding: greedy for short clips (<2s), beam search for longer
            let useBeamSearch = Self.isAppleSilicon && audioBuffer.count >= 32000
            var params = useBeamSearch
                ? whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
                : whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

            if useBeamSearch {
                params.beam_search.beam_size = 5
            }

            // Allocate C strings (freed in defer)
            let langCStr = strdup("en")
            let suppressCStr = strdup("(Thank you|Thanks for watching|Please subscribe|you)")
            let promptCStr = prompt.isEmpty ? nil : strdup(prompt)
            var vadPathCStr: UnsafeMutablePointer<CChar>?

            params.language = UnsafePointer(langCStr)
            params.translate = false
            params.suppress_nst = true
            params.suppress_regex = UnsafePointer(suppressCStr)
            params.no_context = false

            // For streaming, use single_segment to get faster first output
            params.single_segment = onSegment != nil

            // Temperature fallback
            params.temperature = 0.0
            params.temperature_inc = 0.2
            params.entropy_thold = 2.4
            params.logprob_thold = -1.0
            params.no_speech_thold = 0.6

            // Threads
            let threadCount = Self.isAppleSilicon
                ? max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
                : max(1, ProcessInfo.processInfo.activeProcessorCount)
            params.n_threads = Int32(threadCount)

            // VAD
            if let vadPath = self.vadModelPath {
                params.vad = true
                vadPathCStr = strdup(vadPath)
                params.vad_model_path = UnsafePointer(vadPathCStr)
            }

            // Vocabulary prompt
            params.initial_prompt = promptCStr.map { UnsafePointer($0) }

            // Streaming callback setup
            var callbackCtx: SegmentCallbackContext?
            var callbackCtxPtr: Unmanaged<SegmentCallbackContext>?
            if let onSegment {
                let ctx = SegmentCallbackContext(context: context, onSegment: onSegment)
                let ptr = Unmanaged.passRetained(ctx)
                callbackCtx = ctx
                callbackCtxPtr = ptr
                params.new_segment_callback = segmentCallback
                params.new_segment_callback_user_data = ptr.toOpaque()
            }

            defer {
                free(langCStr)
                free(suppressCStr)
                if let p = promptCStr { free(p) }
                if let v = vadPathCStr { free(v) }
                callbackCtxPtr?.release()
            }

            let strategy = useBeamSearch ? "beam(5)" : "greedy"
            fputs("[WhisperBridge] \(String(format: "%.1f", audioDuration))s | \(strategy) | \(threadCount)T | streaming: \(onSegment != nil)\n", stderr)

            let result = audioBuffer.withUnsafeBufferPointer { bufferPtr in
                whisper_full(context, params, bufferPtr.baseAddress, Int32(audioBuffer.count))
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            guard result == 0 else {
                fputs("[WhisperBridge] Failed (\(result)) in \(String(format: "%.2f", elapsed))s\n", stderr)
                return ""
            }

            // Collect full transcription (callback already typed segments incrementally)
            let segmentCount = whisper_full_n_segments(context)
            var transcription = ""
            for i in 0..<segmentCount {
                if let text = whisper_full_get_segment_text(context, i) {
                    transcription += String(cString: text)
                }
            }

            let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            fputs("[WhisperBridge] Done (\(String(format: "%.2f", elapsed))s): \"\(trimmed)\"\n", stderr)
            return trimmed
        }
    }
}

enum WhisperError: LocalizedError {
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load Whisper model at: \(path)"
        }
    }
}
