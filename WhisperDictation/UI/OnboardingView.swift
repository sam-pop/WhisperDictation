import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var modelManager = ModelManager.shared
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Welcome to WhisperDictation")
                .font(.title)
                .fontWeight(.bold)

            Text("Local, private voice-to-text powered by Whisper AI.\nHold a key to speak, release to type.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone Access",
                    description: "Required to capture your voice",
                    isGranted: permissions.microphoneGranted,
                    action: { permissions.requestMicrophone() }
                )

                PermissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility Access",
                    description: "Required for global hotkey and text typing",
                    isGranted: permissions.accessibilityGranted,
                    action: { permissions.openAccessibilitySettings() }
                )

                ModelDownloadRow(modelManager: modelManager)
            }
            .padding()
            .background(.quaternary.opacity(0.5))
            .cornerRadius(12)

            Button("Get Started") {
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(!permissions.allPermissionsGranted || modelManager.activeModelPath() == nil)
            .controlSize(.large)

            Button("Skip for now") {
                isPresented = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .padding(32)
        .frame(width: 440)
        .onAppear {
            permissions.checkPermissions()
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .blue)
                .frame(width: 32)

            VStack(alignment: .leading) {
                Text(title).fontWeight(.medium)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if !isGranted {
                Button("Grant", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

private struct ModelDownloadRow: View {
    @ObservedObject var modelManager: ModelManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: modelManager.activeModelPath() != nil ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(modelManager.activeModelPath() != nil ? .green : .blue)
                .frame(width: 32)

            VStack(alignment: .leading) {
                Text("Whisper Model").fontWeight(.medium)
                if modelManager.isDownloading {
                    ProgressView(value: modelManager.downloadProgress)
                    Text("Downloading... \(Int(modelManager.downloadProgress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                } else if modelManager.activeModelPath() != nil {
                    Text("Small English model ready").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Download the Small English model (466 MB)").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if modelManager.activeModelPath() == nil && !modelManager.isDownloading {
                Button("Download") {
                    Task {
                        try? await modelManager.downloadModel(.smallEn)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
