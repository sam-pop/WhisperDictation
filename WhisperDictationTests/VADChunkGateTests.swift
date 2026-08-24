import XCTest
@testable import WhisperDictation

final class VADChunkGateTests: XCTestCase {
    private func feed(_ gate: inout VADChunkGate, speech: Int = 0, silence: Int = 0) -> VADChunkGate.Event {
        var last = VADChunkGate.Event.none
        for _ in 0..<speech { last = gate.ingest(probability: 0.9) }
        for _ in 0..<silence { last = gate.ingest(probability: 0.1) }
        return last
    }

    func testConstantsMatchSpecTimings() {
        // 512 samples @16 kHz = 32 ms per window.
        XCTAssertEqual(Double(VADChunkGate.pauseWindows) * 0.032, 0.448, accuracy: 0.033)      // ~0.45 s
        XCTAssertEqual(Double(VADChunkGate.minSpeechWindows) * 0.032, 0.32, accuracy: 0.033)   // ~0.3 s
        XCTAssertEqual(Double(VADChunkGate.ceilingWindows) * 0.032, 25.0, accuracy: 0.05)      // ~25 s
    }

    func testPauseAfterEnoughSpeechCommitsExcludingTrailingSilence() {
        var gate = VADChunkGate()
        let event = feed(&gate, speech: 30, silence: VADChunkGate.pauseWindows)
        XCTAssertEqual(event, .commit(chunkEndWindow: 30))
    }

    func testPauseAfterTooLittleSpeechDrops() {
        var gate = VADChunkGate()
        let event = feed(&gate, speech: VADChunkGate.minSpeechWindows - 1,
                         silence: VADChunkGate.pauseWindows)
        XCTAssertEqual(event, .drop)
    }

    func testShortSilenceDoesNotCommit() {
        var gate = VADChunkGate()
        let event = feed(&gate, speech: 30, silence: VADChunkGate.pauseWindows - 1)
        XCTAssertEqual(event, .none)
    }

    func testSpeechResetsTrailingSilenceRun() {
        var gate = VADChunkGate()
        _ = feed(&gate, speech: 30, silence: VADChunkGate.pauseWindows - 1)
        _ = gate.ingest(probability: 0.9)                       // speech resets the run
        let event = feed(&gate, silence: VADChunkGate.pauseWindows - 1)
        XCTAssertEqual(event, .none)                            // run restarted, not resumed
    }

    func testCeilingForcesCommitAtLowestProbabilityWindow() {
        var gate = VADChunkGate()
        var event = VADChunkGate.Event.none
        for i in 0..<VADChunkGate.ceilingWindows {
            event = gate.ingest(probability: i == 400 ? 0.55 : 0.95)  // dip (still speech) at 400
        }
        XCTAssertEqual(event, .commit(chunkEndWindow: 400))
    }

    func testGateIsFreshAfterCommit() {
        var gate = VADChunkGate()
        _ = feed(&gate, speech: 30, silence: VADChunkGate.pauseWindows)   // commit + reset
        let event = feed(&gate, speech: 30, silence: VADChunkGate.pauseWindows)
        XCTAssertEqual(event, .commit(chunkEndWindow: 30))                // counts restarted
    }
}
