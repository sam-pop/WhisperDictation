import Foundation

final class WhisperBridge: @unchecked Sendable {
    private let context: OpaquePointer
    private let queue = DispatchQueue(label: "com.whisperdictation.whisper", qos: .userInitiated)

    init(modelPath: String) throws {
        var contextParams = whisper_context_default_params()
        contextParams.use_gpu = true
        contextParams.flash_attn = true

        guard let ctx = whisper_init_from_file_with_params(modelPath, contextParams) else {
            throw WhisperError.modelLoadFailed(modelPath)
        }
        self.context = ctx
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(audioBuffer: [Float], prompt: String = "") -> String {
        queue.sync {
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.language = UnsafePointer(strdup("en"))
            params.translate = false
            params.no_context = true
            params.single_segment = false
            params.suppress_nst = true
            params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))

            // Set developer vocabulary prompt
            let promptCString = prompt.isEmpty ? nil : strdup(prompt)
            params.initial_prompt = promptCString.map { UnsafePointer($0) }

            defer {
                if let lang = params.language { free(UnsafeMutablePointer(mutating: lang)) }
                if let p = promptCString { free(p) }
            }

            let result = audioBuffer.withUnsafeBufferPointer { bufferPtr in
                whisper_full(context, params, bufferPtr.baseAddress, Int32(audioBuffer.count))
            }

            guard result == 0 else {
                print("whisper_full failed with code \(result)")
                return ""
            }

            let segmentCount = whisper_full_n_segments(context)
            var transcription = ""

            for i in 0..<segmentCount {
                if let text = whisper_full_get_segment_text(context, i) {
                    transcription += String(cString: text)
                }
            }

            return transcription.trimmingCharacters(in: .whitespacesAndNewlines)
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
