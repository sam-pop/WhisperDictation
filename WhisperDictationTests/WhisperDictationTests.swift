import XCTest
@testable import WhisperDictation

final class SettingsTests: XCTestCase {
    func testDefaultSettings() {
        let settings = AppSettings.shared
        XCTAssertEqual(settings.hotkeyKeyCode, 61) // Right Option
        XCTAssertEqual(settings.selectedModel, "small.en")
        XCTAssertTrue(settings.soundFeedbackEnabled)
        XCTAssertEqual(settings.minimumRecordingDuration, 0.3)
        XCTAssertFalse(settings.vocabularyPrompt.isEmpty)
    }

    func testModelManagerPaths() {
        let manager = ModelManager.shared
        XCTAssertFalse(manager.modelsDirectory.path.isEmpty)
        XCTAssertTrue(ModelManager.ModelInfo.all.count == 3)
    }
}

final class DictationStateTests: XCTestCase {
    func testStateValues() {
        XCTAssertEqual(DictationState.idle.rawValue, "idle")
        XCTAssertEqual(DictationState.recording.rawValue, "recording")
        XCTAssertEqual(DictationState.processing.rawValue, "processing")
        XCTAssertEqual(DictationState.typing.rawValue, "typing")
    }
}
