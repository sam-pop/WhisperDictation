import Foundation

final class WhisperBridge: @unchecked Sendable {
    private let context: OpaquePointer
    private let queue = DispatchQueue(label: "com.whisperdictation.whisper", qos: .userInitiated)

    private static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    init(modelPath: String) throws {
        var contextParams = whisper_context_default_params()
        // Metal GPU is fast on Apple Silicon but slow on Intel AMD GPUs
        contextParams.use_gpu = Self.isAppleSilicon
        contextParams.flash_attn = Self.isAppleSilicon

        print("[WhisperBridge] Loading model: \(modelPath)")
        print("[WhisperBridge] GPU enabled: \(Self.isAppleSilicon)")

        guard let ctx = whisper_init_from_file_with_params(modelPath, contextParams) else {
            throw WhisperError.modelLoadFailed(modelPath)
        }
        self.context = ctx
        print("[WhisperBridge] Model loaded successfully")
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(audioBuffer: [Float], prompt: String = "") -> String {
        queue.sync {
            let startTime = CFAbsoluteTimeGetCurrent()

            var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
            params.beam_search.beam_size = 5
            params.language = UnsafePointer(strdup("en"))
            params.translate = false
            params.no_context = true
            params.single_segment = false
            params.suppress_nst = true
            // Use more threads on Intel since we're CPU-only there
            let threadCount = Self.isAppleSilicon
                ? max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
                : max(1, ProcessInfo.processInfo.activeProcessorCount)
            params.n_threads = Int32(threadCount)

            let promptCString = prompt.isEmpty ? nil : strdup(prompt)
            params.initial_prompt = promptCString.map { UnsafePointer($0) }

            defer {
                if let lang = params.language { free(UnsafeMutablePointer(mutating: lang)) }
                if let p = promptCString { free(p) }
            }

            print("[WhisperBridge] Transcribing \(audioBuffer.count) samples (\(String(format: "%.1f", Double(audioBuffer.count) / 16000.0))s audio) with \(threadCount) threads...")

            let result = audioBuffer.withUnsafeBufferPointer { bufferPtr in
                whisper_full(context, params, bufferPtr.baseAddress, Int32(audioBuffer.count))
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            guard result == 0 else {
                print("[WhisperBridge] whisper_full failed with code \(result) in \(String(format: "%.2f", elapsed))s")
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
            print("[WhisperBridge] Result (\(String(format: "%.2f", elapsed))s): \"\(trimmed)\"")
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
