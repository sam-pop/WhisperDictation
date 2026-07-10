import AVFoundation

final class AudioCapture {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    /// Invoked when the audio engine's configuration changes while recording
    /// (e.g. the selected input device is unplugged). Called on an arbitrary
    /// thread — the handler must hop to the main actor before touching UI state.
    var onConfigurationChange: (() -> Void)?
    private var configObserver: NSObjectProtocol?

    private static let sampleRate: Double = 16000
    private static let desiredFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    func startRecording() throws {
        let engine = AVAudioEngine()

        // Apply the user-selected input device BEFORE prepare()/reading the format,
        // so the hardware format reflects the chosen device. Failure falls back to
        // the system default device (logged inside applySelectedDevice).
        AudioDeviceManager.shared.applySelectedDevice(to: engine)

        let inputNode = engine.inputNode

        // prepare() FIRST — settles the audio hardware format
        engine.prepare()

        let hwFormat = inputNode.outputFormat(forBus: 0)
        fputs("[AudioCapture] Hardware format: \(hwFormat.sampleRate)Hz \(hwFormat.channelCount)ch\n", stderr)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidFormat
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: Self.desiredFormat) else {
            fputs("[AudioCapture] Could not create converter from hardware format\n", stderr)
            throw AudioCaptureError.invalidFormat
        }

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            fputs(".", stderr) // Heartbeat — proves callback is firing
            guard let self else { return }

            let ratio = Self.sampleRate / hwFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: Self.desiredFormat, frameCapacity: capacity) else {
                fputs("X", stderr)
                return
            }

            // Per CLAUDE.md: reset before each conversion. Without this, the converter's
            // internal state expects a continuous stream and produces empty output across
            // discrete tap-callback buffers.
            converter.reset()

            var consumed = false
            var convErr: NSError?
            let status = converter.convert(to: converted, error: &convErr) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if let convErr {
                fputs("[E:\(convErr.code)]", stderr)
                return
            }

            if converted.frameLength > 0, let data = converted.floatChannelData {
                let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(converted.frameLength)))
                self.bufferLock.lock()
                self.audioBuffer.append(contentsOf: samples)
                self.bufferLock.unlock()
                fputs("+", stderr) // successful conversion
            } else {
                fputs("[s:\(status.rawValue) f:\(converted.frameLength)]", stderr)
            }
        }

        // Detect audio configuration changes mid-recording (device unplugged, a new
        // default device appearing, sample-rate change — all invalidate the tap).
        // Observe this specific engine only. Removed in stopRecording().
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            fputs("[AudioCapture] Engine configuration changed\n", stderr)
            self?.onConfigurationChange?()
        }

        try engine.start()
        self.audioEngine = engine
        fputs("[AudioCapture] Recording started\n", stderr)
    }

    /// Stops capture and returns the captured buffer.
    /// - Parameter trimTrailingSeconds: optional number of seconds to trim from the END of the
    ///   buffer. Used by toggle hotkey mode to discard the silent hold-to-stop interval, which
    ///   would otherwise be transcribed by Whisper as hallucinated punctuation/filler.
    func stopRecording(trimTrailingSeconds: TimeInterval = 0) -> [Float] {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        bufferLock.lock()
        var buffer = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        if trimTrailingSeconds > 0 {
            let samplesToTrim = Int(trimTrailingSeconds * Self.sampleRate)
            if buffer.count > samplesToTrim {
                buffer.removeLast(samplesToTrim)
            } else {
                buffer.removeAll()
            }
        }

        let sec = Double(buffer.count) / Self.sampleRate
        fputs("[AudioCapture] Stopped. \(buffer.count) samples (\(String(format: "%.1f", sec))s, trimmed \(String(format: "%.1f", trimTrailingSeconds))s)\n", stderr)
        return buffer
    }

    var isRecording: Bool {
        audioEngine?.isRunning ?? false
    }
}

enum AudioCaptureError: LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        "Audio input format is invalid."
    }
}
