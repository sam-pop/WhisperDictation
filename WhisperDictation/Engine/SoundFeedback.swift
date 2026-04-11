import AppKit

final class SoundFeedback {
    private var startSound: NSSound?
    private var stopSound: NSSound?
    private var doneSound: NSSound?

    init() {
        // Use system sounds for now — can be replaced with custom sounds later
        startSound = NSSound(named: "Tink")
        stopSound = NSSound(named: "Pop")
        doneSound = NSSound(named: "Purr")
    }

    var isEnabled: Bool {
        AppSettings.shared.soundFeedbackEnabled
    }

    func playStartSound() {
        guard isEnabled else { return }
        startSound?.stop()
        startSound?.play()
    }

    func playStopSound() {
        guard isEnabled else { return }
        stopSound?.stop()
        stopSound?.play()
    }

    func playDoneSound() {
        guard isEnabled else { return }
        doneSound?.stop()
        doneSound?.play()
    }
}
