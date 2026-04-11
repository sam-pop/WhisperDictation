import Foundation

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key: String {
        case hotkeyKeyCode
        case selectedModel
        case soundFeedbackEnabled
        case vocabularyPrompt
        case launchAtLogin
        case minimumRecordingDuration
    }

    // MARK: - Properties

    var hotkeyKeyCode: Int {
        get { defaults.object(forKey: Key.hotkeyKeyCode.rawValue) as? Int ?? 61 } // 61 = right Option
        set { defaults.set(newValue, forKey: Key.hotkeyKeyCode.rawValue); objectWillChange.send() }
    }

    var selectedModel: String {
        get { defaults.string(forKey: Key.selectedModel.rawValue) ?? "small.en" }
        set { defaults.set(newValue, forKey: Key.selectedModel.rawValue); objectWillChange.send() }
    }

    var soundFeedbackEnabled: Bool {
        get { defaults.object(forKey: Key.soundFeedbackEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.soundFeedbackEnabled.rawValue); objectWillChange.send() }
    }

    var vocabularyPrompt: String {
        get {
            defaults.string(forKey: Key.vocabularyPrompt.rawValue) ?? Self.defaultVocabularyPrompt
        }
        set { defaults.set(newValue, forKey: Key.vocabularyPrompt.rawValue); objectWillChange.send() }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin.rawValue) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin.rawValue); objectWillChange.send() }
    }

    var minimumRecordingDuration: Double {
        get { defaults.object(forKey: Key.minimumRecordingDuration.rawValue) as? Double ?? 0.3 }
        set { defaults.set(newValue, forKey: Key.minimumRecordingDuration.rawValue); objectWillChange.send() }
    }

    // MARK: - Default Vocabulary Prompt

    static let defaultVocabularyPrompt = """
        Technical programming discussion. Code, API, SDK, CLI, JSON, YAML, REST, \
        GraphQL, React, SwiftUI, TypeScript, Python, Docker, Kubernetes, Git, \
        GitHub, npm, async, await, middleware, endpoint, webhook, PostgreSQL, \
        MongoDB, Firebase, deployment, refactor, dependency, repository, \
        function, variable, parameter, argument, return, class, struct, enum, \
        protocol, interface, component, module, package, import, export.
        """
}
