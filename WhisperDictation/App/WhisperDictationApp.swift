import SwiftUI

@main
struct WhisperDictationApp: App {
    @State private var engine = DictationEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine)
        } label: {
            MenuBarIcon(state: engine.state, isHoldingForToggle: engine.isHoldingForToggle)
        }
        .menuBarExtraStyle(.window)

        Window("WhisperDictation Settings", id: "settings") {
            SettingsView(engine: engine)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

struct MenuBarIcon: View {
    let state: DictationState
    let isHoldingForToggle: Bool

    var body: some View {
        if isHoldingForToggle {
            // Pulsing dotted ring: visual confirmation the toggle hold is being registered.
            Image(systemName: "circle.dotted")
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, options: .repeating)
        } else {
            switch state {
            case .idle:
                Image(systemName: "waveform.badge.mic")
            case .recording:
                Image(systemName: "mic.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            case .processing:
                Image(systemName: "brain.head.profile.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.orange)
            case .typing:
                Image(systemName: "text.cursor")
            }
        }
    }
}
