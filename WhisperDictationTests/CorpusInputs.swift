import Foundation

/// Representative inputs for the TextCorrector equivalence corpus. Outputs were
/// captured from the pre-Phase-3 (per-pattern `replacingOccurrences`) implementation
/// and are locked in `TextCorrectorEquivalenceTests` so the compiled-regex refactor
/// is provably behavior-preserving.
enum CorpusInputs {
    static let all: [String] = [
        // Acronyms
        "the api returns json",
        "parse the html and css then send over http",
        "the cpu and gpu need more ram",
        "connect via ssh over tcp using tls",
        // Shadowing pairs (longest-first must win)
        "postgres",
        "postgresql",
        "migrate from postgres to postgresql",
        "next.js",
        "nextjs",
        "compare next.js and nextjs",
        "ci/cd",
        "cicd",
        "set up ci/cd and cicd pipelines",
        "run ci then cd",
        // java vs javascript
        "java and javascript",
        "write javascript not java",
        // iphone vs ip
        "my iphone has an ip address",
        "ipad and ipados and ip",
        // Apple stack
        "build for macos using swiftui in xcode",
        "ios and ipados and watchos and tvos and visionos",
        "appkit and uikit and coregraphics and avfoundation",
        // Frameworks / DBs
        "use react with tailwind and vite",
        "deploy docker to kubernetes with terraform",
        "query postgresql mongodb mysql sqlite and redis",
        "graphql and grpc and rest",
        // AI
        "openai and anthropic and claude and chatgpt and copilot",
        "hugging face models with pytorch and tensorflow",
        // Compound / special
        "the devops team owns ci/cd",
        "objective-c and objectivec",
        "csharp and fsharp and golang",
        "oauth and saml and jwt and rbac",
        // Numbers + terms
        "three hundred api calls",
        "i need three hundred megabytes of ram",
        "two thousand five hundred json records",
        "nine one one is the number",
        "forty two microservices",
        // Capitalization / punctuation / contractions
        "i think i should go",
        "i'm going and i'll be back",
        "first sentence. second sentence",
        "hello  world",
        "hello .",
        "is this a test?",
        // Realistic paragraphs
        "so the api gateway forwards json over https to the backend which stores it in postgresql and caches hot keys in redis while the frontend built with react and tailwind fetches data through graphql and the whole thing deploys via docker and cicd to kubernetes with terraform managing the aws vpc",
        "yesterday i debugged a nasty race condition in the swiftui view where the cpu spiked and the gpu stalled so i added a jwt check on the rest api and rewrote the sql query for postgresql then pushed through ci/cd and watched the datadog dashboard for errors while sipping coffee",
    ]

    /// ~50-word realistic paragraph used for the performance assertion.
    static let perfParagraph = all[all.count - 1]
}
