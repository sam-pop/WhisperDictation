import SwiftUI

struct MenuBarView: View {
    let engine: DictationEngine
    @ObservedObject private var permissions = PermissionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            statusSection
            Divider()
            controlsSection
            Divider()
            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",")
            Button("Quit WhisperDictation") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.headline)
        }
        .padding(.horizontal, 8)

        if !engine.isModelLoaded {
            if let error = engine.modelLoadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
            } else {
                Text("Loading model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }

        if !permissions.allPermissionsGranted {
            Text("Permissions needed")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        if !permissions.microphoneGranted {
            Button("Grant Microphone Access") {
                permissions.requestMicrophone()
            }
        }
        if !permissions.accessibilityGranted {
            Button("Open Accessibility Settings") {
                permissions.openAccessibilitySettings()
            }
        }

        if let lastText = engine.lastTranscription.isEmpty ? nil : engine.lastTranscription {
            Text("Last: \(lastText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 8)
        }
    }

    private var statusText: String {
        switch engine.state {
        case .idle:
            engine.isModelLoaded ? "Ready" : "Loading..."
        case .recording:
            "Recording..."
        case .processing:
            "Transcribing..."
        case .typing:
            "Typing..."
        }
    }

    private var statusColor: Color {
        switch engine.state {
        case .idle: .green
        case .recording: .red
        case .processing: .orange
        case .typing: .blue
        }
    }
}
