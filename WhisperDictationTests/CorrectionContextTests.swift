import XCTest
@testable import WhisperDictation

final class CorrectionContextTests: XCTestCase {
    private var savedGrammar = true
    private var savedNumberConversion = true
    private var savedCustomTerms: [String] = []

    override func setUp() {
        super.setUp()
        savedGrammar = AppSettings.shared.grammarCorrectionEnabled
        savedNumberConversion = AppSettings.shared.numberConversionEnabled
        savedCustomTerms = AppSettings.shared.customTerms
        AppSettings.shared.grammarCorrectionEnabled = true
        // Pin the other correction inputs too: the expected strings below assume no
        // custom-term rewrites, and a persisted user setting must not perturb them.
        AppSettings.shared.numberConversionEnabled = true
        AppSettings.shared.customTerms = []
    }

    override func tearDown() {
        AppSettings.shared.grammarCorrectionEnabled = savedGrammar
        AppSettings.shared.numberConversionEnabled = savedNumberConversion
        AppSettings.shared.customTerms = savedCustomTerms
        super.tearDown()
    }

    func testStandaloneContextMatchesLegacyEntryPoint() {
        for s in ["hello world", "i think it's fine", "run the tests ."] {
            XCTAssertEqual(TextCorrector.shared.correct(s),
                           TextCorrector.shared.correct(s, context: .standalone))
        }
    }

    func testMidSentenceChunkKeepsLowercaseAndGetsNoPeriod() {
        let ctx = CorrectionContext(atSentenceStart: false, appendPeriod: false)
        XCTAssertEqual(TextCorrector.shared.correct("then run the tests", context: ctx),
                       "then run the tests")
    }

    func testInternalSentenceStartsStillCapitalizeMidSentenceChunk() {
        let ctx = CorrectionContext(atSentenceStart: false, appendPeriod: false)
        XCTAssertEqual(TextCorrector.shared.correct("then stop. also check the logs", context: ctx),
                       "then stop. Also check the logs")
    }

    func testSentenceStartChunkCapitalizesWithoutPeriod() {
        let ctx = CorrectionContext(atSentenceStart: true, appendPeriod: false)
        XCTAssertEqual(TextCorrector.shared.correct("open the file", context: ctx),
                       "Open the file")
    }

    func testCollectorSentenceStartTracking() {
        let c = TranscriptCollector()
        XCTAssertTrue(c.atSentenceStart)                    // empty
        _ = c.joinAndAppend("open the file")
        XCTAssertFalse(c.atSentenceStart)                   // mid-sentence
        _ = c.joinAndAppend("then stop.")
        XCTAssertTrue(c.atSentenceStart)                    // after terminal punctuation
    }
}
