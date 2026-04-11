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
        Technical software engineering discussion. \
        Languages: JavaScript, TypeScript, Python, Swift, SwiftUI, Rust, Go, Golang, \
        Java, Kotlin, C++, Ruby, PHP, Dart, Scala, Haskell, Elixir, Clojure, Zig, Lua, \
        Objective-C, C#, F#. \
        Frameworks: React, Next.js, Vue, Angular, Svelte, Express, Django, Flask, FastAPI, \
        Spring Boot, Rails, Laravel, ASP.NET, NestJS, Remix, Nuxt, Astro, SvelteKit, Gatsby, \
        Tailwind, Bootstrap, Material UI, Chakra UI, shadcn. \
        Infrastructure: Docker, Kubernetes, AWS, GCP, Azure, Terraform, Ansible, Pulumi, \
        Nginx, Apache, Caddy, Cloudflare, Vercel, Netlify, Heroku, Railway, Fly.io, \
        Lambda, EC2, S3, CloudFront, ECS, EKS, Fargate, RDS, DynamoDB, SQS, SNS, \
        Cloud Run, Cloud Functions, BigQuery, Pub/Sub. \
        Databases: PostgreSQL, MySQL, SQLite, MongoDB, Redis, Elasticsearch, Cassandra, \
        DynamoDB, Firestore, Firebase, Supabase, PlanetScale, Neon, CockroachDB, \
        Prisma, Drizzle, Sequelize, TypeORM, Mongoose, SQLAlchemy. \
        APIs: REST, GraphQL, gRPC, WebSocket, tRPC, OpenAPI, Swagger, Postman, \
        JSON, YAML, XML, protobuf, JWT, OAuth, SAML, CORS, CSRF, webhook, \
        endpoint, middleware, rate limiting, pagination, cursor, offset. \
        DevOps: Git, GitHub, GitLab, Bitbucket, CI/CD, GitHub Actions, Jenkins, \
        CircleCI, Travis CI, ArgoCD, Helm, kubectl, Prometheus, Grafana, Datadog, \
        Sentry, PagerDuty, Terraform, CloudFormation, Ansible, Chef, Puppet. \
        Tools: npm, yarn, pnpm, Bun, Deno, Node.js, Webpack, Vite, Rollup, esbuild, \
        SWC, Babel, ESLint, Prettier, Biome, Cargo, pip, Poetry, uv, CocoaPods, \
        Swift Package Manager, Gradle, Maven, homebrew, apt, dnf. \
        Concepts: API, SDK, CLI, IDE, ORM, OOP, SOLID, DRY, KISS, YAGNI, \
        async, await, promise, callback, closure, mutex, semaphore, deadlock, \
        thread, coroutine, goroutine, actor, channel, stream, observable, \
        microservice, monolith, serverless, edge function, CDN, \
        dependency injection, inversion of control, singleton, factory, observer, \
        pub/sub, event-driven, message queue, CQRS, event sourcing, \
        REST API, CRUD, HTTP, HTTPS, TCP, UDP, DNS, SSL, TLS, SSH, \
        load balancer, reverse proxy, service mesh, API gateway, \
        container, pod, replica set, deployment, ingress, namespace, \
        CI/CD pipeline, pull request, merge, rebase, cherry-pick, \
        branch, commit, push, pull, fetch, clone, fork, stash, \
        unit test, integration test, end-to-end test, mock, stub, fixture, \
        TDD, BDD, assertion, coverage, snapshot test, regression, \
        linting, formatting, type checking, static analysis, \
        refactor, technical debt, code review, pair programming, \
        agile, sprint, standup, retrospective, backlog, epic, story, \
        function, variable, parameter, argument, return, class, struct, \
        enum, protocol, interface, component, module, package, import, \
        export, namespace, generic, template, trait, mixin, decorator, \
        annotation, attribute, macro, pragma, directive, \
        array, list, map, set, dictionary, hash, tuple, queue, stack, \
        tree, graph, linked list, heap, trie, bloom filter, \
        sort, search, traverse, recursive, iterative, memoize, \
        big O, complexity, algorithm, data structure, design pattern, \
        authentication, authorization, encryption, hashing, salting, \
        RBAC, ACL, SSO, MFA, two-factor, TOTP, session, token, cookie, \
        XSS, CSRF, SQL injection, OWASP, vulnerability, CVE, \
        machine learning, neural network, transformer, LLM, GPT, Claude, \
        embedding, vector, RAG, fine-tuning, inference, training, \
        prompt engineering, tokenizer, attention, softmax, \
        Anthropic, OpenAI, Hugging Face, PyTorch, TensorFlow, MLX, ONNX, \
        Whisper, Stable Diffusion, DALL-E, Midjourney, Copilot, \
        Xcode, VS Code, IntelliJ, Vim, Neovim, Emacs, JetBrains, \
        terminal, shell, bash, zsh, fish, PowerShell, iTerm, tmux, \
        regex, cron, sed, awk, grep, curl, wget, jq, yq, \
        localhost, port, socket, bind, listen, ping, traceroute, \
        base64, UTF-8, Unicode, ASCII, hex, binary, octal, \
        Boolean, integer, float, double, string, char, byte, null, nil, \
        undefined, NaN, infinity, void, optional, nullable, \
        camelCase, PascalCase, snake_case, kebab-case, SCREAMING_CASE.
        """
}
