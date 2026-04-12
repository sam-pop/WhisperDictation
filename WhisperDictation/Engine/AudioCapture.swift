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
    private var preRecordConverter: AVAudioConverter?
    private static let preRecordDuration: Double = 1.0
    private static let preRecordSamples = Int(preRecordDuration * sampleRate)

    private static let sampleRate: Double = 16000
    private static let desiredFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Pre-recording

    func startPreRecording() throws {
        guard preRecordEngine == nil else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        engine.prepare()

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            guard let self else { return }

            // Lazily create converter from the actual buffer format
            if self.preRecordConverter == nil {
                self.preRecordConverter = AVAudioConverter(from: buffer.format, to: Self.desiredFormat)
                fputs("[AudioCapture] Pre-record format: \(buffer.format.sampleRate)Hz \(buffer.format.channelCount)ch\n", stderr)
            }

            let samples = self.convertToFloat(buffer, converter: self.preRecordConverter)
            guard !samples.isEmpty else { return }

            self.preRecordLock.lock()
            self.preRecordBuffer.append(contentsOf: samples)
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
        preRecordConverter = nil
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
            preRecordConverter = nil

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

        bufferLock.lock()
        self.converter = nil // Will be created lazily from actual buffer format
        audioBuffer = preBuffer
        bufferLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }

            // Lazily create converter from the actual buffer format on first callback
            self.bufferLock.lock()
            if self.converter == nil {
                self.converter = AVAudioConverter(from: buffer.format, to: Self.desiredFormat)
                fputs("[AudioCapture] Recording format: \(buffer.format.sampleRate)Hz \(buffer.format.channelCount)ch\n", stderr)
            }
            let conv = self.converter
            self.bufferLock.unlock()

            let samples = self.convertToFloat(buffer, converter: conv)
            if samples.isEmpty {
                fputs("[AudioCapture] WARNING: convertToFloat returned 0 samples from \(buffer.frameLength) frames\n", stderr)
                return
            }

            self.bufferLock.lock()
            self.audioBuffer.append(contentsOf: samples)
            let total = self.audioBuffer.count
            self.bufferLock.unlock()

            if total % 16000 < 500 { // Log roughly every second
                fputs("[AudioCapture] Buffer: \(total) samples (\(String(format: "%.1f", Double(total) / Self.sampleRate))s)\n", stderr)
            }
        }

        try engine.start()
        self.audioEngine = engine
        fputs("[AudioCapture] Recording started\n", stderr)
    }

    /// Convert an audio buffer to Float32 16kHz mono
    private func convertToFloat(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?) -> [Float] {
        guard let converter else {
            // No converter — assume format already matches
            guard let floatData = buffer.floatChannelData else { return [] }
            return Array(UnsafeBufferPointer(start: floatData[0], count: Int(buffer.frameLength)))
        }

        let ratio = Self.sampleRate / converter.inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.desiredFormat,
            frameCapacity: outputCapacity
        ) else { return [] }

        // Reset converter before each conversion to prevent internal state drift
        converter.reset()

        var inputConsumed = false
        var convError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &convError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let convError {
            fputs("[AudioCapture] Conversion error: \(convError)\n", stderr)
            return []
        }

        if (status == .haveData || status == .endOfStream),
           convertedBuffer.frameLength > 0,
           let floatData = convertedBuffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: floatData[0], count: Int(convertedBuffer.frameLength)))
        }
        return []
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

        // Restart pre-recording for next dictation
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

enum AudioCaptureError: LocalizedError {
    case invalidInputFormat

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat:
            return "Audio input format is invalid."
        }
    }
}
