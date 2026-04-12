import Foundation

final class TextCorrector: @unchecked Sendable {
    static nonisolated(unsafe) let shared = TextCorrector()

    func correct(_ text: String) -> String {
        guard AppSettings.shared.grammarCorrectionEnabled else { return text }
        let startTime = CFAbsoluteTimeGetCurrent()

        var result = text
        if AppSettings.shared.numberConversionEnabled {
            result = convertWordsToNumbers(result)
        }
        result = fixAcronymsAndTerms(result)
        result = fixCapitalization(result)
        result = fixPunctuation(result)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[TextCorrector] \(String(format: "%.1f", elapsed))ms: \"\(text)\" → \"\(result)\"")
        return result
    }

    // MARK: - Pass 0: Number Word → Digit Conversion

    private static let onesMap: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]

    private static let tensMap: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    private static let scaleMap: [String: Int] = [
        "hundred": 100, "thousand": 1_000, "million": 1_000_000,
        "billion": 1_000_000_000, "trillion": 1_000_000_000_000,
    ]

    private static let allNumberWords: Set<String> = {
        var words = Set(onesMap.keys)
        words.formUnion(tensMap.keys)
        words.formUnion(scaleMap.keys)
        words.insert("and") // "one hundred and twenty"
        words.insert("a") // "a hundred", "a thousand"
        return words
    }()

    private func convertWordsToNumbers(_ text: String) -> String {
        let words = text.components(separatedBy: " ")
        var result: [String] = []
        var numberWords: [String] = []

        func flushNumber() {
            guard !numberWords.isEmpty else { return }
            if let value = parseNumberWords(numberWords) {
                // Format with commas for thousands: 1000 → "1,000"
                result.append(formatNumber(value))
            } else {
                result.append(contentsOf: numberWords)
            }
            numberWords.removeAll()
        }

        for word in words {
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if Self.allNumberWords.contains(lower) {
                // "and" only counts as part of a number if we're already in a number sequence
                if lower == "and" && numberWords.isEmpty {
                    flushNumber()
                    result.append(word)
                } else if lower == "a" && numberWords.isEmpty {
                    // "a hundred" = 100 — only if next word could be a scale
                    numberWords.append(word)
                } else {
                    numberWords.append(word)
                }
            } else {
                // "a" followed by non-number word — flush as regular word
                if numberWords.count == 1 && numberWords[0].lowercased() == "a" {
                    result.append(numberWords.removeFirst())
                }
                flushNumber()
                result.append(word)
            }
        }
        flushNumber()

        return result.joined(separator: " ")
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1000 {
            // Add commas: 1000 → "1,000", 1000000 → "1,000,000"
            var s = String(value)
            var i = s.count - 3
            while i > 0 {
                let idx = s.index(s.startIndex, offsetBy: i)
                s.insert(",", at: idx)
                i -= 3
            }
            return s
        }
        return String(value)
    }

    private func parseNumberWords(_ words: [String]) -> Int? {
        let cleaned = words.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0 != "and" }

        guard !cleaned.isEmpty else { return nil }

        // Single word "zero"
        if cleaned.count == 1, cleaned[0] == "zero" { return 0 }

        // Detect digit-by-digit dictation vs compound numbers:
        // "two four six eight" → 2468 (digit sequence)
        // "eighty eighty" → 8080 (digit sequence)
        // BUT "forty two" → 42 (compound — tens followed by ones)
        let hasScaleWord = cleaned.contains { Self.scaleMap[$0] != nil }
        let hasTensOnesCombo = cleaned.count >= 2 && {
            for i in 0..<(cleaned.count - 1) {
                if Self.tensMap[cleaned[i]] != nil,
                   let v = Self.onesMap[cleaned[i + 1]], v >= 1, v <= 9 {
                    return true
                }
            }
            return false
        }()

        if !hasScaleWord && !hasTensOnesCombo && cleaned.count >= 2 {
            let values = cleaned.compactMap { word -> Int? in
                if let v = Self.onesMap[word], v <= 9 { return v }
                if let v = Self.tensMap[word] { return v }
                return nil
            }
            if values.count == cleaned.count {
                let digits = values.map(String.init).joined()
                return Int(digits)
            }
        }

        // Standard number parsing: "three hundred forty two" → 342
        var total = 0
        var current = 0

        for word in cleaned {
            if word == "a" {
                current = 1
            } else if let ones = Self.onesMap[word] {
                current += ones
            } else if let tens = Self.tensMap[word] {
                current += tens
            } else if word == "hundred" {
                current = (current == 0 ? 1 : current) * 100
            } else if let scale = Self.scaleMap[word], scale >= 1000 {
                current = (current == 0 ? 1 : current) * scale
                total += current
                current = 0
            } else {
                return nil // unknown word
            }
        }

        total += current
        return total > 0 ? total : nil
    }

    // MARK: - Pass 1: Acronym & Term Casing

    /// Word-boundary-aware replacement of common dev terms
    private func fixAcronymsAndTerms(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in Self.termPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return result
    }

    // MARK: - Pass 2: Capitalization

    private func fixCapitalization(_ text: String) -> String {
        var result = text

        // Capitalize first character
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }

        // Capitalize after sentence-ending punctuation
        result = capitalizeSentenceStarts(result)

        // Capitalize standalone "i"
        result = result.replacingOccurrences(
            of: "\\b[Ii]\\b(?!')",
            with: "I",
            options: .regularExpression
        )
        // Fix "i'm", "i'll", "i've", "i'd"
        result = result.replacingOccurrences(
            of: "\\bi'([mldvs])",
            with: "I'$1",
            options: .regularExpression
        )

        return result
    }

    private func capitalizeSentenceStarts(_ text: String) -> String {
        var chars = Array(text)
        var capitalizeNext = true

        for i in chars.indices {
            if capitalizeNext && chars[i].isLetter {
                chars[i] = Character(chars[i].uppercased())
                capitalizeNext = false
            } else if ".!?".contains(chars[i]) {
                capitalizeNext = true
            } else if chars[i].isLetter {
                capitalizeNext = false
            }
        }
        return String(chars)
    }

    // MARK: - Pass 3: Punctuation Cleanup

    private func fixPunctuation(_ text: String) -> String {
        var result = text

        // Remove space before punctuation: "hello ." → "hello."
        result = result.replacingOccurrences(
            of: "\\s+([.!?,;:])",
            with: "$1",
            options: .regularExpression
        )

        // Fix double/triple spaces
        result = result.replacingOccurrences(
            of: "\\s{2,}",
            with: " ",
            options: .regularExpression
        )

        // Trim
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add period at end if missing punctuation
        // But not for: short text, numbers, or text already ending with punctuation
        if result.count > 3,
           let last = result.last,
           !".!?,;:\"')".contains(last),
           !last.isNumber {
            result += "."
        }

        return result
    }

    // MARK: - Term Dictionary

    /// Compiled regex patterns for word-boundary-aware term replacement.
    /// Format: (regex pattern, replacement string)
    private static let termPatterns: [(String, String)] = {
        // Terms where the match is case-insensitive and replacement is the correct form
        let upperTerms = [
            // Pure acronyms (all caps)
            "api", "sdk", "cli", "ide", "orm", "cdn", "dns", "ssl", "tls", "ssh",
            "html", "css", "xml", "sql", "jwt", "csv", "pdf", "svg", "png", "jpg",
            "gif", "url", "uri", "http", "https", "ajax", "cors", "csrf", "xss",
            "crud", "rest", "grpc", "tcp", "udp", "ip", "vpn", "ram", "cpu", "gpu",
            "ssd", "hdd", "usb", "hdmi", "json", "yaml", "toml", "uuid", "guid",
            "aws", "gcp", "ecs", "eks", "rds", "sqs", "sns", "iam", "vpc",
            "ec2", "s3", "cdn", "ddos", "dos", "vm", "ci", "cd",
            "tdd", "bdd", "ddd", "mvc", "mvvm", "oop", "fp",
            "rbac", "acl", "sso", "mfa", "saml", "ldap",
            "llm", "gpt", "rag", "nlp", "ml", "ai",
            "ascii", "utf", "hex", "rgb", "hsl",
            "npm", "npx",
        ]

        let mixedCaseTerms: [(String, String)] = [
            // Proper nouns / brand names
            ("javascript", "JavaScript"), ("typescript", "TypeScript"),
            ("python", "Python"), ("golang", "Golang"),
            ("swift", "Swift"), ("swiftui", "SwiftUI"),
            ("kotlin", "Kotlin"), ("java", "Java"),
            ("rust", "Rust"), ("ruby", "Ruby"),
            ("haskell", "Haskell"), ("elixir", "Elixir"),
            ("php", "PHP"), ("perl", "Perl"),
            ("csharp", "C#"), ("fsharp", "F#"),
            ("objective-c", "Objective-C"), ("objectivec", "Objective-C"),

            // Frameworks & tools
            ("react", "React"), ("nextjs", "Next.js"), ("next.js", "Next.js"),
            ("vue", "Vue"), ("angular", "Angular"), ("svelte", "Svelte"),
            ("express", "Express"), ("django", "Django"), ("flask", "Flask"),
            ("fastapi", "FastAPI"), ("nestjs", "NestJS"),
            ("tailwind", "Tailwind"), ("bootstrap", "Bootstrap"),
            ("webpack", "Webpack"), ("vite", "Vite"),
            ("docker", "Docker"), ("kubernetes", "Kubernetes"),
            ("terraform", "Terraform"), ("ansible", "Ansible"),
            ("jenkins", "Jenkins"), ("nginx", "Nginx"),
            ("redis", "Redis"), ("elasticsearch", "Elasticsearch"),
            ("postgresql", "PostgreSQL"), ("postgres", "PostgreSQL"),
            ("mongodb", "MongoDB"), ("mysql", "MySQL"),
            ("sqlite", "SQLite"), ("dynamodb", "DynamoDB"),
            ("firebase", "Firebase"), ("firestore", "Firestore"),
            ("supabase", "Supabase"), ("prisma", "Prisma"),
            ("graphql", "GraphQL"),

            // Platforms & services
            ("github", "GitHub"), ("gitlab", "GitLab"),
            ("bitbucket", "Bitbucket"), ("jira", "Jira"),
            ("heroku", "Heroku"), ("vercel", "Vercel"),
            ("netlify", "Netlify"), ("cloudflare", "Cloudflare"),
            ("datadog", "Datadog"), ("sentry", "Sentry"),
            ("grafana", "Grafana"), ("prometheus", "Prometheus"),

            // Apple
            ("macos", "macOS"), ("ios", "iOS"), ("ipados", "iPadOS"),
            ("watchos", "watchOS"), ("tvos", "tvOS"), ("visionos", "visionOS"),
            ("iphone", "iPhone"), ("ipad", "iPad"), ("macbook", "MacBook"),
            ("xcode", "Xcode"), ("appkit", "AppKit"), ("uikit", "UIKit"),
            ("coregraphics", "CoreGraphics"), ("avfoundation", "AVFoundation"),

            // AI
            ("openai", "OpenAI"), ("anthropic", "Anthropic"),
            ("chatgpt", "ChatGPT"), ("claude", "Claude"),
            ("copilot", "Copilot"), ("hugging face", "Hugging Face"),
            ("pytorch", "PyTorch"), ("tensorflow", "TensorFlow"),

            // Git terms
            ("git", "Git"),

            // Special: CI/CD as a compound
            ("ci/cd", "CI/CD"), ("cicd", "CI/CD"),
            ("devops", "DevOps"),
            ("oauth", "OAuth"),
            ("nosql", "NoSQL"),
            ("webrtc", "WebRTC"),
            ("websocket", "WebSocket"),
        ]

        var patterns: [(String, String)] = []

        // Pure uppercase acronyms
        for term in upperTerms {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
            patterns.append((pattern, term.uppercased()))
        }

        // Mixed case terms
        for (match, replacement) in mixedCaseTerms {
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: match))\\b"
            patterns.append((pattern, replacement))
        }

        return patterns
    }()
}
