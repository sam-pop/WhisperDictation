import SwiftUI

// MARK: - Onboarding

/// First-launch setup: Welcome → Permissions → Model → Done.
/// Presented once for genuinely new users (see `shouldShowOnboarding`). Styled to
/// match SettingsView (cards, gradients, SF Symbols) for a consistent feel.
struct OnboardingView: View {
    let engine: DictationEngine
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var modelManager = ModelManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: Step = .welcome

    /// The tier we recommend to new users: same "Balanced" quantized model SettingsView
    /// promotes — small footprint (181 MB), near-full accuracy.
    private let recommendedModel = ModelManager.ModelInfo.smallEnQ5

    /// Auto-refresh permissions while onboarding is visible so granting Accessibility
    /// in System Settings (which can't be requested in-process) reflects without a manual tap.
    private let permissionTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    enum Step: Int, CaseIterable {
        case welcome, permissions, model, done
    }

    /// Pure decision: show onboarding only for a genuinely new user — one who hasn't
    /// completed it AND has no whisper model on disk. Existing/upgrading users always
    /// have a model, so they skip it entirely.
    static func shouldShowOnboarding(hasCompleted: Bool, hasAnyModel: Bool) -> Bool {
        !hasCompleted && !hasAnyModel
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 22)
                .padding(.bottom, 4)

            Spacer(minLength: 0)

            Group {
                switch step {
                case .welcome: welcomeStep
                case .permissions: permissionsStep
                case .model: modelStep
                case .done: doneStep
                }
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            footer
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
        }
        .frame(width: 620, height: 460)
        .background(colorScheme == .dark ? Color(.windowBackgroundColor) : Color(.controlBackgroundColor).opacity(0.3))
        .onAppear { permissions.checkPermissions() }
        .onReceive(permissionTimer) { _ in
            // Only worth polling while the user is on (or past) the permissions step.
            if step != .welcome { permissions.checkPermissions() }
        }
        .onChange(of: modelManager.activeDownloads[recommendedModel.fileName]) { oldValue, newValue in
            // Download of the recommended model just finished (present → absent) and the
            // file verified onto disk: make it the active model so the engine loads it.
            if oldValue != nil, newValue == nil, modelManager.isModelDownloaded(recommendedModel) {
                activateRecommendedModel()
            }
        }
        .onDisappear {
            // Any dismissal — Get Started, Skip, or the window's close button — ends
            // onboarding for good. Marking complete here guarantees it never re-shows,
            // even if the user closed it without finishing.
            AppSettings.shared.hasCompletedOnboarding = true
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.blue : Color.secondary.opacity(0.25))
                    .frame(width: s == step ? 22 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.8), .blue.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 76, height: 76)
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("Welcome to WhisperDictation")
                    .font(.system(size: 22, weight: .bold))
                Text("Local, private voice-to-text powered by Whisper AI.\nHold a key to speak, release to type — nothing leaves your Mac.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            stepHeading("Grant Permissions", "WhisperDictation needs two permissions to work.")

            VStack(spacing: 12) {
                OnboardingRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Capture your voice for transcription.",
                    isGranted: permissions.microphoneGranted,
                    actionLabel: "Grant Access",
                    colorScheme: colorScheme,
                    action: { permissions.requestMicrophone() }
                )

                OnboardingRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    description: "Global hotkey and typing text at your cursor. macOS only lets you enable this manually in System Settings — the button opens the right pane.",
                    isGranted: permissions.accessibilityGranted,
                    actionLabel: "Open Settings",
                    colorScheme: colorScheme,
                    action: { permissions.openAccessibilitySettings() }
                )
            }

            if !permissions.allPermissionsGranted {
                Text("You can grant these later in Settings — they're just needed before you can dictate.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Model

    private var modelStep: some View {
        VStack(spacing: 16) {
            stepHeading("Download a Model", "This runs entirely offline once downloaded.")

            OnboardingModelCard(
                model: recommendedModel,
                modelManager: modelManager,
                colorScheme: colorScheme
            )

            if let error = modelManager.downloadError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.green.opacity(0.8), .green.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 76, height: 76)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("You're all set")
                    .font(.system(size: 22, weight: .bold))
                Text("Hold your hotkey and start speaking. Fine-tune everything — hotkey, model, vocabulary — anytime from Settings in the menu bar.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Footer (navigation)

    private var footer: some View {
        HStack {
            if step == .welcome {
                Button("Skip setup") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
            } else {
                Button("Back") { goBack() }
                    .controlSize(.large)
            }

            Spacer()

            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button("Get Started") { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .permissions:
            Button("Continue") { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .model:
            Button("Continue") { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                // Require a usable model before finishing so the app isn't left unable to transcribe.
                .disabled(modelManager.activeModelPath() == nil)
        case .done:
            Button("Start Dictating") { finish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    // MARK: - Helpers

    private func stepHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = prev }
    }

    private func activateRecommendedModel() {
        let name = recommendedModel.fileName
            .replacingOccurrences(of: "ggml-", with: "")
            .replacingOccurrences(of: ".bin", with: "")
        AppSettings.shared.selectedModel = name
        engine.reloadModel()
    }

    private func finish() {
        AppSettings.shared.hasCompletedOnboarding = true
        dismiss()
    }
}

// MARK: - Permission Row

private struct OnboardingRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let actionLabel: String
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isGranted
                        ? LinearGradient(colors: [.green.opacity(0.7), .green.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.red.opacity(0.7), .red.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: isGranted ? "checkmark" : icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 18))
            } else {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.blue)
                    .fixedSize()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
            )
    }
}

// MARK: - Model Card

private struct OnboardingModelCard: View {
    let model: ModelManager.ModelInfo
    @ObservedObject var modelManager: ModelManager
    let colorScheme: ColorScheme

    private var isDownloaded: Bool { modelManager.isModelDownloaded(model) }
    private var isDownloading: Bool { modelManager.isDownloading(model) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.7), .blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                Text("🎯")
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text("RECOMMENDED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.blue.opacity(0.15)))
                        .foregroundStyle(.blue)
                }
                if isDownloading {
                    let progress = modelManager.downloadProgress(for: model) ?? 0
                    ProgressView(value: progress)
                        .frame(maxWidth: 220)
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if isDownloaded {
                    Text("Ready — \(model.size), \(model.accuracy.lowercased()) accuracy")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        Label(model.size, systemImage: "internaldrive")
                        Label(model.speed, systemImage: "bolt.fill")
                        Label(model.accuracy, systemImage: "target")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 20))
            } else if isDownloading {
                Button {
                    modelManager.cancelDownload(name: model.fileName)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel download")
            } else {
                Button("Download") {
                    modelManager.startDownload(model)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}
