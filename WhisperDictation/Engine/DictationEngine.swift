import Foundation
import Observation
import Cocoa

enum DictationState: String {
    case idle
    case recording
    case processing
    case typing
}

@Observable
final class DictationEngine {
    private(set) var state: DictationState = .idle
    private(set) var lastTranscription: String = ""
    private(set) var isModelLoaded: Bool = false
    private(set) var modelLoadError: String?

    private var whisperBridge: WhisperBridge?
    private let audioCapture = AudioCapture()
    private let textInjector = TextInjector()
    private let soundFeedback = SoundFeedback()
    private var hotkeyMonitor: HotkeyMonitor?

    private let minRecordingDuration: TimeInterval = 0.3
    private var recordingStartTime: Date?

    init() {
        let axTrusted = AXIsProcessTrusted()
        fputs("[DictationEngine] Init. Accessibility: \(axTrusted)\n", stderr)
        setupHotkeyMonitor()
        hotkeyMonitor?.start()
        loadModelAsync()
    }

    // MARK: - Model Loading

    private func loadModelAsync() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let modelPath = ModelManager.shared.activeModelPath()
                guard let modelPath else {
                    await MainActor.run {
                        self.modelLoadError = "No model found. Open Settings to download a model."
                    }
                    return
                }
                let bridge = try WhisperBridge(modelPath: modelPath)
                await MainActor.run {
                    self.whisperBridge = bridge
                    self.isModelLoaded = true
                    self.modelLoadError = nil
                }
            } catch {
                await MainActor.run {
                    self.modelLoadError = "Failed to load model: \(error.localizedDescription)"
                }
            }
        }
    }

    func reloadModel() {
        isModelLoaded = false
        modelLoadError = nil
        whisperBridge = nil
        loadModelAsync()
    }

    // MARK: - Hotkey

    private func setupHotkeyMonitor() {
        hotkeyMonitor = HotkeyMonitor(
            onKeyDown: { [weak self] in self?.startRecording() },
            onKeyUp: { [weak self] in self?.stopRecordingAndTranscribe() }
        )
    }

    func startMonitoring() {
        hotkeyMonitor?.start()
    }

    func stopMonitoring() {
        hotkeyMonitor?.stop()
    }

    // MARK: - Recording Flow

    private func startRecording() {
        guard state == .idle, isModelLoaded else { return }

        state = .recording
        recordingStartTime = Date()
        soundFeedback.playStartSound()

        do {
            try audioCapture.startRecording()
        } catch {
            print("Failed to start recording: \(error)")
            state = .idle
        }
    }

    private func stopRecordingAndTranscribe() {
        guard state == .recording else { return }

        let audioBuffer = audioCapture.stopRecording()
        soundFeedback.playStopSound()

        // Check minimum duration
        if let start = recordingStartTime,
           Date().timeIntervalSince(start) < minRecordingDuration {
            state = .idle
            return
        }

        guard !audioBuffer.isEmpty else {
            state = .idle
            return
        }

        state = .processing

        let bridge = self.whisperBridge
        let prompt = AppSettings.shared.vocabularyPrompt
        let injector = self.textInjector
        let feedback = self.soundFeedback

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let bridge else {
                await MainActor.run { [weak self] in self?.state = .idle }
                return
            }

            let rawText = bridge.transcribe(audioBuffer: audioBuffer, prompt: prompt)

            guard !rawText.isEmpty else {
                await MainActor.run { [weak self] in self?.state = .idle }
                return
            }

            // Grammar correction (local, <5ms)
            let text = TextCorrector.shared.correct(rawText)

            await MainActor.run { [weak self] in
                self?.lastTranscription = text
                self?.state = .typing
            }

            // Type text on a background thread to avoid blocking the main thread
            injector.type(text: text)
            feedback.playDoneSound()

            await MainActor.run { [weak self] in
                self?.state = .idle
            }
        }
    }
}
