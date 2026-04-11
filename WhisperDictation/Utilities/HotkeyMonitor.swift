import Cocoa
import CoreGraphics

final class HotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void

    private var monitoredKeyCode: CGKeyCode {
        CGKeyCode(AppSettings.shared.hotkeyKeyCode)
    }

    /// Whether the monitored key is a modifier (Option, Control, Shift, Command, Fn, Caps Lock)
    private var isModifierKey: Bool {
        let code = Int(monitoredKeyCode)
        return [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code)
    }

    private var isKeyHeld = false

    init(onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
    }

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil else { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleEvent(type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let eventTap else {
            print("Failed to create event tap. Is Accessibility permission granted?")
            Unmanaged<HotkeyMonitor>.fromOpaque(selfPtr).release()
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if isModifierKey {
            // Modifier keys use flagsChanged events
            if type == .flagsChanged && keyCode == monitoredKeyCode {
                let flags = event.flags
                let isPressed = isModifierPressed(flags)
                if isPressed && !isKeyHeld {
                    isKeyHeld = true
                    DispatchQueue.main.async { self.onKeyDown() }
                    return nil
                } else if !isPressed && isKeyHeld {
                    isKeyHeld = false
                    DispatchQueue.main.async { self.onKeyUp() }
                    return nil
                }
            }
        } else {
            // Regular keys use keyDown/keyUp events
            if keyCode == monitoredKeyCode {
                if type == .keyDown && !isKeyHeld {
                    isKeyHeld = true
                    DispatchQueue.main.async { self.onKeyDown() }
                    return nil
                } else if type == .keyUp && isKeyHeld {
                    isKeyHeld = false
                    DispatchQueue.main.async { self.onKeyUp() }
                    return nil
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func isModifierPressed(_ flags: CGEventFlags) -> Bool {
        let code = Int(monitoredKeyCode)
        switch code {
        case 58, 61: return flags.contains(.maskAlternate)   // Option keys
        case 59, 62: return flags.contains(.maskControl)     // Control keys
        case 56, 60: return flags.contains(.maskShift)       // Shift keys
        case 54, 55: return flags.contains(.maskCommand)     // Command keys
        case 57:     return flags.contains(.maskAlphaShift)  // Caps Lock
        case 63:     return flags.contains(.maskSecondaryFn) // Fn
        default:     return false
        }
    }
}
