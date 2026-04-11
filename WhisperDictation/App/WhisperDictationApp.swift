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
            Image(systemName: "mic.fill")
        case .recording:
            Image(systemName: "mic.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red)
        case .processing:
            Image(systemName: "waveform")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.orange)
        case .typing:
            Image(systemName: "keyboard")
        }
    }
}
