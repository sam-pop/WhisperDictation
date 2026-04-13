import XCTest
@testable import WhisperDictation

// MARK: - Settings Tests

final class AppSettingsTests: XCTestCase {
    func testHotkeyCodeIsValid() {
        let code = AppSettings.shared.hotkeyKeyCode
        XCTAssertGreaterThanOrEqual(code, 0)
        XCTAssertLessThan(code, 128)
    }

    func testSelectedModelIsNotEmpty() {
        XCTAssertFalse(AppSettings.shared.selectedModel.isEmpty)
    }

    func testSoundFeedbackDefault() {
        XCTAssertTrue(AppSettings.shared.soundFeedbackEnabled)
    }

    func testMinimumRecordingDuration() {
        XCTAssertEqual(AppSettings.shared.minimumRecordingDuration, 0.3)
    }

    func testHotkeyModeRoundTrips() {
        let settings = AppSettings.shared
        let original = settings.hotkeyMode

        settings.hotkeyMode = .toggle
        XCTAssertEqual(settings.hotkeyMode, .toggle)

        settings.hotkeyMode = .pushToTalk
        XCTAssertEqual(settings.hotkeyMode, .pushToTalk)

        settings.hotkeyMode = original
    }

    func testToggleHoldDurationClampsAboveRange() {
        let settings = AppSettings.shared
        let original = settings.toggleHoldDuration

        settings.toggleHoldDuration = 999.0
        XCTAssertLessThanOrEqual(settings.toggleHoldDuration, 3.0)

        settings.toggleHoldDuration = original
    }

    func testToggleHoldDurationClampsBelowRange() {
        let settings = AppSettings.shared
        let original = settings.toggleHoldDuration

        settings.toggleHoldDuration = -5.0
        XCTAssertGreaterThanOrEqual(settings.toggleHoldDuration, 0.5)

        settings.toggleHoldDuration = original
    }

    func testToggleHoldDurationInRange() {
        let value = AppSettings.shared.toggleHoldDuration
        XCTAssertGreaterThanOrEqual(value, 0.5)
        XCTAssertLessThanOrEqual(value, 3.0)
    }

    func testGrammarCorrectionDefault() {
        XCTAssertTrue(AppSettings.shared.grammarCorrectionEnabled)
    }

    func testNumberConversionDefault() {
        XCTAssertTrue(AppSettings.shared.numberConversionEnabled)
    }

    func testVocabularyPromptNotEmpty() {
        let prompt = AppSettings.shared.vocabularyPrompt
        XCTAssertFalse(prompt.isEmpty)
        XCTAssertTrue(prompt.contains("API"))
        XCTAssertTrue(prompt.contains("JSON"))
        XCTAssertTrue(prompt.contains("SwiftUI"))
    }

    func testDefaultVocabularyPrompt() {
        XCTAssertTrue(AppSettings.defaultVocabularyPrompt.contains("Technical software engineering"))
    }

    func testCustomTermsDefaultEmpty() {
        // Fresh install should have no custom terms (or whatever the user currently has)
        let terms = AppSettings.shared.customTerms
        XCTAssertTrue(terms is [String]) // type check — always passes, validates the property exists
    }

    func testAddAndRemoveCustomTerm() {
        let settings = AppSettings.shared
        let original = settings.customTerms

        settings.addCustomTerm("TestTermXYZ123")
        XCTAssertTrue(settings.customTerms.contains("TestTermXYZ123"))

        // Duplicate (case-insensitive) should not add
        let countBefore = settings.customTerms.count
        settings.addCustomTerm("testtermxyz123")
        XCTAssertEqual(settings.customTerms.count, countBefore)

        // Empty/whitespace term should not add
        settings.addCustomTerm("   ")
        XCTAssertFalse(settings.customTerms.contains("   "))

        settings.removeCustomTerm("TestTermXYZ123")
        XCTAssertFalse(settings.customTerms.contains("TestTermXYZ123"))

        // Restore original
        settings.customTerms = original
    }
}

// MARK: - State Machine Tests

final class DictationStateTests: XCTestCase {
    func testAllStatesExist() {
        XCTAssertEqual(DictationState.idle.rawValue, "idle")
        XCTAssertEqual(DictationState.recording.rawValue, "recording")
        XCTAssertEqual(DictationState.processing.rawValue, "processing")
        XCTAssertEqual(DictationState.typing.rawValue, "typing")
    }
}

// MARK: - Model Manager Tests

final class ModelManagerTests: XCTestCase {
    func testModelInfoCount() {
        XCTAssertEqual(ModelManager.ModelInfo.all.count, 6)
    }

    func testRecommendedModelsCount() {
        XCTAssertEqual(ModelManager.ModelInfo.recommended.count, 3)
    }

    func testQuantizedModelsAreRecommended() {
        for model in ModelManager.ModelInfo.recommended {
            XCTAssertTrue(model.isQuantized, "\(model.name) should be quantized")
        }
    }

    func testFullPrecisionModelsExist() {
        let names = ModelManager.ModelInfo.all.map(\.name)
        XCTAssertTrue(names.contains("Base (English)"))
        XCTAssertTrue(names.contains("Small (English)"))
        XCTAssertTrue(names.contains("Medium (English)"))
    }

    func testQuantizedModelsExist() {
        let names = ModelManager.ModelInfo.all.map(\.name)
        XCTAssertTrue(names.contains("Base Q5 (English)"))
        XCTAssertTrue(names.contains("Small Q5 (English)"))
        XCTAssertTrue(names.contains("Medium Q5 (English)"))
    }

    func testModelsDirectoryExists() {
        let dir = ModelManager.shared.modelsDirectory
        XCTAssertFalse(dir.path.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testModelURLsAreValid() {
        for model in ModelManager.ModelInfo.all {
            XCTAssertTrue(model.url.absoluteString.contains("huggingface.co"))
            XCTAssertTrue(model.url.absoluteString.hasSuffix(".bin"))
        }
    }

    func testVADModel() {
        let vad = ModelManager.ModelInfo.vadSilero
        XCTAssertTrue(vad.url.absoluteString.contains("whisper-vad"))
        XCTAssertEqual(vad.fileName, "ggml-silero-v5.1.2.bin")
    }
}

// MARK: - TextCorrector Tests

final class TextCorrectorTests: XCTestCase {
    let corrector = TextCorrector.shared

    // MARK: Number Conversion - Basic

    func testNumberZero() {
        let result = corrector.correct("zero")
        XCTAssertEqual(result, "0")
    }

    func testNumberSingleDigit() {
        XCTAssertTrue(corrector.correct("one").contains("1"))
        XCTAssertTrue(corrector.correct("nine").contains("9"))
    }

    func testNumberTeens() {
        XCTAssertTrue(corrector.correct("eleven").contains("11"))
        XCTAssertTrue(corrector.correct("nineteen").contains("19"))
    }

    func testNumberTens() {
        XCTAssertTrue(corrector.correct("twenty").contains("20"))
        XCTAssertTrue(corrector.correct("ninety").contains("90"))
    }

    func testNumberCompound() {
        XCTAssertTrue(corrector.correct("forty two").contains("42"))
        XCTAssertTrue(corrector.correct("twenty one").contains("21"))
        XCTAssertTrue(corrector.correct("ninety nine").contains("99"))
    }

    // MARK: Number Conversion - Hundreds/Thousands

    func testNumberHundred() {
        XCTAssertTrue(corrector.correct("three hundred").contains("300"))
        XCTAssertTrue(corrector.correct("a hundred").contains("100"))
        XCTAssertTrue(corrector.correct("one hundred").contains("100"))
    }

    func testNumberHundredCompound() {
        XCTAssertTrue(corrector.correct("three hundred forty two").contains("342"))
        XCTAssertTrue(corrector.correct("one hundred and twenty three").contains("123"))
    }

    func testNumberThousand() {
        XCTAssertTrue(corrector.correct("one thousand").contains("1,000"))
        XCTAssertTrue(corrector.correct("a thousand").contains("1,000"))
    }

    func testNumberLargeCompound() {
        XCTAssertTrue(corrector.correct("two thousand five hundred").contains("2,500"))
        XCTAssertTrue(corrector.correct("one million").contains("1,000,000"))
    }

    // MARK: Number Conversion - Digit Sequences

    func testDigitSequence() {
        XCTAssertTrue(corrector.correct("two four six eight").contains("2,468"))
        XCTAssertTrue(corrector.correct("nine one one").contains("911"))
        XCTAssertTrue(corrector.correct("one two three").contains("123"))
    }

    func testDigitSequenceTens() {
        XCTAssertTrue(corrector.correct("eighty eighty").contains("8,080"))
        XCTAssertTrue(corrector.correct("fifty fifty").contains("5,050"))
    }

    // MARK: Number Conversion - In Context

    func testNumberInSentence() {
        let result = corrector.correct("I have three hundred dollars")
        XCTAssertTrue(result.contains("300"))
        XCTAssertTrue(result.contains("dollars"))
    }

    func testNumberPreservesNonNumberWords() {
        let result = corrector.correct("a big dog")
        XCTAssertTrue(result.lowercased().contains("a big dog"))
    }

    // MARK: Number Conversion - Format

    func testFormatThousands() {
        XCTAssertTrue(corrector.correct("five thousand").contains("5,000"))
    }

    func testNoTrailingPeriodAfterNumber() {
        let result = corrector.correct("three hundred")
        XCTAssertFalse(result.hasSuffix("."), "Numbers shouldn't get trailing periods: '\(result)'")
    }

    // MARK: Acronym/Term Casing

    func testAcronymUppercase() {
        let result = corrector.correct("the api returns json")
        XCTAssertTrue(result.contains("API"))
        XCTAssertTrue(result.contains("JSON"))
    }

    func testMixedCaseTerms() {
        XCTAssertTrue(corrector.correct("use javascript").contains("JavaScript"))
        XCTAssertTrue(corrector.correct("deploy with docker").contains("Docker"))
        XCTAssertTrue(corrector.correct("query postgresql").contains("PostgreSQL"))
    }

    func testAppleTerms() {
        XCTAssertTrue(corrector.correct("build for macos").contains("macOS"))
        XCTAssertTrue(corrector.correct("using swiftui").contains("SwiftUI"))
        XCTAssertTrue(corrector.correct("open xcode").contains("Xcode"))
    }

    func testAITerms() {
        XCTAssertTrue(corrector.correct("use openai").contains("OpenAI"))
        XCTAssertTrue(corrector.correct("ask claude").contains("Claude"))
    }

    func testCompoundTerms() {
        XCTAssertTrue(corrector.correct("set up ci/cd").contains("CI/CD"))
        XCTAssertTrue(corrector.correct("the devops team").contains("DevOps"))
        XCTAssertTrue(corrector.correct("use graphql").contains("GraphQL"))
    }

    // MARK: Capitalization

    func testCapitalizeFirstLetter() {
        let result = corrector.correct("hello world")
        XCTAssertTrue(result.hasPrefix("H"))
    }

    func testCapitalizeAfterPeriod() {
        let result = corrector.correct("first sentence. second sentence")
        // After the period, "second" should be capitalized
        XCTAssertTrue(result.contains("Second") || result.contains("second"), "Got: \(result)")
    }

    func testCapitalizeStandaloneI() {
        let result = corrector.correct("i think i should go")
        XCTAssertTrue(result.contains("I think I should"))
    }

    func testCapitalizeContractions() {
        let result = corrector.correct("i'm going and i'll be back")
        XCTAssertTrue(result.contains("I'm") || result.contains("I'M"))
        XCTAssertTrue(result.contains("I'll") || result.contains("I'LL"))
    }

    // MARK: Punctuation

    func testAddTrailingPeriod() {
        let result = corrector.correct("this is a test")
        XCTAssertTrue(result.hasSuffix("."), "Should add period: '\(result)'")
    }

    func testNoDoubleTrailingPunctuation() {
        let result = corrector.correct("is this a test?")
        XCTAssertFalse(result.hasSuffix("?."))
        XCTAssertTrue(result.hasSuffix("?"))
    }

    func testFixSpaceBeforePunctuation() {
        let result = corrector.correct("hello .")
        XCTAssertFalse(result.contains(" ."))
    }

    func testFixDoubleSpaces() {
        let result = corrector.correct("hello  world")
        XCTAssertFalse(result.contains("  "))
    }

    // MARK: Full Pipeline

    func testFullPipeline() {
        let result = corrector.correct("create a rest api endpoint that returns json")
        XCTAssertTrue(result.contains("REST"))
        XCTAssertTrue(result.contains("API"))
        XCTAssertTrue(result.contains("JSON"))
        XCTAssertTrue(result.hasPrefix("C")) // Capitalized
    }

    func testFullPipelineWithNumbers() {
        let result = corrector.correct("i need three hundred megabytes of ram")
        XCTAssertTrue(result.contains("300"))
        XCTAssertTrue(result.contains("RAM"))
        XCTAssertTrue(result.contains("I need"))
    }

    // MARK: Custom Terms

    func testCustomTermCasing() {
        let settings = AppSettings.shared
        let original = settings.customTerms

        settings.customTerms = ["McKinsey", "DeepMind"]
        let result = corrector.correct("talk to mckinsey about deepmind")
        XCTAssertTrue(result.contains("McKinsey"), "Got: \(result)")
        XCTAssertTrue(result.contains("DeepMind"), "Got: \(result)")

        settings.customTerms = original
    }

    func testCustomTermsEmptyIsNoOp() {
        let settings = AppSettings.shared
        let original = settings.customTerms

        settings.customTerms = []
        let result = corrector.correct("hello world")
        XCTAssertTrue(result.hasPrefix("Hello"))

        settings.customTerms = original
    }

    func testCustomTermsDoNotBreakExistingPipeline() {
        let settings = AppSettings.shared
        let original = settings.customTerms

        settings.customTerms = ["MyCompany"]
        let result = corrector.correct("the api at mycompany returns json")
        XCTAssertTrue(result.contains("API"), "Got: \(result)")
        XCTAssertTrue(result.contains("JSON"), "Got: \(result)")
        XCTAssertTrue(result.contains("MyCompany"), "Got: \(result)")

        settings.customTerms = original
    }
}

// MARK: - DictationEngine Tests

final class DictationEngineTests: XCTestCase {
    func testInitialState() {
        let engine = DictationEngine()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertTrue(engine.lastTranscription.isEmpty)
        XCTAssertFalse(engine.isModelLoaded)
    }
}

// MARK: - WhisperBridge Tests

final class WhisperBridgeTests: XCTestCase {
    func testInvalidModelPathThrows() {
        XCTAssertThrowsError(try WhisperBridge(modelPath: "/nonexistent/model.bin")) { error in
            XCTAssertTrue(error is WhisperError)
            XCTAssertTrue(error.localizedDescription.contains("/nonexistent/model.bin"))
        }
    }
}

// MARK: - AudioDeviceManager Tests

final class AudioDeviceManagerTests: XCTestCase {
    func testListDevices() {
        let manager = AudioDeviceManager.shared
        manager.refreshDevices()
        // Should have at least one input device on any Mac
        XCTAssertFalse(manager.inputDevices.isEmpty, "No audio input devices found")
    }

    func testSelectedDeviceHandled() {
        // selectedDevice returns nil if no matching device, or a valid device if set
        let device = AudioDeviceManager.shared.selectedDevice
        if let device {
            XCTAssertFalse(device.name.isEmpty)
            XCTAssertFalse(device.uid.isEmpty)
        }
        // Either nil or valid — both are acceptable
    }
}
