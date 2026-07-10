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

    /// Last transcription/recording failure surfaced to the user (inference failure,
    /// audio input configuration change). Cleared when a new recording starts and on
    /// the next successful dictation.
    private(set) var transcriptionError: String?

    /// True while the user is holding the hotkey but the toggle-mode threshold hasn't yet fired.
    /// Drives the menu bar hold indicator.
    private(set) var isHoldingForToggle: Bool = false

    private var whisperBridge: WhisperBridge?
    private let audioCapture = AudioCapture()
    private let textInjector = TextInjector()
    private let soundFeedback = SoundFeedback()
    private var hotkeyMonitor: HotkeyMonitor?

    private let minRecordingDuration: TimeInterval = 0.3
    private var recordingStartTime: Date?

    private var accessibilityPoller: Timer?

    /// Pending toggle-mode hold timer. Cancelled if the user releases the key
    /// before the threshold; cleared after firing.
    private var holdWorkItem: DispatchWorkItem?

    init() {
        let axTrusted = AXIsProcessTrusted()
        fputs("[DictationEngine] Init. Accessibility: \(axTrusted)\n", stderr)
        audioCapture.onConfigurationChange = { [weak self] in
            self?.handleInputConfigurationChange()
        }
        audioCapture.onMaxDurationReached = { [weak self] in
            self?.handleMaxRecordingDurationReached()
        }
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
        cancelPendingToggle()
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

                // Pre-warm GPU: JIT-compile Metal shaders with a tiny dummy inference.
                // Async so this cooperative-pool task isn't blocked during warmup.
                await bridge.warmup()

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

    /// Set when `reloadModel()` is requested while a transcription is in flight.
    /// Consumed on the return to idle. Main-actor only.
    private var pendingModelReload = false

    /// Swap the active model. If a transcription is mid-flight (`.recording` captured
    /// no bridge yet, but `.processing`/`.typing` hold the current bridge locally and
    /// must finish on it), nulling `whisperBridge` here would strand that task or drop
    /// the utterance. So only reload immediately when idle; otherwise defer until the
    /// engine returns to idle (the new selection is already persisted in AppSettings,
    /// so the deferred reload picks it up). Called on the main actor.
    func reloadModel() {
        guard state == .idle else {
            pendingModelReload = true
            return
        }
        performModelReload()
    }

    private func performModelReload() {
        pendingModelReload = false
        isModelLoaded = false
        modelLoadError = nil
        whisperBridge = nil
        loadModelAsync()
    }

    /// Transition to idle and, if a model reload was deferred while the engine was
    /// busy, perform it now. Main-actor only.
    private func returnToIdle() {
        state = .idle
        if pendingModelReload { performModelReload() }
    }

    // MARK: - Hotkey

    private func setupHotkeyMonitor() {
        hotkeyMonitor = HotkeyMonitor(
            onKeyDown: { [weak self] in self?.handleKeyDown() },
            onKeyUp: { [weak self] in self?.handleKeyUp() }
        )
    }

    func startMonitoring() {
        hotkeyMonitor?.start()
    }

    func stopMonitoring() {
        cancelPendingToggle()
        hotkeyMonitor?.stop()
    }

    // MARK: - Hotkey Mode Dispatch

    /// What a key-DOWN should do, given the hotkey mode and current state.
    /// Pure/static so the mode dispatch is unit-testable without hardware.
    ///
    /// Cancel semantics follow each mode's existing intent model:
    /// - Push-to-talk: any key-down is deliberate, so a key-down while transcribing
    ///   cancels the in-flight inference immediately. This handler is only invoked
    ///   for genuine key-down / modifier-press events — the HotkeyMonitor watchdog
    ///   only ever synthesizes key-UP — so a cancel can never come from watchdog
    ///   recovery.
    /// - Toggle: every action requires the deliberate ~1.5s hold, and a quick tap is
    ///   ignored. An instant cancel here would let a stray tap destroy a transcription
    ///   (worst case: the 5-min cap or a device change auto-stopped a long recording,
    ///   the user taps to "stop", and the tap lands during .processing). So toggle
    ///   always goes through `scheduleToggleAction`; the cancel happens only if the
    ///   full hold completes while transcribing (see `toggleHoldAction`).
    enum KeyDownAction: Equatable { case startRecording, scheduleToggle, cancelTranscription }

    static func keyDownAction(mode: AppSettings.HotkeyMode, state: DictationState) -> KeyDownAction {
        switch mode {
        case .pushToTalk:
            return (state == .processing || state == .typing) ? .cancelTranscription : .startRecording
        case .toggle:
            return .scheduleToggle
        }
    }

    /// What the toggle hold work item should do when it fires after the full hold
    /// duration. Pure/static for unit testing. A completed hold during
    /// .processing/.typing is as deliberate as one during .recording — it cancels
    /// the in-flight transcription (silently; already-typed segments remain).
    enum ToggleHoldAction: Equatable { case startRecording, stopAndTranscribe, cancelTranscription }

    static func toggleHoldAction(state: DictationState) -> ToggleHoldAction {
        switch state {
        case .idle: return .startRecording
        case .recording: return .stopAndTranscribe
        case .processing, .typing: return .cancelTranscription
        }
    }

    private func handleKeyDown() {
        switch Self.keyDownAction(mode: AppSettings.shared.hotkeyMode, state: state) {
        case .cancelTranscription:
            cancelTranscription()
        case .startRecording:
            startRecording()
        case .scheduleToggle:
            scheduleToggleAction()
        }
    }

    /// Ask the active bridge to abort the running decode. The `transcribe` call then
    /// throws `WhisperError.cancelled`, which the transcription task treats as a silent
    /// reset to idle (no error surfaced). Already-typed segments remain.
    private func cancelTranscription() {
        fputs("[DictationEngine] Cancel requested during \(state.rawValue).\n", stderr)
        whisperBridge?.cancelTranscription()
    }

    private func handleKeyUp() {
        switch AppSettings.shared.hotkeyMode {
        case .pushToTalk:
            stopRecordingAndTranscribe()
        case .toggle:
            cancelPendingToggle()
        }
    }

    /// Toggle mode: schedule a deferred start/stop after `toggleHoldDuration` seconds.
    /// If the user releases the key first, `cancelPendingToggle()` aborts the work item.
    private func scheduleToggleAction() {
        cancelPendingToggle()
        isHoldingForToggle = true
        // Capture the duration ONCE at schedule time. We pass this same value to the
        // trim path so the audio trimmed at stop matches what was actually waited out,
        // even if the slider value changes between schedule and stop.
        let duration = AppSettings.shared.toggleHoldDuration
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isHoldingForToggle = false
            self.holdWorkItem = nil
            // Defensive: settings may have changed mid-hold.
            guard AppSettings.shared.hotkeyMode == .toggle else { return }
            switch Self.toggleHoldAction(state: self.state) {
            case .startRecording:
                self.startRecording()
            case .stopAndTranscribe:
                self.stopRecordingAndTranscribe(trimTrailingSeconds: duration)
            case .cancelTranscription:
                self.cancelTranscription()
            }
        }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func cancelPendingToggle() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        if isHoldingForToggle { isHoldingForToggle = false }
    }

    // MARK: - Prompt Assembly

    /// Whisper's initial_prompt is capped at ~1024 tokens (~750 words). Exceeding it
    /// triggers `whisper_tokenize: too many resulting tokens` and degrades accuracy
    /// (see CLAUDE.md). We budget 700 words as a safe margin.
    static let promptWordBudget = 700

    /// Builds the whisper initial_prompt from the base vocabulary prompt plus the
    /// user's custom terms, staying within `promptWordBudget` words. The base prompt
    /// is truncated first if it alone exceeds the budget; custom terms then fill any
    /// remaining word budget. Pure/static so it is unit-testable without the engine.
    static func buildPrompt(base: String, customTerms: [String]) -> String {
        let baseWords = base.split(separator: " ")
        let cappedBase = baseWords.count > promptWordBudget
            ? baseWords.prefix(promptWordBudget).joined(separator: " ")
            : base

        guard !customTerms.isEmpty else { return cappedBase }

        let budget = max(0, promptWordBudget - baseWords.count)
        let termsToAdd = Array(customTerms.prefix(budget))
        return termsToAdd.isEmpty
            ? cappedBase
            : cappedBase + ", " + termsToAdd.joined(separator: ", ")
    }

    // MARK: - Recording Flow

    private func startRecording() {
        guard state == .idle, isModelLoaded else { return }

        transcriptionError = nil
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

    /// - Parameter trimTrailingSeconds: number of seconds to trim from the end of the audio
    ///   buffer before transcription. Used by toggle mode to discard the silent hold-to-stop
    ///   interval (otherwise Whisper hallucinates trailing punctuation/filler from the silence).
    ///   Push-to-talk passes 0.
    private func stopRecordingAndTranscribe(trimTrailingSeconds: TimeInterval = 0) {
        guard state == .recording else { return }

        let audioBuffer = audioCapture.stopRecording(trimTrailingSeconds: trimTrailingSeconds)
        soundFeedback.playStopSound()

        // Check minimum duration
        if let start = recordingStartTime,
           Date().timeIntervalSince(start) < minRecordingDuration {
            returnToIdle()
            return
        }

        guard !audioBuffer.isEmpty else {
            returnToIdle()
            return
        }

        state = .processing

        let bridge = self.whisperBridge
        let prompt = Self.buildPrompt(
            base: AppSettings.shared.vocabularyPrompt,
            customTerms: AppSettings.shared.customTerms
        )
        let injector = self.textInjector
        let feedback = self.soundFeedback

        Task.detached(priority: .userInitiated) { [weak self] in
            // Wait for all enqueued typing to drain, then surface the result and go idle.
            // injector.flush() blocks this cooperative-pool thread — but it is only a
            // wait (typing itself runs on the injector's own queue), which is the same
            // accepted tradeoff the old synchronous transcribe made.
            func finish(transcript: String?, error: String?) async {
                injector.flush()
                await MainActor.run { [weak self] in
                    if let error { self?.transcriptionError = error }
                    if let transcript, !transcript.isEmpty {
                        self?.lastTranscription = transcript
                        self?.transcriptionError = nil
                    }
                    feedback.playDoneSound()
                    self?.returnToIdle()
                }
            }

            guard let bridge else {
                await finish(transcript: nil, error: nil)
                return
            }

            await MainActor.run { [weak self] in
                self?.state = .typing
            }

            // Stream: correct and type each segment as it's decoded. Segments are
            // enqueued to the injector (non-blocking) and accumulated for the final
            // lastTranscription. The collector is written only from the whisper queue
            // (segment callbacks are serial) and read after `await` returns, which
            // happens-after all writes — so @unchecked Sendable is sound.
            let collected = TranscriptCollector()
            do {
                _ = try await bridge.transcribe(audioBuffer: audioBuffer, prompt: prompt) { segment in
                    let corrected = TextCorrector.shared.correct(segment)
                    // Never log transcribed content — it's the user's private dictation.
                    injector.type(text: corrected)
                    collected.append(corrected)
                }
            } catch let error as WhisperError where error.isCancellation {
                // User-intended cancel: reset to idle without surfacing an error.
                // Any segments already decoded were already typed — that's acceptable.
                fputs("[DictationEngine] Transcription cancelled by user.\n", stderr)
                await finish(transcript: nil, error: nil)
                return
            } catch {
                fputs("[DictationEngine] Transcription failed: \(error)\n", stderr)
                await finish(transcript: nil, error: error.localizedDescription)
                return
            }

            await finish(transcript: collected.text, error: nil)
        }
    }

    /// Invoked (on the audio tap thread) when a recording reaches the maximum
    /// duration cap. Route it through the normal stop-and-transcribe path on the main
    /// actor so what was captured is still transcribed, and surface a brief,
    /// non-error explanation. `stopRecordingAndTranscribe()` leaves any transcript we
    /// produce intact (it clears the status on success once text is typed).
    private func handleMaxRecordingDurationReached() {
        Task { @MainActor [weak self] in
            guard let self, self.state == .recording else { return }
            fputs("[DictationEngine] Max recording duration reached — transcribing what was captured.\n", stderr)
            self.stopRecordingAndTranscribe()
            // Set after stop so it isn't cleared by startRecording's reset; visible
            // during processing until the successful transcript clears it.
            self.transcriptionError = "Reached the \(Int(AudioCapture.maxRecordingSeconds / 60))-minute recording limit. Transcribing what was captured."
        }
    }

    /// Invoked (on an arbitrary thread) when the audio engine's configuration
    /// changes mid-recording — a device being unplugged, a newly plugged-in device
    /// becoming default, or a sample-rate change. All invalidate the running tap,
    /// so stop cleanly and surface the reason. No auto-restart in this phase.
    private func handleInputConfigurationChange() {
        Task { @MainActor [weak self] in
            guard let self, self.state == .recording else { return }
            fputs("[DictationEngine] Audio input configuration changed during recording — stopping.\n", stderr)
            _ = self.audioCapture.stopRecording()
            self.soundFeedback.playStopSound()
            self.recordingStartTime = nil
            self.returnToIdle()
            self.transcriptionError = "Audio input changed. Recording stopped."
        }
    }
}

/// Accumulates corrected transcript segments during a streaming transcription.
/// Appended to only from the whisper decode queue (segment callbacks are delivered
/// serially) and read once after the transcribe `await` returns, which happens-after
/// all appends. That ordering makes the unsynchronized access sound; hence
/// `@unchecked Sendable`.
final class TranscriptCollector: @unchecked Sendable {
    private(set) var text: String = ""
    func append(_ segment: String) { text += segment }
}
