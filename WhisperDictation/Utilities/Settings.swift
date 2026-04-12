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

    // ~500 words — under whisper's 1024 token (~750 word) limit
    static let defaultVocabularyPrompt = """
        Technical software engineering discussion. \
        Languages: JavaScript, TypeScript, Python, Swift, SwiftUI, Rust, Go, Golang, \
        Java, Kotlin, C++, C#, F#, Ruby, PHP, Dart, Scala, Haskell, Elixir, Clojure, \
        Zig, Lua, Objective-C, Perl, COBOL, Fortran, Assembly, WASM, WebAssembly. \
        Frameworks: React, Next.js, Vue, Nuxt, Angular, Svelte, SvelteKit, Remix, \
        Astro, Gatsby, Express, Django, Flask, FastAPI, NestJS, Spring Boot, Rails, \
        Laravel, ASP.NET, Gin, Echo, Fiber, Actix, Rocket, Phoenix, Tailwind, \
        Bootstrap, Material UI, Chakra UI, shadcn, Radix, Headless UI, Storybook. \
        Infrastructure: Docker, Kubernetes, AWS, GCP, Azure, Terraform, Ansible, \
        Pulumi, Nginx, Apache, Caddy, Cloudflare, Vercel, Netlify, Heroku, Railway, \
        Fly.io, Render, Lambda, EC2, S3, CloudFront, ECS, EKS, Fargate, RDS, \
        DynamoDB, SQS, SNS, IAM, VPC, Cloud Run, Cloud Functions, BigQuery. \
        Databases: PostgreSQL, MySQL, SQLite, MongoDB, Redis, Elasticsearch, \
        Cassandra, DynamoDB, Firestore, Firebase, Supabase, PlanetScale, Neon, \
        CockroachDB, Prisma, Drizzle, Sequelize, TypeORM, Mongoose, SQLAlchemy, \
        Knex, Kysely, EdgeDB, SurrealDB, Turso, Upstash. \
        APIs: REST, GraphQL, gRPC, WebSocket, tRPC, OpenAPI, Swagger, Postman, \
        JSON, YAML, XML, protobuf, JWT, OAuth, SAML, CORS, CSRF, webhook, \
        endpoint, middleware, rate limiting, pagination, cursor, offset, idempotent. \
        DevOps: Git, GitHub, GitLab, Bitbucket, CI/CD, GitHub Actions, Jenkins, \
        CircleCI, ArgoCD, Helm, kubectl, Prometheus, Grafana, Datadog, Sentry, \
        PagerDuty, container, pod, replica set, deployment, ingress, namespace, \
        artifact, staging, production, canary, blue-green, rollback, hotfix, \
        feature flag, environment variable, secret, load balancer, reverse proxy, \
        API gateway, service mesh, uptime, latency, throughput, SLA, SLO, SLI. \
        Tools: npm, yarn, pnpm, Bun, Deno, Node.js, Webpack, Vite, Rollup, \
        esbuild, SWC, Babel, ESLint, Prettier, Biome, Cargo, pip, Poetry, uv, \
        CocoaPods, Swift Package Manager, Gradle, Maven, homebrew, apt, Turborepo, \
        Nx, Lerna, Changesets, Husky, lint-staged, commitlint. \
        Frontend: tooltip, dropdown, popover, modal, dialog, sidebar, navbar, \
        breadcrumb, carousel, accordion, checkbox, toggle, slider, pagination, \
        skeleton, spinner, toast, snackbar, avatar, badge, chip, tag, tabs, \
        responsive, viewport, breakpoint, flexbox, grid, z-index, opacity, \
        hover, focus, blur, onClick, onChange, onSubmit, useState, useEffect, \
        useRef, useMemo, useCallback, useContext, useReducer, custom hook, \
        SSR, SSG, ISR, hydration, lazy loading, code splitting, tree shaking, \
        bundler, minify, transpile, polyfill, CSS-in-JS, styled-components, \
        SVG, canvas, WebGL, animation, transition, keyframe, media query, \
        accessibility, ARIA, screen reader, semantic HTML, SEO, meta tags, \
        localStorage, sessionStorage, IndexedDB, service worker, PWA, \
        dark mode, light mode, theme, design system, design tokens, Figma. \
        Backend: controller, route, handler, resolver, schema, migration, seed, \
        ORM, query builder, connection pool, transaction, caching, Redis cache, \
        authentication, authorization, session, cookie, token, RBAC, ACL, SSO, MFA, \
        cron job, queue, worker, pub/sub, event-driven, message broker, RabbitMQ, \
        Kafka, NATS, logging, monitoring, tracing, OpenTelemetry, health check, \
        graceful shutdown, retry, circuit breaker, backoff, dead letter queue. \
        Concepts: API, SDK, CLI, IDE, async, await, promise, callback, closure, \
        mutex, semaphore, thread, coroutine, actor, channel, stream, observable, \
        microservice, monolith, serverless, edge function, CDN, \
        HTTP, HTTPS, TCP, UDP, DNS, SSL, TLS, SSH, SMTP, FTP, \
        pull request, merge, rebase, cherry-pick, squash, commit, branch, tag, \
        unit test, integration test, end-to-end test, TDD, BDD, mock, stub, spy, \
        snapshot test, regression, coverage, assertion, fixture, \
        function, class, struct, enum, protocol, interface, component, module, \
        generic, template, trait, mixin, decorator, annotation, abstract, \
        singleton, factory, observer, strategy, adapter, facade, proxy, \
        big O, algorithm, data structure, hash map, linked list, binary tree, \
        recursion, memoization, dynamic programming, sorting, searching. \
        AI: LLM, GPT, Claude, OpenAI, Anthropic, Hugging Face, Ollama, \
        PyTorch, TensorFlow, MLX, ONNX, Whisper, Stable Diffusion, DALL-E, \
        Midjourney, Copilot, RAG, embedding, vector, inference, fine-tuning, \
        tokenizer, attention, transformer, prompt engineering, agent, tool use. \
        Editors: Xcode, VS Code, IntelliJ, Vim, Neovim, Emacs, JetBrains, \
        terminal, shell, bash, zsh, fish, tmux, iTerm, PowerShell, \
        regex, cron, sed, awk, grep, curl, wget, jq, yq.
        """
}
