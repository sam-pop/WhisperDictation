import AVFoundation

final class AudioCapture {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var converter: AVAudioConverter?

    // Pre-recording: circular buffer that captures audio BEFORE key press
    private var preRecordEngine: AVAudioEngine?
    private var preRecordBuffer: [Float] = []
    private let preRecordLock = NSLock()
    private static let preRecordDuration: Double = 1.0 // 1 second
    private static let preRecordSamples = Int(preRecordDuration * sampleRate) // 16,000 samples

    private static let sampleRate: Double = 16000
    private static let desiredFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Pre-recording (always-on 1s circular buffer)

    /// Start capturing audio into a 1-second rolling buffer. Call once after model loads.
    /// This runs continuously so we never miss the first words of a dictation.
    func startPreRecording() throws {
        guard preRecordEngine == nil else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        engine.prepare()

        let inputFormat = inputNode.outputFormat(forBus: 0)
        let conv = AVAudioConverter(from: inputFormat, to: Self.desiredFormat)

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = self.convertToFloat(buffer, converter: conv)
            guard !samples.isEmpty else { return }

            self.preRecordLock.lock()
            self.preRecordBuffer.append(contentsOf: samples)
            // Keep only the last 1 second
            if self.preRecordBuffer.count > Self.preRecordSamples {
                self.preRecordBuffer.removeFirst(self.preRecordBuffer.count - Self.preRecordSamples)
            }
            self.preRecordLock.unlock()
        }

        try engine.start()
        self.preRecordEngine = engine
        fputs("[AudioCapture] Pre-recording started (1s circular buffer)\n", stderr)
    }

    func stopPreRecording() {
        preRecordEngine?.inputNode.removeTap(onBus: 0)
        preRecordEngine?.stop()
        preRecordEngine = nil
        preRecordLock.lock()
        preRecordBuffer.removeAll()
        preRecordLock.unlock()
    }

    // MARK: - Active Recording

    func startRecording() throws {
        // Stop pre-recording first (we'll use its buffer as a head start)
        let preBuffer: [Float]
        if preRecordEngine != nil {
            preRecordEngine?.inputNode.removeTap(onBus: 0)
            preRecordEngine?.stop()
            preRecordEngine = nil

            preRecordLock.lock()
            preBuffer = preRecordBuffer
            preRecordBuffer.removeAll()
            preRecordLock.unlock()

            fputs("[AudioCapture] Pre-buffer: \(preBuffer.count) samples (\(String(format: "%.1f", Double(preBuffer.count) / Self.sampleRate))s)\n", stderr)
        } else {
            preBuffer = []
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        AudioDeviceManager.shared.applySelectedDevice(to: engine)
        engine.prepare()

        let inputFormat = inputNode.outputFormat(forBus: 0)
        let conv = AVAudioConverter(from: inputFormat, to: Self.desiredFormat)

        bufferLock.lock()
        self.converter = conv
        // Seed with pre-recorded audio
        audioBuffer = preBuffer
        bufferLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processBuffer(buffer)
        }

        try engine.start()
        self.audioEngine = engine
        fputs("[AudioCapture] Recording started\n", stderr)
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        bufferLock.lock()
        let conv = self.converter
        bufferLock.unlock()

        let samples = convertToFloat(buffer, converter: conv)
        guard !samples.isEmpty else { return }

        bufferLock.lock()
        audioBuffer.append(contentsOf: samples)
        bufferLock.unlock()
    }

    /// Convert an audio buffer to Float32 16kHz mono using the given converter
    private func convertToFloat(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?) -> [Float] {
        if let converter {
            let ratio = Self.sampleRate / converter.inputFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: Self.desiredFormat,
                frameCapacity: outputCapacity
            ) else { return [] }

            var inputConsumed = false
            let status = converter.convert(to: convertedBuffer, error: nil) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if (status == .haveData || status == .endOfStream),
               convertedBuffer.frameLength > 0,
               let floatData = convertedBuffer.floatChannelData {
                return Array(UnsafeBufferPointer(start: floatData[0], count: Int(convertedBuffer.frameLength)))
            }
            return []
        } else {
            guard let floatData = buffer.floatChannelData else { return [] }
            return Array(UnsafeBufferPointer(start: floatData[0], count: Int(buffer.frameLength)))
        }
    }

    func stopRecording() -> [Float] {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        bufferLock.lock()
        converter = nil
        let buffer = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        let durationSec = Double(buffer.count) / Self.sampleRate
        fputs("[AudioCapture] Stopped. \(buffer.count) samples (\(String(format: "%.1f", durationSec))s)\n", stderr)

        // Restart pre-recording for next dictation (only if not already recording again)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.audioEngine == nil, self.preRecordEngine == nil else { return }
            try? self.startPreRecording()
        }

        return buffer
    }

    var isRecording: Bool {
        audioEngine?.isRunning ?? false
    }
}
