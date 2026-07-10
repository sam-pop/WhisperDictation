import SwiftUI

@main
struct WhisperDictationApp: App {
    @State private var engine = DictationEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine)
        } label: {
            // The label renders at launch (it's the menu bar icon), so it's a reliable
            // place to trigger first-launch onboarding for an LSUIElement app that has
            // no window open at startup.
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)

        Window("WhisperDictation Settings", id: "settings") {
            SettingsView(engine: engine)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Welcome to WhisperDictation", id: "onboarding") {
            OnboardingView(engine: engine)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - Menu Bar Label + Onboarding Trigger

/// Wraps the menu bar icon and, once per launch, decides whether to present onboarding.
/// Lives here (not in MenuBarIcon) so the icon stays a pure presentation view and the
/// trigger has access to `@Environment(\.openWindow)`.
private struct MenuBarLabel: View {
    let engine: DictationEngine
    @Environment(\.openWindow) private var openWindow
    @State private var didEvaluateOnboarding = false

    var body: some View {
        MenuBarIcon(state: engine.state, isHoldingForToggle: engine.isHoldingForToggle)
            .task {
                // Guard against the label view re-appearing: evaluate at most once per launch.
                guard !didEvaluateOnboarding else { return }
                didEvaluateOnboarding = true
                presentOnboardingIfNeeded()
            }
    }

    private func presentOnboardingIfNeeded() {
        let settings = AppSettings.shared
        guard !settings.hasCompletedOnboarding else { return }

        let hasAnyModel = !ModelManager.shared.downloadedModels().isEmpty
        if OnboardingView.shouldShowOnboarding(hasCompleted: settings.hasCompletedOnboarding, hasAnyModel: hasAnyModel) {
            openWindow(id: "onboarding")
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Existing/upgrading user: a model is already installed, so skip the flow
            // and mark complete so this check never runs again.
            settings.hasCompletedOnboarding = true
        }
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
