import Foundation

/// Pure per-window boundary state machine for commit-on-pause segmentation.
/// Fed one Silero speech probability per 512-sample window; decides when the
/// accumulated windows become a chunk. Pure/static-constant so it is fully
/// unit-testable without hardware or the VAD model.
struct VADChunkGate {
    /// Silero v5 processes 512-sample windows at 16 kHz (32 ms). n_window is
    /// read from the model file with no public C accessor, so this constant is
    /// pinned to ggml-silero-v5.1.2.bin — revisit on VAD model bumps.
    static let windowSamples = 512
    static let speechThreshold: Float = 0.5
    /// ~0.7 s of consecutive silence after speech commits a boundary.
    static let pauseWindows = 22
    /// Chunks with under ~0.3 s of speech are dropped, never transcribed.
    static let minSpeechWindows = 10
    /// Force a boundary before Whisper's 30 s hard window: ~25 s.
    static let ceilingWindows = 781

    enum Event: Equatable {
        case none
        /// Windows [0, chunkEndWindow) are the chunk; the caller carries the
        /// rest into the next chunk (replaying their probabilities).
        case commit(chunkEndWindow: Int)
        /// Too little speech before the pause — discard the accumulated windows.
        case drop
    }

    private(set) var windowCount = 0
    private var speechWindows = 0
    private var trailingSilence = 0
    private var minProb: Float = .greatestFiniteMagnitude
    private var minProbIndex = 0

    mutating func ingest(probability p: Float) -> Event {
        let index = windowCount
        windowCount += 1
        if p < minProb { minProb = p; minProbIndex = index }
        if p >= Self.speechThreshold {
            speechWindows += 1
            trailingSilence = 0
        } else {
            trailingSilence += 1
        }
        if trailingSilence >= Self.pauseWindows {
            let hadSpeech = speechWindows >= Self.minSpeechWindows
            let end = windowCount - trailingSilence
            self = VADChunkGate()
            return hadSpeech ? .commit(chunkEndWindow: end) : .drop
        }
        if windowCount >= Self.ceilingWindows {
            let end = max(1, minProbIndex)
            self = VADChunkGate()
            return .commit(chunkEndWindow: end)
        }
        return .none
    }
}

/// Streams mic samples through whisper.cpp's Silero VAD and emits whole
/// utterance chunks on speech pauses. All VAD C calls and mutable state live
/// on `queue`; `onChunk` is delivered async on the main queue (NEVER
/// synchronously — the engine's stop path sync-barriers on `queue`, and a
/// main.sync from inside it would deadlock).
final class VADSegmenter {
    private let queue = DispatchQueue(label: "com.whisperdictation.vad", qos: .userInitiated)
    private let vadContext: OpaquePointer
    private var pending: [Float] = []       // < windowSamples carry between calls
    private var chunkSamples: [Float] = []
    private var chunkProbs: [Float] = []
    private var gate = VADChunkGate()

    /// Whole utterance chunk (16 kHz mono Float32), async on the main queue.
    var onChunk: (([Float]) -> Void)?

    init(vadModelPath: String) throws {
        let params = whisper_vad_default_context_params()
        guard let ctx = whisper_vad_init_from_file_with_params(vadModelPath, params) else {
            throw WhisperError.modelLoadFailed(vadModelPath)
        }
        vadContext = ctx
    }

    deinit { whisper_vad_free(vadContext) }

    /// Reset all session state (accumulators, gate, LSTM). Call at every
    /// session start so stale samples from a torn-down session are harmless.
    func start() {
        queue.async { self.resetSession() }
    }

    /// Safe to call from the audio tap thread — hops to the VAD queue.
    func append(_ samples: [Float]) {
        queue.async { self.process(samples) }
    }

    /// Sync barrier: drains already-enqueued sample work, returns the
    /// un-committed remainder (chunk accumulator + sub-window carry), and
    /// resets session state. A tap block already mid-execution when the tap
    /// was removed may deliver up to ~one buffer late; those samples are lost
    /// from the residual (accepted) and cleaned up by the next start().
    func finishAndCollectResidual() -> [Float] {
        var residual: [Float] = []
        queue.sync {
            residual = self.chunkSamples + self.pending
            self.resetSession()
        }
        return residual
    }

    // MARK: - Queue-confined internals

    private func resetSession() {
        dispatchPrecondition(condition: .onQueue(queue))
        pending.removeAll()
        chunkSamples.removeAll()
        chunkProbs.removeAll()
        gate = VADChunkGate()
        whisper_vad_reset_state(vadContext)
    }

    private func process(_ samples: [Float]) {
        dispatchPrecondition(condition: .onQueue(queue))
        pending.append(contentsOf: samples)
        let windows = pending.count / VADChunkGate.windowSamples
        guard windows > 0 else { return }

        let consumed = windows * VADChunkGate.windowSamples
        let feed = Array(pending.prefix(consumed))
        pending.removeFirst(consumed)

        var probs: [Float] = []
        feed.withUnsafeBufferPointer { ptr in
            guard whisper_vad_detect_speech_no_reset(vadContext, ptr.baseAddress, Int32(feed.count)) else {
                fputs("[VADSegmenter] detect_speech failed — dropping \(feed.count) samples from VAD (audio buffer unaffected)\n", stderr)
                return
            }
            let n = Int(whisper_vad_n_probs(vadContext))
            if let p = whisper_vad_probs(vadContext) {
                probs = Array(UnsafeBufferPointer(start: p, count: n))
            }
        }

        chunkSamples.append(contentsOf: feed)
        ingest(probs: probs)
    }

    /// Feed window probabilities through the gate; on commit, emit the chunk
    /// and carry the remaining windows into the fresh chunk, replaying their
    /// probabilities (one rule covers both commit kinds: replayed pause
    /// silence immediately self-cleans via .drop; replayed ceiling speech
    /// keeps exact counts).
    private func ingest(probs: [Float]) {
        var replay = probs
        while !replay.isEmpty {
            var consumedInReplay = 0
            var event = VADChunkGate.Event.none
            for p in replay {
                chunkProbs.append(p)
                consumedInReplay += 1
                event = gate.ingest(probability: p)
                if event != .none { break }
            }
            replay.removeFirst(consumedInReplay)

            switch event {
            case .none:
                return
            case .drop:
                chunkSamples.removeFirst(min(chunkProbs.count * VADChunkGate.windowSamples, chunkSamples.count))
                chunkProbs.removeAll()
                whisper_vad_reset_state(vadContext)
            case .commit(let endWindow):
                let endSample = endWindow * VADChunkGate.windowSamples
                let chunk = Array(chunkSamples.prefix(endSample))
                let carriedProbs = Array(chunkProbs.suffix(from: endWindow))
                chunkSamples.removeFirst(min(endSample, chunkSamples.count))
                chunkProbs.removeAll()
                whisper_vad_reset_state(vadContext)
                if let onChunk = onChunk {
                    DispatchQueue.main.async { onChunk(chunk) }
                }
                // Carried windows re-enter the fresh gate ahead of any
                // remaining unprocessed probabilities from this call.
                replay = carriedProbs + replay
            }
        }
    }
}
