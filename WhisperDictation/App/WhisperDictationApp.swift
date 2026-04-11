import SwiftUI

@main
struct WhisperDictationApp: App {
    @State private var engine = DictationEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine)
        } label: {
            MenuBarIcon(state: engine.state)
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

    var body: some View {
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
