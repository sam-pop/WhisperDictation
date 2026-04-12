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

        AudioDeviceManager.shared.applySelectedDevice(to: engine)
        engine.prepare()

        bufferLock.lock()
        self.converter = nil
        audioBuffer.removeAll()
        bufferLock.unlock()

        // Pass nil format — create converter lazily from actual buffer format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }

            // Create converter on first callback from the real buffer format
            self.bufferLock.lock()
            if self.converter == nil {
                self.converter = AVAudioConverter(from: buffer.format, to: Self.desiredFormat)
                fputs("[AudioCapture] Format: \(buffer.format.sampleRate)Hz \(buffer.format.channelCount)ch\n", stderr)
            }
            let conv = self.converter
            self.bufferLock.unlock()

            guard let conv else { return }

            let ratio = Self.sampleRate / conv.inputFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: Self.desiredFormat,
                frameCapacity: outputCapacity
            ) else { return }

            // Reset converter between callbacks — required because we feed one buffer
            // per convert() call with the inputConsumed pattern. Without reset, the
            // converter's internal state expects a continuous stream and produces empty output.
            conv.reset()

            var inputConsumed = false
            let status = conv.convert(to: convertedBuffer, error: nil) { _, outStatus in
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
                let samples = Array(UnsafeBufferPointer(
                    start: floatData[0],
                    count: Int(convertedBuffer.frameLength)
                ))
                self.bufferLock.lock()
                self.audioBuffer.append(contentsOf: samples)
                self.bufferLock.unlock()
            }
        }

        try engine.start()
        self.audioEngine = engine
        fputs("[AudioCapture] Recording started\n", stderr)
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
        return buffer
    }

    var isRecording: Bool {
        audioEngine?.isRunning ?? false
    }
}
