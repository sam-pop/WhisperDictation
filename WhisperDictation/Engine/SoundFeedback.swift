import AudioToolbox
import Foundation

/// Feedback sounds via System Sound Services: playback is handed to the system
/// sound server and the call returns immediately, from any thread. NSSound.play()
/// blocked its calling thread indefinitely when the default output device stalled
/// (e.g. a sleeping DisplayPort monitor's speakers), beach-balling the app on the
/// hotkey; a stalled device now just means no beep.
final class SoundFeedback {
    static let soundNames = ["Tink", "Pop", "Purr"]   // start, stop, done

    static func systemSoundURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
    }

    /// Registered once; immutable after init.
    private var soundIDs: [String: SystemSoundID] = [:]

    init() {
        for name in Self.soundNames {
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(Self.systemSoundURL(name) as CFURL, &id) == noErr {
                soundIDs[name] = id
            }
        }
    }

    deinit {
        soundIDs.values.forEach { AudioServicesDisposeSystemSoundID($0) }
    }

    var registeredSoundCount: Int { soundIDs.count }

    var isEnabled: Bool {
        AppSettings.shared.soundFeedbackEnabled
    }

    func playStartSound() { play("Tink") }
    func playStopSound() { play("Pop") }
    func playDoneSound() { play("Purr") }

    private func play(_ name: String) {
        guard isEnabled, let id = soundIDs[name] else { return }
        AudioServicesPlaySystemSound(id)
    }
}
