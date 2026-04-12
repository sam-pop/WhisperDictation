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
        let basePrompt = AppSettings.shared.vocabularyPrompt
        let customTerms = AppSettings.shared.customTerms
        let prompt: String
        if customTerms.isEmpty {
            prompt = basePrompt
        } else {
            // Cap custom terms to stay under whisper's ~1024 token (~750 word) limit
            let baseWordCount = basePrompt.split(separator: " ").count
            let budget = max(0, 700 - baseWordCount)
            let termsToAdd = Array(customTerms.prefix(budget))
            prompt = termsToAdd.isEmpty ? basePrompt : basePrompt + ", " + termsToAdd.joined(separator: ", ")
        }
        let injector = self.textInjector
        let feedback = self.soundFeedback

        Task.detached(priority: .userInitiated) { [weak self] in
            func resetToIdle() async {
                await MainActor.run { [weak self] in
                    feedback.playDoneSound()
                    self?.state = .idle
                }
            }

            guard let bridge else {
                await resetToIdle()
                return
            }

            await MainActor.run { [weak self] in
                self?.state = .typing
            }

            // Stream: correct and type each segment as it's decoded
            var fullText = ""
            let _ = bridge.transcribe(audioBuffer: audioBuffer, prompt: prompt) { segment in
                let corrected = TextCorrector.shared.correct(segment)
                fputs("[Streaming] \(corrected)\n", stderr)
                injector.type(text: corrected)
                fullText += corrected
            }

            await MainActor.run { [weak self] in
                if !fullText.isEmpty {
                    self?.lastTranscription = fullText
                }
            }

            await resetToIdle()
        }
    }
}
