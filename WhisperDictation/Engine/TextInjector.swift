import CoreGraphics
import Foundation

final class TextInjector {
    private let source: CGEventSource?

    init() {
        source = CGEventSource(stateID: .hidSystemState)
    }

    func type(text: String) {
        // Use CGEvent to type Unicode text at the current cursor position.
        // We process the text in chunks using keyboardSetUnicodeString
        // which can handle up to ~20 UTF-16 code units per event.
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

            // Small delay between chunks for reliability
            if offset < utf16.count {
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
    }
}
