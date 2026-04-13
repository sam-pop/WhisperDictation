import Cocoa
import CoreGraphics
import os

final class HotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelfPtr: UnsafeMutableRawPointer?
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void
    private let lock = os_unfair_lock_t.allocate(capacity: 1)

    private var monitoredKeyCode: CGKeyCode {
        CGKeyCode(AppSettings.shared.hotkeyKeyCode)
    }

    private var isModifierKey: Bool {
        let code = Int(monitoredKeyCode)
        return [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code)
    }

    private var isKeyHeld = false

    init(onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        stop()
        lock.deallocate()
    }

    func start() {
        guard eventTap == nil else { return }
        fputs("[HotkeyMonitor] Starting... keyCode=\(monitoredKeyCode) isModifier=\(isModifierKey)\n", stderr)

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
            fputs("[HotkeyMonitor] FAILED to create event tap! Grant Accessibility permission in System Settings.\n", stderr)
            Unmanaged<HotkeyMonitor>.fromOpaque(selfPtr).release()
            return
        }

        fputs("[HotkeyMonitor] Event tap created successfully\n", stderr)
        retainedSelfPtr = selfPtr

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        // Watchdog: macOS silently disables taps when Accessibility permission is stale.
        // Schedule explicitly on main run loop to guarantee it fires.
        startTapWatchdog()
    }

    private var watchdogTimer: Timer?

    private func startTapWatchdog() {
        watchdogTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                fputs("[HotkeyMonitor] Event tap was disabled by macOS! Re-enabling...\n", stderr)
                CGEvent.tapEnable(tap: tap, enable: true)
                // The tap was disabled — any in-flight key-down without its key-up
                // would leave isKeyHeld stuck true, blocking the next press. Reset.
                os_unfair_lock_lock(self.lock)
                self.isKeyHeld = false
                os_unfair_lock_unlock(self.lock)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    func stop() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
        if let ptr = retainedSelfPtr {
            Unmanaged<HotkeyMonitor>.fromOpaque(ptr).release()
            retainedSelfPtr = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if isModifierKey {
            if type == .flagsChanged && keyCode == monitoredKeyCode {
                let flags = event.flags
                let isPressed = isModifierPressed(flags)
                os_unfair_lock_lock(lock)
                let wasHeld = isKeyHeld
                if isPressed && !wasHeld {
                    isKeyHeld = true
                    os_unfair_lock_unlock(lock)
                    DispatchQueue.main.async { self.onKeyDown() }
                    return nil
                } else if !isPressed && wasHeld {
                    isKeyHeld = false
                    os_unfair_lock_unlock(lock)
                    DispatchQueue.main.async { self.onKeyUp() }
                    return nil
                }
                os_unfair_lock_unlock(lock)
            }
        } else {
            if keyCode == monitoredKeyCode {
                os_unfair_lock_lock(lock)
                let wasHeld = isKeyHeld
                if type == .keyDown && !wasHeld {
                    isKeyHeld = true
                    os_unfair_lock_unlock(lock)
                    DispatchQueue.main.async { self.onKeyDown() }
                    return nil
                } else if type == .keyUp && wasHeld {
                    isKeyHeld = false
                    os_unfair_lock_unlock(lock)
                    DispatchQueue.main.async { self.onKeyUp() }
                    return nil
                }
                os_unfair_lock_unlock(lock)
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func isModifierPressed(_ flags: CGEventFlags) -> Bool {
        let code = Int(monitoredKeyCode)
        switch code {
        case 58, 61: return flags.contains(.maskAlternate)
        case 59, 62: return flags.contains(.maskControl)
        case 56, 60: return flags.contains(.maskShift)
        case 54, 55: return flags.contains(.maskCommand)
        case 57:     return flags.contains(.maskAlphaShift)
        case 63:     return flags.contains(.maskSecondaryFn)
        default:     return false
        }
    }
}
