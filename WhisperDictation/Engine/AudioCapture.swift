import AVFoundation

final class AudioCapture {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

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

        // Read the input format BEFORE prepare — this is the hardware format
        let hwFormat = inputNode.outputFormat(forBus: 0)
        fputs("[AudioCapture] Hardware format: \(hwFormat.sampleRate)Hz \(hwFormat.channelCount)ch\n", stderr)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidFormat
        }

        engine.prepare()

        let converter = AVAudioConverter(from: hwFormat, to: Self.desiredFormat)!

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        // Use the hardware format for the tap — matches what the node outputs
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }

            converter.reset()

            let ratio = Self.sampleRate / hwFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: Self.desiredFormat, frameCapacity: capacity) else { return }

            var consumed = false
            let status = converter.convert(to: converted, error: nil) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if (status == .haveData || status == .endOfStream),
               converted.frameLength > 0,
               let data = converted.floatChannelData {
                let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(converted.frameLength)))
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
        let buffer = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        let sec = Double(buffer.count) / Self.sampleRate
        fputs("[AudioCapture] Stopped. \(buffer.count) samples (\(String(format: "%.1f", sec))s)\n", stderr)
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
