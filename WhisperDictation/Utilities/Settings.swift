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

    // ~250 words — stays under whisper's 1024 token limit
    static let defaultVocabularyPrompt = """
        Technical software engineering discussion. \
        Languages: JavaScript, TypeScript, Python, Swift, SwiftUI, Rust, Go, Golang, \
        Java, Kotlin, C++, Ruby, PHP, Dart, Haskell, Elixir, Objective-C, C#. \
        Frameworks: React, Next.js, Vue, Angular, Svelte, Express, Django, Flask, \
        FastAPI, NestJS, Tailwind, Bootstrap, Spring Boot, Rails, Laravel. \
        Infrastructure: Docker, Kubernetes, AWS, GCP, Azure, Terraform, Ansible, \
        Nginx, Cloudflare, Vercel, Netlify, Heroku, Lambda, EC2, S3, ECS, EKS, \
        Cloud Run, Cloud Functions. \
        Databases: PostgreSQL, MySQL, SQLite, MongoDB, Redis, Elasticsearch, \
        DynamoDB, Firestore, Firebase, Supabase, Prisma, Drizzle. \
        APIs: REST, GraphQL, gRPC, WebSocket, tRPC, OpenAPI, JSON, YAML, XML, \
        protobuf, JWT, OAuth, CORS, CSRF, webhook, endpoint, middleware. \
        DevOps: Git, GitHub, GitLab, CI/CD, GitHub Actions, Jenkins, Helm, \
        Prometheus, Grafana, Datadog, Sentry. \
        Tools: npm, yarn, pnpm, Bun, Deno, Node.js, Webpack, Vite, esbuild, \
        ESLint, Prettier, Cargo, pip, Poetry, CocoaPods, homebrew. \
        Concepts: API, SDK, CLI, IDE, ORM, async, await, promise, callback, \
        closure, mutex, thread, microservice, serverless, CDN, \
        HTTP, HTTPS, TCP, UDP, DNS, SSL, TLS, SSH, \
        container, pod, deployment, ingress, CI/CD pipeline, \
        pull request, merge, rebase, commit, branch, deploy, refactor, \
        unit test, integration test, TDD, mock, coverage, \
        function, class, struct, enum, protocol, interface, component, module. \
        UI: tooltip, dropdown, popover, modal, sidebar, navbar, breadcrumb, \
        carousel, accordion, checkbox, toggle, slider, pagination, skeleton, \
        responsive, viewport, breakpoint, flexbox, grid, z-index, opacity, \
        hover, focus, blur, onClick, onChange, onSubmit, useState, useEffect. \
        AI: LLM, GPT, Claude, OpenAI, Anthropic, Hugging Face, \
        PyTorch, TensorFlow, MLX, Whisper, RAG, embedding, inference, \
        Xcode, VS Code, IntelliJ, Vim, Neovim, terminal, bash, zsh.
        """
}
