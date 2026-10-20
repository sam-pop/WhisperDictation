import XCTest
@testable import WhisperDictation

final class SegmentJoinTests: XCTestCase {
    func testFirstSegmentHasNoSeparator() {
        let collector = TranscriptCollector()
        XCTAssertEqual(collector.joinAndAppend("First sentence."), "First sentence.")
        XCTAssertEqual(collector.text, "First sentence.")
    }

    func testLaterSegmentsGetLeadingSpaceInBothOutputs() {
        let collector = TranscriptCollector()
        _ = collector.joinAndAppend("First sentence.")
        XCTAssertEqual(collector.joinAndAppend("Second sentence."), " Second sentence.")
        XCTAssertEqual(collector.text, "First sentence. Second sentence.")
    }
}

final class LiveSessionDecisionTests: XCTestCase {
    func testResidualMinimumIsSampleCountBased() {
        XCTAssertFalse(DictationEngine.residualMeetsMinimum(sampleCount: 0))
        XCTAssertFalse(DictationEngine.residualMeetsMinimum(sampleCount: 4799))   // < 0.3 s
        XCTAssertTrue(DictationEngine.residualMeetsMinimum(sampleCount: 4800))    // = 0.3 s @16 kHz
    }

    func testTerminalPeriodRule() {
        XCTAssertFalse(DictationEngine.needsTerminalPeriod(committed: ""))            // empty: type nothing
        XCTAssertFalse(DictationEngine.needsTerminalPeriod(committed: "Done."))
        XCTAssertFalse(DictationEngine.needsTerminalPeriod(committed: "Really?"))
        XCTAssertTrue(DictationEngine.needsTerminalPeriod(committed: "open the file"))
    }

    /// Same no-period set as batch's fixPunctuation: a chunk cut at a pause often
    /// ends in "," and appending "." produced "milk,." (append-only, can't revise).
    func testTerminalPeriodSkippedAfterSoftPunctuationAndDigits() {
        for text in ["eggs, milk,", "note;", "as follows:", "he said \"go\"", "it's 'fine'", "(see above)", "version 2"] {
            XCTAssertFalse(DictationEngine.needsTerminalPeriod(committed: text), text)
        }
    }

    /// The error shown after a live drain: a decode failure wins; committed text
    /// clears transient status (the 5-minute-cap note, as in batch) but NOT a
    /// forced stop's reason ("Audio input changed"), which used to be erased.
    func testLiveFinishErrorKeepsForcedStopReason() {
        let reason = "Audio input changed. Recording stopped."
        XCTAssertEqual(DictationEngine.liveFinishError(surfaced: "boom", stopReason: reason, committed: "hi", current: reason), "boom")
        XCTAssertEqual(DictationEngine.liveFinishError(surfaced: nil, stopReason: reason, committed: "hi", current: reason), reason)
        XCTAssertNil(DictationEngine.liveFinishError(surfaced: nil, stopReason: nil, committed: "hi", current: "Reached the limit."))
        XCTAssertEqual(DictationEngine.liveFinishError(surfaced: nil, stopReason: nil, committed: "", current: "Reached the limit."), "Reached the limit.")
    }
}
