import SwiftUI
import Carbon.HIToolbox

// MARK: - Settings Window

struct SettingsView: View {
    let engine: DictationEngine
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @State private var selectedSection: SettingsSection = .general
    @Environment(\.colorScheme) private var colorScheme

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case model = "Model"
        case vocabulary = "Vocabulary"
        case permissions = "Permissions"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: "gearshape.fill"
            case .model: "brain.head.profile.fill"
            case .vocabulary: "text.book.closed.fill"
            case .permissions: "lock.shield.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailPane
        }
        .frame(width: 620, height: 460)
        .background(colorScheme == .dark ? Color(.windowBackgroundColor) : Color(.controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)

            ForEach(SettingsSection.allCases) { section in
                SidebarRow(
                    title: section.rawValue,
                    icon: section.icon,
                    isSelected: selectedSection == section,
                    colorScheme: colorScheme
                )
                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { selectedSection = section } }
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(engine.isModelLoaded ? .green : .orange)
                    .frame(width: 7, height: 7)
                Text(engine.isModelLoaded ? "Ready" : "Loading...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 170)
        .background(
            colorScheme == .dark
                ? Color.black.opacity(0.15)
                : Color(.windowBackgroundColor)
        )
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedSection.rawValue)
                    .font(.system(size: 20, weight: .bold))
                    .padding(.bottom, 16)

                switch selectedSection {
                case .general:
                    GeneralSection(settings: settings, engine: engine, colorScheme: colorScheme)
                case .model:
                    ModelSection(settings: settings, modelManager: modelManager, engine: engine, colorScheme: colorScheme)
                case .vocabulary:
                    VocabularySection(settings: settings, colorScheme: colorScheme)
                case .permissions:
                    PermissionsSection(permissions: permissions, colorScheme: colorScheme)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    isSelected
                        ? AnyShapeStyle(LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                : nil
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Card

private struct SettingsCard<Content: View>: View {
    let colorScheme: ColorScheme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }
}

private struct CardHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - General Section

private struct GeneralSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var audioDevices: AudioDeviceManager = .shared
    let engine: DictationEngine
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(colorScheme: colorScheme) {
                CardHeader("Push-to-Talk", subtitle: "Hold key to record, release to transcribe")
                HotkeyRecorder(keyCode: $settings.hotkeyKeyCode, colorScheme: colorScheme)
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader("Microphone", subtitle: "Audio input device for recording")
                Picker("Input device", selection: Binding(
                    get: { settings.selectedAudioDeviceUID ?? "" },
                    set: { settings.selectedAudioDeviceUID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System Default").tag("")
                    ForEach(audioDevices.inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .font(.system(size: 13))
                .onAppear { audioDevices.refreshDevices() }
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader("Preferences")
                Toggle("Auto-correct grammar & formatting", isOn: $settings.grammarCorrectionEnabled)
                    .font(.system(size: 13))
                Toggle("Convert number words to digits", isOn: $settings.numberConversionEnabled)
                    .font(.system(size: 13))
                Toggle("Sound feedback", isOn: $settings.soundFeedbackEnabled)
                    .font(.system(size: 13))
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .font(.system(size: 13))
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        LaunchAtLoginHelper.setEnabled(newValue)
                    }
            }
        }
    }
}

// MARK: - Hotkey Recorder

private struct HotkeyRecorder: View {
    @Binding var keyCode: Int
    let colorScheme: ColorScheme
    @State private var isRecording = false
    @State private var eventMonitors: [Any] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Keycap display
            Button(action: { toggleRecording() }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                isRecording
                                    ? LinearGradient(colors: [.blue, .blue.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [Color.white.opacity(0.12), Color.white.opacity(0.06)]
                                            : [Color.white, Color(.controlBackgroundColor)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isRecording ? Color.blue.opacity(0.5) : (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 1, y: 1)
                            .frame(height: 38)

                        if isRecording {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 6, height: 6)
                                    .opacity(0.8)
                                Text("Press any key...")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        } else {
                            Text(keyName(for: keyCode))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                    }

                    if !isRecording {
                        Text("Click to change")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Quick pick pills
            HStack(spacing: 6) {
                ForEach(presetKeys, id: \.code) { preset in
                    Button {
                        keyCode = preset.code
                        stopRecording()
                    } label: {
                        Text(preset.name)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(keyCode == preset.code
                                        ? Color.blue.opacity(0.15)
                                        : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(keyCode == preset.code ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                            .foregroundStyle(keyCode == preset.code ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            keyCode = Int(event.keyCode)
            stopRecording()
            return nil
        }
        let flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            let code = Int(event.keyCode)
            if [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code) {
                keyCode = code
                stopRecording()
            }
            return nil
        }
        if let keyMonitor { eventMonitors.append(keyMonitor) }
        if let flagsMonitor { eventMonitors.append(flagsMonitor) }
    }

    private func stopRecording() {
        isRecording = false
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        eventMonitors.removeAll()
    }

    private var presetKeys: [(name: String, code: Int)] {
        [("Right ⌥", 61), ("Left ⌥", 58), ("Right ⌃", 62), ("Left ⌃", 59), ("Fn", 63)]
    }

    private func keyName(for code: Int) -> String {
        switch code {
        case 61: return "⌥  Right Option"
        case 58: return "⌥  Left Option"
        case 59: return "⌃  Left Control"
        case 62: return "⌃  Right Control"
        case 63: return "Fn"
        case 56: return "⇧  Left Shift"
        case 60: return "⇧  Right Shift"
        case 55: return "⌘  Left Command"
        case 54: return "⌘  Right Command"
        case 57: return "⇪  Caps Lock"
        case 36: return "↩  Return"
        case 49: return "␣  Space"
        case 53: return "⎋  Escape"
        case 48: return "⇥  Tab"
        default:
            if let name = keyCodeToString(code) { return name }
            return "Key \(code)"
        }
    }

    private func keyCodeToString(_ code: Int) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        let layout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0
        let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                     UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                     &deadKeyState, chars.count, &length, &chars)
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

// MARK: - Model Section

private struct ModelSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var modelManager: ModelManager
    let engine: DictationEngine
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            // Recommended quantized models
            CardHeader("Recommended (Quantized)", subtitle: "Smaller, faster, near-identical accuracy")

            ForEach(ModelManager.ModelInfo.recommended) { model in
                modelCard(model)
            }

            // VAD model
            CardHeader("Voice Activity Detection", subtitle: "Trims silence for faster inference (2 MB)")

            let vadDownloaded = modelManager.isModelDownloaded(ModelManager.ModelInfo.vadSilero)
            SettingsCard(colorScheme: colorScheme) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.cyan.opacity(0.7), .cyan.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                        Image(systemName: "waveform.path")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Silero VAD")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Auto-trims silence before transcription")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if vadDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 18))
                    } else if modelManager.isDownloading {
                        ProgressView(value: modelManager.downloadProgress)
                            .frame(width: 60)
                    } else {
                        Button("Download") {
                            Task { try? await modelManager.downloadModel(.vadSilero) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // Full precision models (collapsible)
            DisclosureGroup {
                VStack(spacing: 10) {
                    ForEach([ModelManager.ModelInfo.baseEn, .smallEn, .mediumEn]) { model in
                        modelCard(model)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Full Precision Models")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let error = modelManager.downloadError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func modelCard(_ model: ModelManager.ModelInfo) -> some View {
        let isSelected = isModelSelected(model)
        let isDownloaded = modelManager.isModelDownloaded(model)

        SettingsCard(colorScheme: colorScheme) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tierGradient(for: model))
                        .frame(width: 36, height: 36)
                    Text(tierEmoji(for: model))
                        .font(.system(size: 16))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.name)
                            .font(.system(size: 13, weight: .semibold))
                        if model.isQuantized {
                            Text("Q5")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.3)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.orange.opacity(0.15)))
                                .foregroundStyle(.orange)
                        }
                        if isSelected {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.5)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.green.opacity(0.15)))
                                .foregroundStyle(.green)
                        }
                    }
                    HStack(spacing: 12) {
                        Label(model.size, systemImage: "internaldrive")
                        Label(model.speed, systemImage: "bolt.fill")
                        Label(model.accuracy, systemImage: "target")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if isDownloaded {
                    if !isSelected {
                        Button("Activate") {
                            let name = model.fileName
                                .replacingOccurrences(of: "ggml-", with: "")
                                .replacingOccurrences(of: ".bin", with: "")
                            settings.selectedModel = name
                            engine.reloadModel()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.blue)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 18))
                    }
                } else if modelManager.isDownloading {
                    ProgressView(value: modelManager.downloadProgress)
                        .frame(width: 60)
                } else {
                    Button("Download") {
                        Task { try? await modelManager.downloadModel(model) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func isModelSelected(_ model: ModelManager.ModelInfo) -> Bool {
        let modelKey = model.fileName
            .replacingOccurrences(of: "ggml-", with: "")
            .replacingOccurrences(of: ".bin", with: "")
        return settings.selectedModel == modelKey
    }

    private func tierGradient(for model: ModelManager.ModelInfo) -> LinearGradient {
        switch model.fileName {
        case let f where f.contains("base"): return LinearGradient(colors: [.green.opacity(0.7), .green.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case let f where f.contains("small"): return LinearGradient(colors: [.blue.opacity(0.7), .blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default: return LinearGradient(colors: [.purple.opacity(0.7), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func tierEmoji(for model: ModelManager.ModelInfo) -> String {
        switch model.fileName {
        case let f where f.contains("base"): return "⚡"
        case let f where f.contains("small"): return "🎯"
        default: return "🧠"
        }
    }

    private func tierSpeed(for model: ModelManager.ModelInfo) -> String {
        switch model.fileName {
        case let f where f.contains("base"): return "Fastest"
        case let f where f.contains("small"): return "Balanced"
        default: return "Most accurate"
        }
    }
}

// MARK: - Vocabulary Section

private struct VocabularySection: View {
    @ObservedObject var settings: AppSettings
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(colorScheme: colorScheme) {
                CardHeader("Developer Vocabulary", subtitle: "Bias Whisper toward recognizing these terms")
                TextEditor(text: $settings.vocabularyPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color(.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 0.5)
                    )

                HStack {
                    Text("Add project-specific terms for better recognition")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Reset") {
                        settings.vocabularyPrompt = AppSettings.defaultVocabularyPrompt
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Permissions Section

private struct PermissionsSection: View {
    @ObservedObject var permissions: PermissionManager
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            PermissionCard(
                icon: "mic.fill",
                title: "Microphone",
                description: "Capture your voice for transcription",
                isGranted: permissions.microphoneGranted,
                colorScheme: colorScheme,
                action: { permissions.requestMicrophone() },
                actionLabel: "Grant Access"
            )

            PermissionCard(
                icon: "hand.raised.fill",
                title: "Accessibility",
                description: "Global hotkey and text injection at cursor",
                isGranted: permissions.accessibilityGranted,
                colorScheme: colorScheme,
                action: { permissions.openAccessibilitySettings() },
                actionLabel: "Open Settings"
            )

            Button {
                permissions.checkPermissions()
            } label: {
                Label("Refresh Permissions", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let colorScheme: ColorScheme
    let action: () -> Void
    let actionLabel: String

    var body: some View {
        SettingsCard(colorScheme: colorScheme) {
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
                }

                Spacer()

                if !isGranted {
                    Button(actionLabel, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.blue)
                }
            }
        }
    }
}
