import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    let engine: DictationEngine
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var permissions = PermissionManager.shared

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralTab(settings: settings, engine: engine)
            }
            Tab("Model", systemImage: "brain") {
                ModelTab(settings: settings, modelManager: modelManager, engine: engine)
            }
            Tab("Vocabulary", systemImage: "text.book.closed") {
                VocabularyTab(settings: settings)
            }
            Tab("Permissions", systemImage: "lock.shield") {
                PermissionsTab(permissions: permissions)
            }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    let engine: DictationEngine

    var body: some View {
        Form {
            Section("Push-to-Talk Hotkey") {
                HotkeyRecorder(keyCode: $settings.hotkeyKeyCode)
                Text("Hold this key to record, release to transcribe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Audio") {
                Toggle("Sound feedback", isOn: $settings.soundFeedbackEnabled)
            }

            Section("System") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        LaunchAtLoginHelper.setEnabled(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Hotkey Recorder

private struct HotkeyRecorder: View {
    @Binding var keyCode: Int
    @State private var isRecording = false
    @State private var eventMonitors: [Any] = []

    var body: some View {
        HStack {
            Text("Key:")
            Spacer()

            Button(action: { toggleRecording() }) {
                Text(isRecording ? "Press any key..." : keyName(for: keyCode))
                    .frame(minWidth: 140)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isRecording ? Color.accentColor.opacity(0.2) : Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color(.separatorColor), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onDisappear { stopRecording() }
        }

        if isRecording {
            Text("Press the key you want to use, or click the button to cancel")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        HStack(spacing: 8) {
            Text("Quick pick:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(presetKeys, id: \.code) { preset in
                Button(preset.name) {
                    keyCode = preset.code
                    stopRecording()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(keyCode == preset.code ? .accentColor : nil)
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true

        // Monitor regular key presses
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            keyCode = Int(event.keyCode)
            stopRecording()
            return nil // consume event
        }

        // Monitor modifier key presses (Option, Control, Shift, Command, Fn)
        let flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            let code = Int(event.keyCode)
            // Only capture known modifier key codes
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
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }

    private var presetKeys: [(name: String, code: Int)] {
        [
            ("Right ⌥", 61),
            ("Left ⌥", 58),
            ("Right ⌃", 62),
            ("Left ⌃", 59),
            ("Fn", 63),
        ]
    }

    private func keyName(for code: Int) -> String {
        switch code {
        case 61: return "Right Option (⌥)"
        case 58: return "Left Option (⌥)"
        case 59: return "Left Control (⌃)"
        case 62: return "Right Control (⌃)"
        case 63: return "Fn"
        case 56: return "Left Shift (⇧)"
        case 60: return "Right Shift (⇧)"
        case 55: return "Left Command (⌘)"
        case 54: return "Right Command (⌘)"
        case 57: return "Caps Lock"
        case 36: return "Return"
        case 49: return "Space"
        case 53: return "Escape"
        case 48: return "Tab"
        default:
            if let name = keyCodeToString(code) {
                return name
            }
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

        let status = UCKeyTranslate(
            layout,
            UInt16(code),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

// MARK: - Model Tab

private struct ModelTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var modelManager: ModelManager
    let engine: DictationEngine

    var body: some View {
        Form {
            Section("Whisper Model") {
                ForEach(ModelManager.ModelInfo.all, id: \.fileName) { model in
                    ModelRow(
                        model: model,
                        isSelected: isModelSelected(model),
                        isDownloaded: modelManager.isModelDownloaded(model),
                        modelManager: modelManager,
                        settings: settings,
                        engine: engine
                    )
                }
            }

            if modelManager.isDownloading {
                Section("Download Progress") {
                    ProgressView(value: modelManager.downloadProgress)
                    Text("\(Int(modelManager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = modelManager.downloadError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func isModelSelected(_ model: ModelManager.ModelInfo) -> Bool {
        let modelKey = model.fileName
            .replacingOccurrences(of: "ggml-", with: "")
            .replacingOccurrences(of: ".bin", with: "")
        return settings.selectedModel == modelKey
    }
}

private struct ModelRow: View {
    let model: ModelManager.ModelInfo
    let isSelected: Bool
    let isDownloaded: Bool
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var settings: AppSettings
    let engine: DictationEngine

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    Text(model.name)
                        .fontWeight(isSelected ? .semibold : .regular)
                    if isSelected {
                        Text("Active")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(4)
                    }
                }
                Text(model.size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if isDownloaded {
                if !isSelected {
                    Button("Use") {
                        let name = model.fileName
                            .replacingOccurrences(of: "ggml-", with: "")
                            .replacingOccurrences(of: ".bin", with: "")
                        settings.selectedModel = name
                        engine.reloadModel()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button("Download") {
                    Task {
                        try? await modelManager.downloadModel(model)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(modelManager.isDownloading)
            }
        }
    }
}

// MARK: - Vocabulary Tab

private struct VocabularyTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Developer Vocabulary Prompt") {
                TextEditor(text: $settings.vocabularyPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)

                Text("This prompt biases Whisper toward recognizing these terms. Add your project-specific terms here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset to Default") {
                    settings.vocabularyPrompt = AppSettings.defaultVocabularyPrompt
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Permissions Tab

private struct PermissionsTab: View {
    @ObservedObject var permissions: PermissionManager

    var body: some View {
        Form {
            Section("Required Permissions") {
                HStack {
                    Image(systemName: permissions.microphoneGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(permissions.microphoneGranted ? .green : .red)
                    Text("Microphone")
                    Spacer()
                    if !permissions.microphoneGranted {
                        Button("Grant") {
                            permissions.requestMicrophone()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack {
                    Image(systemName: permissions.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(permissions.accessibilityGranted ? .green : .red)
                    Text("Accessibility")
                    Spacer()
                    if !permissions.accessibilityGranted {
                        Button("Open Settings") {
                            permissions.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text("Microphone is needed to capture audio. Accessibility is needed for the global hotkey and to type text at the cursor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Refresh") {
                    permissions.checkPermissions()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
