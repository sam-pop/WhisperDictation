import SwiftUI

struct SettingsView: View {
    let engine: DictationEngine
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var permissions = PermissionManager.shared

    var body: some View {
        TabView {
            GeneralTab(settings: settings, engine: engine)
                .tabItem { Label("General", systemImage: "gear") }

            ModelTab(settings: settings, modelManager: modelManager, engine: engine)
                .tabItem { Label("Model", systemImage: "brain") }

            VocabularyTab(settings: settings)
                .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }

            PermissionsTab(permissions: permissions)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 480, height: 380)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    let engine: DictationEngine

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Push-to-talk key:")
                    Spacer()
                    Text(hotkeyName)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .cornerRadius(6)
                }
                Text("Hold to record, release to transcribe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Audio") {
                Toggle("Sound feedback", isOn: $settings.soundFeedbackEnabled)
            }

            Section("System") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var hotkeyName: String {
        switch settings.hotkeyKeyCode {
        case 61: "Right Option"
        case 58: "Left Option"
        case 59: "Left Control"
        case 62: "Right Control"
        default: "Key \(settings.hotkeyKeyCode)"
        }
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
                        isSelected: settings.selectedModel.contains(model.fileName.replacingOccurrences(of: "ggml-", with: "").replacingOccurrences(of: ".bin", with: "")),
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
