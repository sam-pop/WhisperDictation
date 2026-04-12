import CoreGraphics
import Foundation

final class TextInjector {
    private let source: CGEventSource?
    private let typingQueue = DispatchQueue(label: "com.whisperdictation.typing", qos: .userInteractive)

    init() {
        source = CGEventSource(stateID: .hidSystemState)
    }

    /// Type text at the current cursor position via CGEvent.
    /// Runs on a dedicated serial queue — safe to call from any thread.
    /// Blocks until all text is typed.
    func type(text: String) {
        typingQueue.sync {
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
}
