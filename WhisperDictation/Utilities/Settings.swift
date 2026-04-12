import Foundation

final class AppSettings: ObservableObject, @unchecked Sendable {
    static nonisolated(unsafe) let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key: String {
        case hotkeyKeyCode
        case selectedModel
        case soundFeedbackEnabled
        case vocabularyPrompt
        case launchAtLogin
        case minimumRecordingDuration
        case grammarCorrectionEnabled
        case selectedAudioDeviceUID
        case numberConversionEnabled
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

    var grammarCorrectionEnabled: Bool {
        get { defaults.object(forKey: Key.grammarCorrectionEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.grammarCorrectionEnabled.rawValue); objectWillChange.send() }
    }

    var numberConversionEnabled: Bool {
        get { defaults.object(forKey: Key.numberConversionEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.numberConversionEnabled.rawValue); objectWillChange.send() }
    }

    /// nil means "use system default"
    var selectedAudioDeviceUID: String? {
        get { defaults.string(forKey: Key.selectedAudioDeviceUID.rawValue) }
        set { defaults.set(newValue, forKey: Key.selectedAudioDeviceUID.rawValue); objectWillChange.send() }
    }

    // MARK: - Default Vocabulary Prompt

    // Must stay under ~200 words to avoid whisper's 1024 token limit
    static let defaultVocabularyPrompt = """
        Technical programming discussion. \
        API, SDK, CLI, JSON, YAML, REST, GraphQL, gRPC, WebSocket, HTTP, HTTPS, \
        JavaScript, TypeScript, Python, Swift, SwiftUI, Rust, Go, Java, Kotlin, C++, \
        React, Next.js, Vue, Angular, Express, Django, FastAPI, Tailwind, \
        Docker, Kubernetes, AWS, GCP, Azure, Terraform, Nginx, Vercel, Cloudflare, \
        PostgreSQL, MongoDB, Redis, Firebase, Supabase, Prisma, MySQL, SQLite, \
        Git, GitHub, CI/CD, GitHub Actions, npm, Webpack, Vite, ESLint, \
        JWT, OAuth, SSL, TLS, SSH, DNS, CDN, TCP, UDP, \
        async, await, middleware, endpoint, webhook, microservice, serverless, \
        LLM, GPT, Claude, OpenAI, Anthropic, PyTorch, TensorFlow, Whisper, \
        Xcode, VS Code, terminal, bash, zsh, regex, curl, \
        function, class, struct, enum, interface, component, module, \
        pull request, merge, rebase, commit, branch, deploy, refactor.
        """
}
