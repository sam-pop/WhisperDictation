import AVFoundation

final class AudioCapture {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var converter: AVAudioConverter?

    private static let sampleRate: Double = 16000
    private static let desiredFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    func startRecording() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        engine.prepare()

        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("[AudioCapture] Input device format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        // Create converter for resampling (input format → 16kHz mono Float32)
        let conv = AVAudioConverter(from: inputFormat, to: Self.desiredFormat)
        self.converter = conv
        print("[AudioCapture] Converter created: \(conv != nil)")

        // Install tap with the INPUT's native format — never pass a custom format
        // to installTap as it can throw uncatchable NSExceptions
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processBuffer(buffer)
        }

        try engine.start()
        self.audioEngine = engine
        print("[AudioCapture] Recording started")
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        // Read converter under lock to avoid race with stopRecording() nil-ing it
        bufferLock.lock()
        let conv = self.converter
        bufferLock.unlock()

        guard let converter = conv else {
            // No converter means formats match — use raw samples
            appendSamples(from: buffer)
            return
        }

        // Calculate output capacity
        let ratio = Self.sampleRate / converter.inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.desiredFormat,
            frameCapacity: outputCapacity
        ) else { return }

        // Use the block-based converter — feed our buffer exactly once
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
           convertedBuffer.frameLength > 0 {
            appendSamples(from: convertedBuffer)
        }
    }

    private func appendSamples(from buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let samples = Array(UnsafeBufferPointer(
            start: floatData[0],
            count: Int(buffer.frameLength)
        ))
        bufferLock.lock()
        audioBuffer.append(contentsOf: samples)
        bufferLock.unlock()
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
        print("[AudioCapture] Stopped. Buffer: \(buffer.count) samples (\(String(format: "%.1f", durationSec))s)")
        return buffer
    }

    var isRecording: Bool {
        audioEngine?.isRunning ?? false
    }
}
