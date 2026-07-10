import XCTest
@testable import WhisperDictation

// MARK: - TextInjector UTF-16 chunking (Phase 5)

/// The chunking math is extracted as a pure static so the surrogate-pair boundary
/// rule is testable without CGEvent. A split surrogate pair would post a lone high
/// surrogate then a lone low surrogate — macOS renders that as replacement glyphs.
final class TextInjectorChunkingTests: XCTestCase {
    private let highSurrogates: ClosedRange<UInt16> = 0xD800...0xDBFF

    private func assertNoSplitPairs(_ chunks: [[UInt16]], line: UInt = #line) {
        for i in chunks.indices where i < chunks.count - 1 {
            if let last = chunks[i].last {
                XCTAssertFalse(highSurrogates.contains(last),
                    "chunk \(i) ends with a high surrogate — its low half is in the next chunk", line: line)
            }
        }
    }

    func testEmptyProducesNoChunks() {
        XCTAssertEqual(TextInjector.chunks(of: []), [])
    }

    func testExactlyMaxIsOneChunk() {
        let units = [UInt16](repeating: 0x41, count: 16)
        XCTAssertEqual(TextInjector.chunks(of: units), [units])
    }

    func testOneOverMaxSplitsIntoTwo() {
        let units = [UInt16](repeating: 0x41, count: 17)
        let chunks = TextInjector.chunks(of: units)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 16)
        XCTAssertEqual(chunks[1].count, 1)
        XCTAssertEqual(chunks.flatMap { $0 }, units)
    }

    func testDoubleMaxIsTwoFullChunks() {
        let units = [UInt16](repeating: 0x41, count: 32)
        let chunks = TextInjector.chunks(of: units)
        XCTAssertEqual(chunks.map(\.count), [16, 16])
    }

    /// Emoji straddling the 16-unit boundary (high surrogate at index 15, low at 16)
    /// MUST NOT be split. Expect the pair pushed whole into the next chunk.
    func testSurrogatePairNotSplitAtBoundary() {
        let text = String(repeating: "a", count: 15) + "😀" // 15 + 2 = 17 UTF-16 units
        let units = Array(text.utf16)
        XCTAssertEqual(units.count, 17)
        let chunks = TextInjector.chunks(of: units)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 15)
        XCTAssertEqual(chunks[1], Array("😀".utf16)) // whole pair pushed to next chunk
        assertNoSplitPairs(chunks)
    }

    /// Pair fully inside the first chunk (boundary lands after it) is left alone.
    func testSurrogatePairFullyInsideChunkIsNotDisturbed() {
        let text = String(repeating: "a", count: 16) + "😀" // pair at indices 16,17
        let chunks = TextInjector.chunks(of: Array(text.utf16))
        XCTAssertEqual(chunks[0].count, 16)
        XCTAssertEqual(chunks[1], Array("😀".utf16))
        assertNoSplitPairs(chunks)
    }

    func testAllEmojiReconstructsAndNeverSplits() {
        let text = String(repeating: "😀", count: 10) // 20 UTF-16 units, all pairs
        let units = Array(text.utf16)
        let chunks = TextInjector.chunks(of: units)
        XCTAssertEqual(chunks.flatMap { $0 }, units) // no bytes lost or duplicated
        assertNoSplitPairs(chunks)
        // Reassembled string is identical (no replacement chars introduced).
        XCTAssertEqual(String(utf16CodeUnits: chunks.flatMap { $0 }, count: units.count), text)
    }

    func testMixedTextReconstructs() {
        let text = "abc😀def👨‍👩‍👧ghi🎯🎯jklmnopqrstuv😀"
        let units = Array(text.utf16)
        let chunks = TextInjector.chunks(of: units)
        XCTAssertEqual(chunks.flatMap { $0 }, units)
        assertNoSplitPairs(chunks)
        XCTAssertEqual(String(utf16CodeUnits: chunks.flatMap { $0 }, count: units.count), text)
    }
}

// MARK: - KeyCodeNames single-source labels (Phase 5)

/// Locks the merged keycode→label table against the exact labels the three former
/// hand-written maps produced (SettingsView recorder, preset pills, MenuBarView).
final class KeyCodeNamesTests: XCTestCase {

    /// Descriptive labels — verbatim from the old HotkeyRecorder.keyName switch.
    func testDescriptiveLabelsMatchOldRecorder() {
        let expected: [Int: String] = [
            61: "⌥  Right Option", 58: "⌥  Left Option",
            59: "⌃  Left Control", 62: "⌃  Right Control",
            63: "Fn",
            56: "⇧  Left Shift", 60: "⇧  Right Shift",
            55: "⌘  Left Command", 54: "⌘  Right Command",
            57: "⇪  Caps Lock",
            36: "↩  Return", 49: "␣  Space", 53: "⎋  Escape", 48: "⇥  Tab",
        ]
        for (code, label) in expected {
            XCTAssertEqual(KeyCodeNames.descriptiveLabel(for: code), label, "code \(code)")
        }
    }

    /// Short labels — verbatim from the old MenuBarView.hotkeyLabel switch (modifiers).
    func testShortLabelsMatchOldMenuBar() {
        let expected: [Int: String] = [
            61: "R⌥", 58: "L⌥", 59: "L⌃", 62: "R⌃", 63: "Fn",
            56: "L⇧", 60: "R⇧", 55: "L⌘", 54: "R⌘",
        ]
        for (code, label) in expected {
            XCTAssertEqual(KeyCodeNames.shortLabel(for: code), label, "code \(code)")
        }
    }

    func testShortLabelUnknownFallsBackToKey() {
        XCTAssertEqual(KeyCodeNames.shortLabel(for: 999), "key")
    }

    func testDescriptiveLabelUnknownUsesFallbackThenKeyN() {
        XCTAssertEqual(KeyCodeNames.descriptiveLabel(for: 999), "Key 999")
        XCTAssertEqual(KeyCodeNames.descriptiveLabel(for: 999, layoutFallback: { _ in "Z" }), "Z")
    }

    /// Preset pills — verbatim order and labels from the old presetKeys array.
    func testPresetsMatchOldPresetKeys() {
        let expected: [(Int, String)] = [
            (61, "Right ⌥"), (58, "Left ⌥"), (62, "Right ⌃"), (59, "Left ⌃"), (63, "Fn"),
        ]
        XCTAssertEqual(KeyCodeNames.presets.count, expected.count)
        for (preset, exp) in zip(KeyCodeNames.presets, expected) {
            XCTAssertEqual(preset.code, exp.0)
            XCTAssertEqual(preset.pill, exp.1)
        }
    }

    func testModifierClassification() {
        for code in 54...63 {
            XCTAssertTrue(KeyCodeNames.isModifier(code), "code \(code) should be a modifier")
        }
        for code in [0, 36, 48, 49, 53, 65, 999] {
            XCTAssertFalse(KeyCodeNames.isModifier(code), "code \(code) should not be a modifier")
        }
    }
}

// MARK: - ModelInfo.settingsId single-source id derivation (Phase 5)

final class ModelSettingsIdTests: XCTestCase {
    func testSettingsIdStripsPrefixAndSuffix() {
        XCTAssertEqual(ModelManager.ModelInfo.smallEnQ5.settingsId, "small.en-q5_1")
        XCTAssertEqual(ModelManager.ModelInfo.smallEn.settingsId, "small.en")
        XCTAssertEqual(ModelManager.ModelInfo.baseEn.settingsId, "base.en")
        XCTAssertEqual(ModelManager.ModelInfo.mediumEnQ5.settingsId, "medium.en-q5_0")
    }

    /// The default persisted selectedModel ("small.en") must resolve to a catalog model.
    func testDefaultSelectedModelIdIsInCatalog() {
        XCTAssertTrue(ModelManager.ModelInfo.all.contains { $0.settingsId == "small.en" })
    }
}

// MARK: - Bundle.appVersion helper (Phase 5)

final class AppInfoTests: XCTestCase {
    func testAppVersionNeverEmpty() {
        // Falls back to "1.0" when the host bundle has no CFBundleShortVersionString.
        XCTAssertFalse(Bundle.main.appVersion.isEmpty)
    }
}

// MARK: - Term-casing drift guard (Phase 5)

/// TextCorrector's casing map and the default vocabulary prompt are maintained
/// separately (full single-sourcing is impossible: the map carries alias spellings
/// like "postgres"→"PostgreSQL" with no display-form preimage, and the prompt is a
/// curated superset). This guard at least prevents the two from disagreeing on the
/// casing of a shared brand term.
final class TermDataDriftTests: XCTestCase {
    func testCanonicalTermCasingConsistentWithVocabularyPrompt() {
        let prompt = AppSettings.defaultVocabularyPrompt
        let lowerPrompt = prompt.lowercased()
        for term in TextCorrector.canonicalDisplayTerms {
            // Skip short/punctuated terms to avoid substring false positives in the
            // case-insensitive membership probe (they carry low drift risk anyway).
            guard term.count >= 4, term.allSatisfy({ $0.isLetter || $0.isNumber }) else { continue }
            guard lowerPrompt.contains(term.lowercased()) else { continue } // prompt omits it
            XCTAssertTrue(prompt.contains(term),
                "Vocabulary prompt spells '\(term)' with casing different from TextCorrector")
        }
    }

    func testCanonicalDisplayTermsAreDeduped() {
        let terms = TextCorrector.canonicalDisplayTerms
        XCTAssertEqual(Set(terms).count, terms.count)
        // Sanity: a couple of known brand casings are present.
        XCTAssertTrue(terms.contains("PostgreSQL"))
        XCTAssertTrue(terms.contains("SwiftUI"))
    }
}
