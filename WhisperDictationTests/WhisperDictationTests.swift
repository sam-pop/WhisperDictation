import XCTest
@testable import WhisperDictation

// MARK: - Settings Tests

final class AppSettingsTests: XCTestCase {
    func testDefaultHotkey() {
        let settings = AppSettings.shared
        XCTAssertEqual(settings.hotkeyKeyCode, 61, "Default hotkey should be right Option (keycode 61)")
    }

    func testDefaultModel() {
        let settings = AppSettings.shared
        XCTAssertEqual(settings.selectedModel, "small.en")
    }

    func testSoundFeedbackDefault() {
        let settings = AppSettings.shared
        XCTAssertTrue(settings.soundFeedbackEnabled)
    }

    func testMinimumRecordingDuration() {
        let settings = AppSettings.shared
        XCTAssertEqual(settings.minimumRecordingDuration, 0.3)
    }

    func testVocabularyPromptNotEmpty() {
        let settings = AppSettings.shared
        XCTAssertFalse(settings.vocabularyPrompt.isEmpty)
        XCTAssertTrue(settings.vocabularyPrompt.contains("API"))
        XCTAssertTrue(settings.vocabularyPrompt.contains("JSON"))
    }

    func testDefaultVocabularyPrompt() {
        XCTAssertTrue(AppSettings.defaultVocabularyPrompt.contains("Technical software engineering"))
        XCTAssertTrue(AppSettings.defaultVocabularyPrompt.contains("SwiftUI"))
        XCTAssertTrue(AppSettings.defaultVocabularyPrompt.contains("TypeScript"))
    }

    func testGrammarCorrectionDefault() {
        XCTAssertTrue(AppSettings.shared.grammarCorrectionEnabled)
    }

    func testNumberConversionDefault() {
        XCTAssertTrue(AppSettings.shared.numberConversionEnabled)
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
        // 3 quantized + 3 full precision = 6
        XCTAssertEqual(ModelManager.ModelInfo.all.count, 6)
    }

    func testRecommendedModelsCount() {
        XCTAssertEqual(ModelManager.ModelInfo.recommended.count, 3)
    }

    func testModelInfoNames() {
        let names = ModelManager.ModelInfo.all.map(\.name)
        XCTAssertTrue(names.contains("Base (English)"))
        XCTAssertTrue(names.contains("Small (English)"))
        XCTAssertTrue(names.contains("Medium (English)"))
        XCTAssertTrue(names.contains("Base Q5 (English)"))
        XCTAssertTrue(names.contains("Small Q5 (English)"))
        XCTAssertTrue(names.contains("Medium Q5 (English)"))
    }

    func testModelsDirectoryExists() {
        let manager = ModelManager.shared
        let dir = manager.modelsDirectory
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
    }
}

// MARK: - DictationEngine Tests

final class DictationEngineTests: XCTestCase {
    func testInitialState() {
        let engine = DictationEngine()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertTrue(engine.lastTranscription.isEmpty)
    }
}

// MARK: - WhisperBridge Tests

final class WhisperBridgeTests: XCTestCase {
    func testInvalidModelPathThrows() {
        XCTAssertThrowsError(try WhisperBridge(modelPath: "/nonexistent/model.bin")) { error in
            XCTAssertTrue(error is WhisperError)
        }
    }
}
