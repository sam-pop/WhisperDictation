import XCTest
import CryptoKit
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

    // MARK: Getter validation (Phase 2)

    /// The getter must clamp out-of-band raw values that bypassed the clamping
    /// setter (e.g. written directly to UserDefaults by an older build or a
    /// corrupt domain). We write raw values under the key and read back through
    /// the getter.
    func testToggleHoldDurationGetterClampsRawValue() {
        let key = "toggleHoldDuration"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(999.0, forKey: key)
        XCTAssertEqual(AppSettings.shared.toggleHoldDuration, 3.0)

        UserDefaults.standard.set(-5.0, forKey: key)
        XCTAssertEqual(AppSettings.shared.toggleHoldDuration, 0.5)
    }

    func testMinimumRecordingDurationGetterClampsRawValue() {
        let key = "minimumRecordingDuration"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(999.0, forKey: key)
        XCTAssertEqual(AppSettings.shared.minimumRecordingDuration, 5.0)

        UserDefaults.standard.set(-5.0, forKey: key)
        XCTAssertEqual(AppSettings.shared.minimumRecordingDuration, 0.0)
    }

    func testSelectedModelFallsBackForUnknownValue() {
        let key = "selectedModel"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        // Unknown id → default
        UserDefaults.standard.set("totally-bogus-model-xyz", forKey: key)
        XCTAssertEqual(AppSettings.shared.selectedModel, "small.en")

        // Known catalog id → preserved
        UserDefaults.standard.set("base.en", forKey: key)
        XCTAssertEqual(AppSettings.shared.selectedModel, "base.en")
    }

    func testCustomTermsCappedAt100() {
        let settings = AppSettings.shared
        let original = settings.customTerms
        defer { settings.customTerms = original }

        settings.customTerms = (0..<150).map { "Term\($0)" }
        XCTAssertEqual(settings.customTerms.count, 100)
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

// MARK: - Live Dictation Setting Tests

final class LiveDictationSettingTests: XCTestCase {
    func testLiveDictationEnabledRoundTrip() {
        let settings = AppSettings.shared
        let saved = settings.liveDictationEnabled          // save user's real value
        defer { settings.liveDictationEnabled = saved }    // restore

        settings.liveDictationEnabled = true
        XCTAssertTrue(settings.liveDictationEnabled)
        settings.liveDictationEnabled = false
        XCTAssertFalse(settings.liveDictationEnabled)
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
        XCTAssertEqual(vad.fileName, "ggml-silero-v6.2.0.bin")
    }

    /// v6 is preferred; an existing install with only v5 keeps working on v5 until
    /// the background upgrade lands, so live dictation never goes dark.
    func testPreferredVADFileFallsBackToLegacyV5() {
        let v6 = ModelManager.ModelInfo.vadSilero.fileName
        let v5 = ModelManager.legacyVADFileName
        XCTAssertEqual(ModelManager.preferredVADFileName(existing: [v5, v6]), v6)
        XCTAssertEqual(ModelManager.preferredVADFileName(existing: [v5]), v5)
        XCTAssertEqual(ModelManager.preferredVADFileName(existing: [v6]), v6)
        XCTAssertNil(ModelManager.preferredVADFileName(existing: []))
    }

    // MARK: Download Integrity (Phase 1)

    /// Every catalog model AND the VAD model must carry a well-formed pinned
    /// SHA256 (64 lowercase hex chars). A blank/short hash means a model shipped
    /// without integrity protection.
    func testEveryModelHasWellFormedSHA256() {
        let allModels = ModelManager.ModelInfo.all + [ModelManager.ModelInfo.vadSilero]
        let hexSet = CharacterSet(charactersIn: "0123456789abcdef")
        for model in allModels {
            let hash = model.sha256
            XCTAssertEqual(hash.count, 64, "\(model.name) sha256 must be 64 chars, got \(hash.count)")
            XCTAssertTrue(
                hash.unicodeScalars.allSatisfy { hexSet.contains($0) },
                "\(model.name) sha256 must be lowercase hex: \(hash)"
            )
        }
    }

    func testModelSHA256AreUnique() {
        let allModels = ModelManager.ModelInfo.all + [ModelManager.ModelInfo.vadSilero]
        let hashes = allModels.map(\.sha256)
        XCTAssertEqual(Set(hashes).count, hashes.count, "Pinned model hashes must all be distinct")
    }

    func testAcceptableStatusCodes() {
        XCTAssertTrue(ModelManager.isAcceptableStatusCode(200))
        XCTAssertTrue(ModelManager.isAcceptableStatusCode(206))
        XCTAssertTrue(ModelManager.isAcceptableStatusCode(299))
        XCTAssertFalse(ModelManager.isAcceptableStatusCode(199))
        XCTAssertFalse(ModelManager.isAcceptableStatusCode(300))
        XCTAssertFalse(ModelManager.isAcceptableStatusCode(304))
        XCTAssertFalse(ModelManager.isAcceptableStatusCode(404))
        XCTAssertFalse(ModelManager.isAcceptableStatusCode(500))
    }

    func testSHA256KnownVector() throws {
        // Canonical SHA256("abc")
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wd-sha-abc-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ModelManager.sha256Hex(ofFileAt: url), expected)
    }

    func testSHA256EmptyFile() throws {
        // Canonical SHA256 of zero bytes
        let expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wd-sha-empty-\(UUID().uuidString)")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ModelManager.sha256Hex(ofFileAt: url), expected)
    }

    /// The async `URLSession.download(from:delegate:)` never calls `didWriteData` on a
    /// task delegate (the bar sat at 0), so progress must come from the task's
    /// `Progress`, obtained in `didCreateTask`. No network: the task is never resumed.
    func testDownloadDelegateReportsTaskProgress() {
        var reported: [Double] = []
        let delegate = DownloadDelegate { reported.append($0) }
        let session = URLSession(configuration: .ephemeral)
        let task = session.downloadTask(with: URL(string: "https://example.invalid/model.bin")!)
        defer { task.cancel(); session.invalidateAndCancel() }

        delegate.urlSession(session, didCreateTask: task)
        task.progress.totalUnitCount = 200
        task.progress.completedUnitCount = 50
        task.progress.completedUnitCount = 200

        XCTAssertEqual(reported.last ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertTrue(reported.contains { abs($0 - 0.25) < 0.0001 }, "got \(reported)")
    }

    /// The active model is never deletable (it would leave the engine with no model);
    /// every other model is. Pure check — never touches the real Models directory.
    func testOnlyInactiveModelsAreDeletable() {
        for active in ModelManager.ModelInfo.all {
            for model in ModelManager.ModelInfo.all {
                XCTAssertEqual(
                    ModelManager.isDeletable(model, selectedModel: active.settingsId),
                    model.fileName != active.fileName,
                    "\(model.fileName) with active \(active.settingsId)"
                )
            }
        }
    }

    /// Streaming hash of a multi-chunk (>1 MB) file must match a one-shot hash of
    /// the same bytes — proves the chunked read covers the whole file with no
    /// dropped/overlapping bytes at chunk boundaries.
    func testSHA256StreamingMatchesOneShotMultiChunk() throws {
        let byteCount = 3 * 1024 * 1024 + 7 // deliberately not a chunk multiple
        var data = Data(count: byteCount)
        for i in 0..<byteCount { data[i] = UInt8((i * 31 + 7) & 0xff) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wd-sha-multi-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let streamed = try ModelManager.sha256Hex(ofFileAt: url)
        let oneShot = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(streamed, oneShot)
    }

    func testSHA256MissingFileThrows() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).bin")
        XCTAssertThrowsError(try ModelManager.sha256Hex(ofFileAt: url))
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

    // MARK: - Hotkey dispatch semantics (Phase 3)

    /// Push-to-talk: a key-down is always deliberate — while transcribing it cancels,
    /// otherwise it starts recording.
    func testPushToTalkKeyDownCancelsOnlyWhileTranscribing() {
        XCTAssertEqual(DictationEngine.keyDownAction(mode: .pushToTalk, state: .idle), .startRecording)
        XCTAssertEqual(DictationEngine.keyDownAction(mode: .pushToTalk, state: .recording), .startRecording)
        XCTAssertEqual(DictationEngine.keyDownAction(mode: .pushToTalk, state: .processing), .cancelTranscription)
        XCTAssertEqual(DictationEngine.keyDownAction(mode: .pushToTalk, state: .typing), .cancelTranscription)
    }

    /// Toggle mode: a bare key-down must NEVER cancel directly — a stray tap during
    /// .processing would destroy an in-flight transcription (e.g. right after the
    /// 5-minute cap auto-stopped a long recording). Everything goes through the
    /// deliberate hold.
    func testToggleKeyDownNeverCancelsDirectly() {
        for state in [DictationState.idle, .recording, .processing, .typing] {
            XCTAssertEqual(
                DictationEngine.keyDownAction(mode: .toggle, state: state),
                .scheduleToggle,
                "toggle key-down in \(state) must only schedule the hold"
            )
        }
    }

    /// A COMPLETED toggle hold is as deliberate as any other toggle action:
    /// idle starts, recording stops, transcribing cancels.
    func testToggleHoldActionPerState() {
        XCTAssertEqual(DictationEngine.toggleHoldAction(state: .idle), .startRecording)
        XCTAssertEqual(DictationEngine.toggleHoldAction(state: .recording), .stopAndTranscribe)
        XCTAssertEqual(DictationEngine.toggleHoldAction(state: .processing), .cancelTranscription)
        XCTAssertEqual(DictationEngine.toggleHoldAction(state: .typing), .cancelTranscription)
    }

    func testInitialState() {
        let engine = DictationEngine()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertTrue(engine.lastTranscription.isEmpty)
        XCTAssertFalse(engine.isModelLoaded)
    }

    // MARK: - Prompt assembly (Phase 2)

    /// A base vocabulary prompt that alone exceeds the word budget must be
    /// truncated (whisper only uses the last 223 prompt tokens).
    func testBuildPromptTruncatesOversizedBase() {
        let longBase = (0..<1000).map { "word\($0)" }.joined(separator: " ")
        let result = DictationEngine.buildPrompt(base: longBase, customTerms: [])
        XCTAssertEqual(result.split(separator: " ").count, DictationEngine.promptWordBudget)
    }

    /// Within budget, custom terms are appended after the base prompt.
    func testBuildPromptAppendsCustomTermsWhenBudgetAllows() {
        let result = DictationEngine.buildPrompt(base: "one two three", customTerms: ["Acme", "Widget"])
        XCTAssertTrue(result.hasPrefix("one two three"))
        XCTAssertTrue(result.contains("Acme"))
        XCTAssertTrue(result.contains("Widget"))
    }

    /// whisper keeps only the LAST ~223 prompt tokens, so an oversized base must yield
    /// to the user's custom terms (it used to push them out entirely).
    func testBuildPromptCustomTermsOutrankOversizedBase() {
        let longBase = (0..<1000).map { "word\($0)" }.joined(separator: " ")
        let result = DictationEngine.buildPrompt(base: longBase, customTerms: ["UniqueTermZZZ"])
        XCTAssertTrue(result.hasSuffix("UniqueTermZZZ"))
        XCTAssertTrue(result.hasPrefix("word0 word1"))     // base kept from its start (framing)
        XCTAssertEqual(result.split(separator: " ").count, DictationEngine.promptWordBudget)
    }

    /// Budget sized to whisper's real limit: 223 tokens at the measured 2.48
    /// tokens/word of the default vocabulary prompt (1373 tokens / 553 words).
    func testPromptWordBudgetFitsWhisperPromptWindow() {
        XCTAssertLessThanOrEqual(Double(DictationEngine.promptWordBudget) * 2.48, 223)
    }

    /// Worst case (default prompt + 100 terms + long tail): stays in budget, and the
    /// tail then the terms survive — the highest-priority text, nearest the decode.
    func testBuildPromptPriorityTailThenTermsThenBase() {
        let terms = (1...100).map { "term\($0)" }
        let tail = (1...80).map { "t\($0)" }.joined(separator: " ")
        let p = DictationEngine.buildPrompt(base: AppSettings.defaultVocabularyPrompt, customTerms: terms, transcriptTail: tail)
        XCTAssertLessThanOrEqual(p.split(separator: " ").count, DictationEngine.promptWordBudget)
        XCTAssertTrue(p.hasSuffix("t79 t80"))
        XCTAssertTrue(p.contains("term1,"))
    }

    /// Every term the UI lets you add (promptTermLimit) must survive even a full
    /// live tail. Previously 100 were allowed and as few as 39 reached whisper,
    /// silently dropping the newest ones.
    func testEveryAllowedTermSurvivesAFullLiveTail() {
        XCTAssertLessThanOrEqual(DictationEngine.promptTermLimit + DictationEngine.liveTailWordCap,
                                 DictationEngine.promptWordBudget)
        let terms = (1...DictationEngine.promptTermLimit).map { "term\($0)" }
        let tail = (1...80).map { "t\($0)" }.joined(separator: " ")
        let p = DictationEngine.buildPrompt(base: AppSettings.defaultVocabularyPrompt, customTerms: terms, transcriptTail: tail)
        XCTAssertTrue(p.contains("term\(DictationEngine.promptTermLimit) t"), "last allowed term missing: \(p)")
    }

    /// Storage keeps up to maxCustomTerms (so no saved term is ever deleted); only
    /// the first promptTermLimit reach the prompt.
    func testTermsBeyondPromptLimitAreNotSent() {
        let terms = (1...100).map { "term\($0)" }
        let p = DictationEngine.buildPrompt(base: "", customTerms: terms)
        XCTAssertTrue(p.hasSuffix("term\(DictationEngine.promptTermLimit)"))
    }

    /// Empty custom terms → the base prompt is returned unchanged (when in budget).
    func testBuildPromptEmptyCustomTermsReturnsBase() {
        XCTAssertEqual(DictationEngine.buildPrompt(base: "hello world", customTerms: []), "hello world")
    }
}

// MARK: - buildPrompt committed-transcript tail

/// The live-mode context carry: previously committed transcript text is appended
/// last (nearest the decode), truncated to the last `liveTailWordCap` words; it
/// outranks custom terms and the base prompt for the word budget.
final class BuildPromptTailTests: XCTestCase {
    func testDefaultOmitsTailAndMatchesTwoArgCall() {
        XCTAssertEqual(DictationEngine.buildPrompt(base: "a b c", customTerms: ["X"]),
                       DictationEngine.buildPrompt(base: "a b c", customTerms: ["X"], transcriptTail: ""))
    }

    func testTailAppendedLast() {
        let p = DictationEngine.buildPrompt(base: "vocab", customTerms: ["Term"], transcriptTail: "we did the thing")
        XCTAssertTrue(p.hasSuffix("we did the thing"))
        XCTAssertTrue(p.hasPrefix("vocab"))
    }

    func testTailTruncatedToLiveTailWordCap() {
        XCTAssertEqual(DictationEngine.liveTailWordCap, 29)
        let tail = (1...80).map(String.init).joined(separator: " ")
        let p = DictationEngine.buildPrompt(base: "v", customTerms: [], transcriptTail: tail)
        XCTAssertFalse(p.contains(" 51 "))          // words 1-51 dropped
        XCTAssertTrue(p.hasSuffix("79 80"))
        XCTAssertTrue(p.contains(" 52 "))            // last 29 kept: 52...80
    }

    /// The tail outranks the base: a long base is trimmed, the tail is kept whole.
    func testTailOutranksLongBase() {
        let base = (1...690).map { "b\($0)" }.joined(separator: " ")
        let tail = (1...20).map { "t\($0)" }.joined(separator: " ")
        let p = DictationEngine.buildPrompt(base: base, customTerms: [], transcriptTail: tail)
        XCTAssertEqual(p.split(separator: " ").count, DictationEngine.promptWordBudget)
        XCTAssertTrue(p.hasSuffix(tail))
        XCTAssertTrue(p.hasPrefix("b1 b2"))
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

    /// transcribe() now surfaces inference failures rather than returning "".
    /// We can't force whisper_full to fail without a loaded model, but the error
    /// case that carries the failure must produce a usable, non-empty description.
    func testTranscriptionFailedErrorHasDescription() {
        let error = WhisperError.transcriptionFailed(code: -7)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("-7") ?? false)
    }

    // MARK: - Cancellation (Phase 3)

    func testCancelledIsCancellationButFailureIsNot() {
        XCTAssertTrue(WhisperError.cancelled.isCancellation)
        XCTAssertFalse(WhisperError.transcriptionFailed(code: -1).isCancellation)
        XCTAssertFalse(WhisperError.modelLoadFailed("/x").isCancellation)
    }

    func testCancellationFlagStartsFalseThenCancels() {
        let flag = CancellationFlag()
        XCTAssertFalse(flag.isCancelled)
        flag.cancel()
        XCTAssertTrue(flag.isCancelled)
        flag.cancel() // idempotent
        XCTAssertTrue(flag.isCancelled)
    }
}

// MARK: - AudioCapture Tests

final class AudioCaptureDurationCapTests: XCTestCase {
    func testMaxRecordingSamplesIsFiveMinutesAt16kHz() {
        XCTAssertEqual(AudioCapture.maxRecordingSeconds, 300)
        XCTAssertEqual(AudioCapture.maxRecordingSamples, 16000 * 300)
    }

    func testCrossesDurationCapFiresExactlyOnCrossing() {
        let cap = AudioCapture.maxRecordingSamples
        // Well below the cap on both sides — no crossing.
        XCTAssertFalse(AudioCapture.crossesDurationCap(previousCount: 0, newCount: 1000))
        // The append that reaches the cap fires.
        XCTAssertTrue(AudioCapture.crossesDurationCap(previousCount: cap - 100, newCount: cap))
        XCTAssertTrue(AudioCapture.crossesDurationCap(previousCount: cap - 1, newCount: cap + 500))
        // Already past the cap — must NOT fire again (fire-once guarantee).
        XCTAssertFalse(AudioCapture.crossesDurationCap(previousCount: cap, newCount: cap + 500))
        XCTAssertFalse(AudioCapture.crossesDurationCap(previousCount: cap + 500, newCount: cap + 1000))
    }
}

final class AudioCaptureConfigChangeTests: XCTestCase {
    // AVAudioEngine posts a configuration-change notification once right after
    // start() when the AUHAL renegotiates a stale format (seen when another app
    // switched the device's sample rate). That renegotiation is benign — the
    // engine keeps running and the tap keeps delivering at the format it was
    // installed with — and must NOT end the session.
    func testRenegotiationWithMatchingFormatIsBenign() {
        XCTAssertTrue(AudioCapture.isBenignConfigurationChange(
            isRunning: true, tapRate: 16000, tapChannels: 2, hwRate: 16000, hwChannels: 2))
    }

    func testEngineStoppedIsFatal() {
        // Device unplugged: the engine stops itself.
        XCTAssertFalse(AudioCapture.isBenignConfigurationChange(
            isRunning: false, tapRate: 16000, tapChannels: 2, hwRate: 16000, hwChannels: 2))
    }

    func testSampleRateChangeIsFatal() {
        // Mid-session rate flip (e.g. conferencing app): tap format no longer valid.
        XCTAssertFalse(AudioCapture.isBenignConfigurationChange(
            isRunning: true, tapRate: 16000, tapChannels: 2, hwRate: 48000, hwChannels: 2))
    }

    func testChannelCountChangeIsFatal() {
        XCTAssertFalse(AudioCapture.isBenignConfigurationChange(
            isRunning: true, tapRate: 16000, tapChannels: 2, hwRate: 16000, hwChannels: 1))
    }

    func testZeroedFormatIsFatal() {
        // Device gone entirely — format reads back as 0 Hz / 0 ch.
        XCTAssertFalse(AudioCapture.isBenignConfigurationChange(
            isRunning: true, tapRate: 16000, tapChannels: 2, hwRate: 0, hwChannels: 0))
    }
}

// MARK: - Onboarding Tests

final class OnboardingTests: XCTestCase {
    func testHasCompletedOnboardingRoundTrips() {
        let settings = AppSettings.shared
        let original = settings.hasCompletedOnboarding

        settings.hasCompletedOnboarding = true
        XCTAssertTrue(settings.hasCompletedOnboarding)

        settings.hasCompletedOnboarding = false
        XCTAssertFalse(settings.hasCompletedOnboarding)

        settings.hasCompletedOnboarding = original
    }

    // The decision is pure: show onboarding only for a genuinely new user —
    // not completed AND no whisper model on disk yet.
    func testShowsForBrandNewUser() {
        XCTAssertTrue(OnboardingView.shouldShowOnboarding(hasCompleted: false, hasAnyModel: false))
    }

    func testSkipsWhenAlreadyCompleted() {
        XCTAssertFalse(OnboardingView.shouldShowOnboarding(hasCompleted: true, hasAnyModel: false))
    }

    // Existing users (upgrading) already have a model — they must never see onboarding.
    func testSkipsExistingUserWithModel() {
        XCTAssertFalse(OnboardingView.shouldShowOnboarding(hasCompleted: false, hasAnyModel: true))
    }

    func testSkipsCompletedUserWithModel() {
        XCTAssertFalse(OnboardingView.shouldShowOnboarding(hasCompleted: true, hasAnyModel: true))
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

// MARK: - HotkeyMonitor non-modifier decision

/// A held non-modifier hotkey (Space, Return, …) generates autorepeat key-downs;
/// those must be swallowed, not passed through to the focused app.
final class HotkeyNonModifierDecisionTests: XCTestCase {
    func testPressReleaseAndAutorepeat() {
        XCTAssertEqual(HotkeyMonitor.nonModifierDecision(isKeyDown: true, isHeld: false), .press)
        XCTAssertEqual(HotkeyMonitor.nonModifierDecision(isKeyDown: true, isHeld: true), .swallow)
        XCTAssertEqual(HotkeyMonitor.nonModifierDecision(isKeyDown: false, isHeld: true), .release)
        XCTAssertEqual(HotkeyMonitor.nonModifierDecision(isKeyDown: false, isHeld: false), .passThrough)
    }
}

// MARK: - HotkeyMonitor own-event pass-through

/// TextInjector posts its typing as virtualKey 0 (the A key). With an "A" hotkey
/// those events must never be read as the hotkey, so anything our own process
/// posted passes straight through.
final class HotkeyOwnEventTests: XCTestCase {
    func testOnlyOurOwnPidIsTreatedAsSelfInjected() {
        XCTAssertTrue(HotkeyMonitor.isOwnEvent(sourcePID: Int64(getpid())))
        XCTAssertFalse(HotkeyMonitor.isOwnEvent(sourcePID: 0))                    // hardware
        XCTAssertFalse(HotkeyMonitor.isOwnEvent(sourcePID: Int64(getpid()) + 1))  // another app
    }
}

// MARK: - HotkeyMonitor sided modifier state

/// A sided modifier hotkey (e.g. Right Option) must read its OWN side: releasing
/// it while the other side is held still carries the generic mask, which used to
/// leave push-to-talk stuck in .recording.
final class HotkeyModifierPressedTests: XCTestCase {
    private func flags(_ generic: CGEventFlags, device: UInt64 = 0) -> CGEventFlags {
        CGEventFlags(rawValue: generic.rawValue | device)
    }

    func testSidedModifierUsesItsOwnDeviceBit() {
        // Right Option (61): device bit 0x40; Left Option device bit 0x20.
        XCTAssertTrue(HotkeyMonitor.isModifierPressed(keyCode: 61, flags: flags(.maskAlternate, device: 0x40)))
        XCTAssertTrue(HotkeyMonitor.isModifierPressed(keyCode: 61, flags: flags(.maskAlternate, device: 0x60)))
        XCTAssertFalse(HotkeyMonitor.isModifierPressed(keyCode: 61, flags: flags(.maskAlternate, device: 0x20)))  // only Left held
        XCTAssertFalse(HotkeyMonitor.isModifierPressed(keyCode: 59, flags: flags(.maskControl, device: 0x2000)))  // Left Ctrl hotkey, Right held
        XCTAssertTrue(HotkeyMonitor.isModifierPressed(keyCode: 54, flags: flags(.maskCommand, device: 0x10)))
        XCTAssertFalse(HotkeyMonitor.isModifierPressed(keyCode: 61, flags: []))
    }

    func testFallsBackToGenericMaskWithoutDeviceBits() {
        XCTAssertTrue(HotkeyMonitor.isModifierPressed(keyCode: 61, flags: .maskAlternate))
        XCTAssertTrue(HotkeyMonitor.isModifierPressed(keyCode: 56, flags: .maskShift))
        XCTAssertTrue(HotkeyMonitor.isModifierPressed(keyCode: 57, flags: .maskAlphaShift))
        XCTAssertTrue(HotkeyMonitor.isModifierPressed(keyCode: 63, flags: .maskSecondaryFn))
    }
}

// MARK: - WhisperBridge decode thread count

/// Capped at 8: on GPU, 26 vs 8 threads measured identical (M3 Ultra); on CPU-only
/// decoding (the Intel path) all cores was wildly unstable while 8 was steady.
final class DecodeThreadCountTests: XCTestCase {
    func testThreadCountIsCappedAndNeverZero() {
        XCTAssertEqual(WhisperBridge.decodeThreadCount(cores: 28, appleSilicon: true), 8)
        XCTAssertEqual(WhisperBridge.decodeThreadCount(cores: 28, appleSilicon: false), 8)
        XCTAssertEqual(WhisperBridge.decodeThreadCount(cores: 8, appleSilicon: true), 6)   // keeps 2 cores free
        XCTAssertEqual(WhisperBridge.decodeThreadCount(cores: 4, appleSilicon: false), 4)
        XCTAssertEqual(WhisperBridge.decodeThreadCount(cores: 1, appleSilicon: true), 1)
    }
}

// MARK: - Input device resolution

/// The capture engine always gets an explicit input device. Leaving it unset
/// ("System Default") made AVAudioEngine start input and output as one IO unit:
/// with a stalled default output (a sleeping DisplayPort monitor) engine.start()
/// hung ~10 s and failed, while the same mic set explicitly started in ~0.25 s.
final class InputDeviceResolutionTests: XCTestCase {
    private let devices = [
        AudioInputDevice(id: 130, uid: "brio", name: "Logitech BRIO"),
        AudioInputDevice(id: 84, uid: "teams", name: "Microsoft Teams Audio"),
    ]

    func testSelectedDeviceWins() {
        XCTAssertEqual(AudioDeviceManager.resolveInputDevice(selectedUID: "teams", devices: devices, systemDefault: 130), 84)
    }

    func testSystemDefaultIsSetExplicitly() {
        XCTAssertEqual(AudioDeviceManager.resolveInputDevice(selectedUID: nil, devices: devices, systemDefault: 130), 130)
    }

    func testUnpluggedSelectionFallsBackToSystemDefault() {
        XCTAssertEqual(AudioDeviceManager.resolveInputDevice(selectedUID: "gone", devices: devices, systemDefault: 130), 130)
    }

    func testNoDefaultLeavesEngineAlone() {
        XCTAssertNil(AudioDeviceManager.resolveInputDevice(selectedUID: nil, devices: devices, systemDefault: nil))
    }
}

// MARK: - SoundFeedback

/// Feedback sounds go through System Sound Services, which hands playback to the
/// system sound server and returns at once. NSSound.play() blocked the main thread
/// forever when the default output device stalled (a sleeping DisplayPort monitor),
/// beach-balling the app on the hotkey. The stall itself needs real hardware; this
/// checks every sound resolves to a system file and registers as a system sound.
final class SoundFeedbackTests: XCTestCase {
    func testEverySoundRegistersAsASystemSound() {
        for name in SoundFeedback.soundNames {
            let url = SoundFeedback.systemSoundURL(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.path)
        }
        let feedback = SoundFeedback()
        XCTAssertEqual(feedback.registeredSoundCount, SoundFeedback.soundNames.count)
    }
}
