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
}
