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
            let utf16 = Array(text.utf16)
            let chunkSize = 16
            var offset = 0

            while offset < utf16.count {
                let end = min(offset + chunkSize, utf16.count)
                let chunk = Array(utf16[offset..<end])

                guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                    offset = end
                    continue
                }

                chunk.withUnsafeBufferPointer { ptr in
                    keyDown.keyboardSetUnicodeString(stringLength: Int(chunk.count), unicodeString: ptr.baseAddress)
                    keyUp.keyboardSetUnicodeString(stringLength: Int(chunk.count), unicodeString: ptr.baseAddress)
                }

                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)

                offset = end

                if offset < utf16.count {
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
        }
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
