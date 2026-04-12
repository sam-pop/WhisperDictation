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

    private var accessibilityPoller: Timer?

    init() {
        let axTrusted = AXIsProcessTrusted()
        fputs("[DictationEngine] Init. Accessibility: \(axTrusted)\n", stderr)
        setupHotkeyMonitor()
        hotkeyMonitor?.start()
        loadModelAsync()
        LaunchAtLoginHelper.reconcile()

        if !axTrusted {
            startAccessibilityPoller()
        }
    }

    private func startAccessibilityPoller() {
        accessibilityPoller?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                fputs("[DictationEngine] Accessibility granted! Restarting hotkey monitor.\n", stderr)
                timer.invalidate()
                self?.accessibilityPoller = nil
                self?.restartHotkeyMonitor()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessibilityPoller = timer
    }

    func restartHotkeyMonitor() {
        hotkeyMonitor?.stop()
        setupHotkeyMonitor()
        hotkeyMonitor?.start()
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

                // Pre-warm GPU: JIT-compile Metal shaders with a tiny dummy inference
                bridge.warmup()

                // Start pre-recording buffer (captures 1s before key press)
                try? self.audioCapture.startPreRecording()

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
        audioCapture.stopPreRecording()
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
            fputs("[DictationEngine] Failed to start recording: \(error)\n", stderr)
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

            // Streaming transcription: type segments as they're decoded
            var streamedText = ""
            let rawText = bridge.transcribe(audioBuffer: audioBuffer, prompt: prompt) { segment in
                // This fires on the whisper queue as each segment completes
                injector.type(text: segment)
                streamedText += segment
            }

            guard !rawText.isEmpty else {
                await MainActor.run { [weak self] in self?.state = .idle }
                return
            }

            // Apply grammar correction to the full text
            let corrected = TextCorrector.shared.correct(rawText)

            // If correction changed the text, we need to fix what was already typed.
            // For now, just store the corrected version as lastTranscription.
            // The streamed text is already typed — correction would require selecting
            // and replacing, which is complex. Store for display in menu bar.
            feedback.playDoneSound()

            await MainActor.run { [weak self] in
                self?.lastTranscription = corrected
                self?.state = .idle
            }
        }
    }
}
