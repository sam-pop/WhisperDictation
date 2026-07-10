import XCTest
@testable import WhisperDictation

/// Golden-master equivalence test for the TextCorrector term-casing refactor
/// (Phase 3). Expected values were captured from the pre-refactor implementation
/// (per-pattern `replacingOccurrences(options: .regularExpression)`) and are locked
/// here so the compiled-regex rewrite is provably behavior-preserving.
///
/// NOTE: some expected outputs contain quirks that live in passes NOT touched by the
/// refactor (e.g. "Next.Js" — the sentence-capitalizer treats "." in "Next.js" as a
/// sentence end; "IPad"/"IOS" — sentence-start capitalization overrides brand casing).
/// They are locked deliberately: the refactor must not change them.
final class TextCorrectorEquivalenceTests: XCTestCase {
    private static let expected: [String] = [
        "The API returns JSON.",
        "Parse the HTML and CSS then send over HTTP.",
        "The CPU and GPU need more RAM.",
        "Connect via SSH over TCP using TLS.",
        "PostgreSQL.",
        "PostgreSQL.",
        "Migrate from PostgreSQL to PostgreSQL.",
        "Next.Js.",
        "Next.Js.",
        "Compare Next.Js and Next.Js.",
        "CI/CD.",
        "CI/CD.",
        "Set up CI/CD and CI/CD pipelines.",
        "Run CI then CD.",
        "Java and JavaScript.",
        "Write JavaScript not Java.",
        "My iPhone has an IP address.",
        "IPad and iPadOS and IP.",
        "Build for macOS using SwiftUI in Xcode.",
        "IOS and iPadOS and watchOS and tvOS and visionOS.",
        "AppKit and UIKit and CoreGraphics and AVFoundation.",
        "Use React with Tailwind and Vite.",
        "Deploy Docker to Kubernetes with Terraform.",
        "Query PostgreSQL MongoDB MySQL SQLite and Redis.",
        "GraphQL and GRPC and REST.",
        "OpenAI and Anthropic and Claude and ChatGPT and Copilot.",
        "Hugging Face models with PyTorch and TensorFlow.",
        "The DevOps team owns CI/CD.",
        "Objective-C and Objective-C.",
        "C# and F# and Golang.",
        "OAuth and SAML and JWT and RBAC.",
        "300 API calls.",
        "I need 300 megabytes of RAM.",
        "2,500 JSON records.",
        "911 Is the number.",
        "42 Microservices.",
        "I think I should go.",
        "I'm going and I'll be back.",
        "First sentence. Second sentence.",
        "Hello world.",
        "Hello.",
        "Is this a test?",
        "So the API gateway forwards JSON over HTTPS to the backend which stores it in PostgreSQL and caches hot keys in Redis while the frontend built with React and Tailwind fetches data through GraphQL and the whole thing deploys via Docker and CI/CD to Kubernetes with Terraform managing the AWS VPC.",
        "Yesterday I debugged a nasty race condition in the SwiftUI view where the CPU spiked and the GPU stalled so I added a JWT check on the REST API and rewrote the SQL query for PostgreSQL then pushed through CI/CD and watched the Datadog dashboard for errors while sipping coffee.",
    ]

    /// Runs the body with grammar + number conversion on and no custom terms,
    /// restoring the user's real settings afterward.
    private func withHermeticSettings(_ body: () -> Void) {
        let s = AppSettings.shared
        let g = s.grammarCorrectionEnabled, n = s.numberConversionEnabled, c = s.customTerms
        defer { s.grammarCorrectionEnabled = g; s.numberConversionEnabled = n; s.customTerms = c }
        s.grammarCorrectionEnabled = true
        s.numberConversionEnabled = true
        s.customTerms = []
        body()
    }

    func testCorpusEquivalence() {
        XCTAssertEqual(CorpusInputs.all.count, Self.expected.count, "corpus/expected length mismatch")
        withHermeticSettings {
            for (i, input) in CorpusInputs.all.enumerated() {
                XCTAssertEqual(TextCorrector.shared.correct(input), Self.expected[i], "input #\(i): \"\(input)\"")
            }
        }
    }

    // MARK: Explicit shadowing guards (called out in the Phase 3 plan)

    func testPostgresNotShadowedByPostgresql() {
        withHermeticSettings {
            XCTAssertEqual(TextCorrector.shared.correct("postgresql"), "PostgreSQL.")
            XCTAssertEqual(TextCorrector.shared.correct("postgres"), "PostgreSQL.")
        }
    }

    func testNextDotJsLiteralDotHandled() {
        withHermeticSettings {
            // Both spellings collapse to the same term output (then the sentence
            // capitalizer upper-cases the letter after the dot — locked quirk).
            XCTAssertEqual(TextCorrector.shared.correct("next.js"), "Next.Js.")
            XCTAssertEqual(TextCorrector.shared.correct("nextjs"), "Next.Js.")
        }
    }

    // MARK: Performance

    /// A full `correct()` pass over a ~50-word realistic paragraph must be well under
    /// 5ms. Assert < 20ms to stay clear of CI scheduling variance.
    func testCorrectPerformanceUnderBudget() {
        withHermeticSettings {
            let paragraph = CorpusInputs.perfParagraph
            // Warm caches (first regex compile) outside the timed region.
            _ = TextCorrector.shared.correct(paragraph)

            let iterations = 50
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<iterations {
                _ = TextCorrector.shared.correct(paragraph)
            }
            let msPerCall = (CFAbsoluteTimeGetCurrent() - start) * 1000 / Double(iterations)
            XCTAssertLessThan(msPerCall, 20.0, "correct() averaged \(String(format: "%.3f", msPerCall))ms/call")
        }
    }

    /// XCTest baseline metric (informational; no hard gate — `measure` has no budget API).
    func testCorrectMeasuredBaseline() {
        let paragraph = CorpusInputs.perfParagraph
        measure { _ = TextCorrector.shared.correct(paragraph) }
    }
}
