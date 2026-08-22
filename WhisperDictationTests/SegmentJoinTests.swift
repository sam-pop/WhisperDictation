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
