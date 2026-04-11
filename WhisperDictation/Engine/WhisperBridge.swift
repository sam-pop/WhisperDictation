import Foundation

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
        fputs("[WhisperBridge] GPU: \(Self.isAppleSilicon) | Arch: \(Self.isAppleSilicon ? "arm64" : "x86_64")\n", stderr)

        guard let ctx = whisper_init_from_file_with_params(modelPath, contextParams) else {
            throw WhisperError.modelLoadFailed(modelPath)
        }
        self.context = ctx

        // Check for VAD model
        let vadPath = ModelManager.shared.vadModelPath()
        self.vadModelPath = vadPath
        fputs("[WhisperBridge] VAD model: \(vadPath ?? "not downloaded")\n", stderr)
        fputs("[WhisperBridge] Model loaded successfully\n", stderr)
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(audioBuffer: [Float], prompt: String = "") -> String {
        queue.sync {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Use beam search on Apple Silicon (fast GPU), greedy on Intel (CPU-bound)
            var params = Self.isAppleSilicon
                ? whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
                : whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

            if Self.isAppleSilicon {
                params.beam_search.beam_size = 5
            }

            // Track all strdup allocations to free in defer (never free static pointers)
            let langCStr = strdup("en")
            let suppressCStr = strdup("(Thank you|Thanks for watching|Please subscribe|you)")
            let promptCStr = prompt.isEmpty ? nil : strdup(prompt)
            var vadPathCStr: UnsafeMutablePointer<CChar>?

            params.language = UnsafePointer(langCStr)
            params.translate = false
            params.single_segment = false
            params.suppress_nst = true
            params.suppress_regex = UnsafePointer(suppressCStr)

            // Use previous transcription context for better multi-sentence accuracy
            params.no_context = false

            // Temperature fallback: start at 0 (deterministic), increment on failure
            params.temperature = 0.0
            params.temperature_inc = 0.2

            // Fallback thresholds
            params.entropy_thold = 2.4
            params.logprob_thold = -1.0
            params.no_speech_thold = 0.6

            // Thread count: use all cores on Intel, reserve 2 for GPU on Apple Silicon
            let threadCount = Self.isAppleSilicon
                ? max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
                : max(1, ProcessInfo.processInfo.activeProcessorCount)
            params.n_threads = Int32(threadCount)

            // VAD: trim silence before inference (major speed boost)
            if let vadPath = self.vadModelPath {
                params.vad = true
                vadPathCStr = strdup(vadPath)
                params.vad_model_path = UnsafePointer(vadPathCStr)
            }

            // Vocabulary prompt
            params.initial_prompt = promptCStr.map { UnsafePointer($0) }

            defer {
                free(langCStr)
                free(suppressCStr)
                if let p = promptCStr { free(p) }
                if let v = vadPathCStr { free(v) }
            }

            let audioDuration = Double(audioBuffer.count) / 16000.0
            fputs("[WhisperBridge] Transcribing \(String(format: "%.1f", audioDuration))s audio | \(threadCount) threads | VAD: \(params.vad)\n", stderr)

            let result = audioBuffer.withUnsafeBufferPointer { bufferPtr in
                whisper_full(context, params, bufferPtr.baseAddress, Int32(audioBuffer.count))
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            guard result == 0 else {
                fputs("[WhisperBridge] whisper_full failed with code \(result) in \(String(format: "%.2f", elapsed))s\n", stderr)
                return ""
            }

            let segmentCount = whisper_full_n_segments(context)
            var transcription = ""

            for i in 0..<segmentCount {
                if let text = whisper_full_get_segment_text(context, i) {
                    transcription += String(cString: text)
                }
            }

            let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            fputs("[WhisperBridge] Result (\(String(format: "%.2f", elapsed))s): \"\(trimmed)\"\n", stderr)
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
