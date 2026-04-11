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
        XCTAssertTrue(AppSettings.defaultVocabularyPrompt.contains("Technical programming"))
        XCTAssertTrue(AppSettings.defaultVocabularyPrompt.contains("SwiftUI"))
        XCTAssertTrue(AppSettings.defaultVocabularyPrompt.contains("TypeScript"))
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
        XCTAssertEqual(ModelManager.ModelInfo.all.count, 3)
    }

    func testModelInfoNames() {
        let names = ModelManager.ModelInfo.all.map(\.name)
        XCTAssertTrue(names.contains("Base (English)"))
        XCTAssertTrue(names.contains("Small (English)"))
        XCTAssertTrue(names.contains("Medium (English)"))
    }

    func testModelInfoFileNames() {
        let files = ModelManager.ModelInfo.all.map(\.fileName)
        XCTAssertTrue(files.contains("ggml-base.en.bin"))
        XCTAssertTrue(files.contains("ggml-small.en.bin"))
        XCTAssertTrue(files.contains("ggml-medium.en.bin"))
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
