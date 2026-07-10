import CoreGraphics
import Foundation

/// @unchecked Sendable: the only stored state is an immutable `CGEventSource?` and
/// a serial `DispatchQueue`. All typing runs on that queue; no mutable shared state.
final class TextInjector: @unchecked Sendable {
    private let source: CGEventSource?
    private let typingQueue = DispatchQueue(label: "com.whisperdictation.typing", qos: .userInteractive)

    init() {
        source = CGEventSource(stateID: .hidSystemState)
    }

    /// Enqueue `text` to be typed at the current cursor position via CGEvent.
    /// Returns immediately — the actual typing happens asynchronously on a dedicated
    /// serial queue, so callers (e.g. the whisper decode thread delivering segments)
    /// are never blocked by the per-chunk `Thread.sleep`. The serial queue preserves
    /// submission order, so segments are typed in the order they were decoded.
    /// Call `flush()` to wait for all enqueued typing to finish.
    func type(text: String) {
        typingQueue.async { [source] in
            let chunks = Self.chunks(of: Array(text.utf16))

            for (i, chunk) in chunks.enumerated() {
                guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                    continue
                }

                chunk.withUnsafeBufferPointer { ptr in
                    keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: ptr.baseAddress)
                    keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: ptr.baseAddress)
                }

                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)

                if i < chunks.count - 1 {
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
        }
    }

    /// Split a UTF-16 buffer into chunks of at most `maxChunk` code units for
    /// `keyboardSetUnicodeString`, **never splitting a surrogate pair across a chunk
    /// boundary**. A split pair would post a lone high surrogate followed by a lone low
    /// surrogate, which macOS renders as replacement characters instead of the intended
    /// emoji/astral glyph. Pure and static so the boundary math is unit-testable
    /// without CGEvent.
    static func chunks(of utf16: [UInt16], maxChunk: Int = 16) -> [[UInt16]] {
        guard maxChunk > 0 else { return utf16.isEmpty ? [] : [utf16] }
        var result: [[UInt16]] = []
        var offset = 0
        while offset < utf16.count {
            var end = min(offset + maxChunk, utf16.count)
            // If the last unit of this chunk is a high surrogate and a unit follows it
            // (its low surrogate), the pair straddles the boundary — back off by one so
            // the whole pair lands in the next chunk. The `end - 1 > offset` guard keeps
            // the chunk non-empty so progress is guaranteed even for pathological input.
            if end < utf16.count, Self.isHighSurrogate(utf16[end - 1]), end - 1 > offset {
                end -= 1
            }
            result.append(Array(utf16[offset..<end]))
            offset = end
        }
        return result
    }

    private static func isHighSurrogate(_ unit: UInt16) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }

    /// Barrier that blocks the caller until all previously-enqueued typing has
    /// finished. Because `typingQueue` is serial, a `sync {}` submitted after all the
    /// `async` type() work runs only once that work drains. MUST NOT be called on the
    /// main actor (it blocks). Intended to be called once, from the detached
    /// transcription task, before the done sound / return to idle.
    func flush() {
        typingQueue.sync {}
    }
}
