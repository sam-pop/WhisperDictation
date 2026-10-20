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
        KeyCodeNames.isModifier(Int(monitoredKeyCode))
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
                // The tap was disabled — any in-flight key-down lost its key-up event.
                // Reset isKeyHeld so the next press is accepted, AND synthesize the missed
                // key-up so DictationEngine can recover (otherwise it stays stuck in
                // .recording for push-to-talk, or in `isHoldingForToggle = true` with a
                // pending work item for toggle mode).
                os_unfair_lock_lock(self.lock)
                let wasHeld = self.isKeyHeld
                self.isKeyHeld = false
                os_unfair_lock_unlock(self.lock)
                if wasHeld {
                    DispatchQueue.main.async { self.onKeyUp() }
                }
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

    enum NonModifierDecision: Equatable { case press, release, swallow, passThrough }

    /// What a key-down/up of a NON-modifier hotkey does. A held key autorepeats
    /// key-downs; those are swallowed so they never reach the focused app.
    static func nonModifierDecision(isKeyDown: Bool, isHeld: Bool) -> NonModifierDecision {
        switch (isKeyDown, isHeld) {
        case (true, false): return .press
        case (true, true): return .swallow
        case (false, true): return .release
        case (false, false): return .passThrough
        }
    }

    /// True for events our own process posted. TextInjector types as virtualKey 0
    /// (the A key), so with an "A" hotkey our typing would otherwise be swallowed
    /// as hotkey presses and cancel the transcription it belongs to.
    static func isOwnEvent(sourcePID: Int64) -> Bool {
        sourcePID == Int64(getpid())
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if Self.isOwnEvent(sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID)) {
            return Unmanaged.passRetained(event)
        }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if isModifierKey {
            if type == .flagsChanged && keyCode == monitoredKeyCode {
                let flags = event.flags
                let isPressed = Self.isModifierPressed(keyCode: Int(monitoredKeyCode), flags: flags)
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
            if keyCode == monitoredKeyCode, type == .keyDown || type == .keyUp {
                os_unfair_lock_lock(lock)
                let decision = Self.nonModifierDecision(isKeyDown: type == .keyDown, isHeld: isKeyHeld)
                switch decision {
                case .press: isKeyHeld = true
                case .release: isKeyHeld = false
                case .swallow, .passThrough: break
                }
                os_unfair_lock_unlock(lock)
                switch decision {
                case .press:
                    DispatchQueue.main.async { self.onKeyDown() }
                    return nil
                case .release:
                    DispatchQueue.main.async { self.onKeyUp() }
                    return nil
                case .swallow:
                    return nil
                case .passThrough:
                    break
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    /// Device-dependent (sided) modifier bits, IOKit's NX_DEVICE*KEYMASK values:
    /// this key's own bit, and both sides of its family.
    private static let sidedModifierBits: [Int: (own: UInt64, family: UInt64)] = [
        58: (0x20, 0x60), 61: (0x40, 0x60),        // L/R Option
        59: (0x01, 0x2001), 62: (0x2000, 0x2001),  // L/R Control
        56: (0x02, 0x06), 60: (0x04, 0x06),        // L/R Shift
        55: (0x08, 0x18), 54: (0x10, 0x18),        // L/R Command
    ]

    /// Whether the modifier hotkey `keyCode` is down in a flagsChanged event.
    /// Sided keys read their own device bit: the generic mask stays set while the
    /// OTHER side is held, so releasing the hotkey then was never seen. Sources
    /// that report no device bits for the family fall back to the generic mask.
    static func isModifierPressed(keyCode code: Int, flags: CGEventFlags) -> Bool {
        if let bits = sidedModifierBits[code], flags.rawValue & bits.family != 0 {
            return flags.rawValue & bits.own != 0
        }
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
