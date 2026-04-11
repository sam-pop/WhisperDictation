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

        // Prepare engine first so hardware format is settled
        engine.prepare()

        let inputFormat = inputNode.outputFormat(forBus: 0)

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        let converter = AVAudioConverter(from: inputFormat, to: Self.desiredFormat)

        guard converter != nil || inputFormat == Self.desiredFormat else {
            throw AudioCaptureError.formatConversionFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            if let converter {
                let ratio = Self.sampleRate / inputFormat.sampleRate
                let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: Self.desiredFormat,
                    frameCapacity: outputFrameCapacity
                ) else { return }

                var error: NSError?
                var allConsumed = false
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    if allConsumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    allConsumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }

                if error == nil, let floatData = convertedBuffer.floatChannelData {
                    let samples = Array(UnsafeBufferPointer(
                        start: floatData[0],
                        count: Int(convertedBuffer.frameLength)
                    ))
                    self.bufferLock.lock()
                    self.audioBuffer.append(contentsOf: samples)
                    self.bufferLock.unlock()
                }
            } else {
                if let floatData = buffer.floatChannelData {
                    let samples = Array(UnsafeBufferPointer(
                        start: floatData[0],
                        count: Int(buffer.frameLength)
                    ))
                    self.bufferLock.lock()
                    self.audioBuffer.append(contentsOf: samples)
                    self.bufferLock.unlock()
                }
            }
        }

        try engine.start()
        self.audioEngine = engine
    }

    func stopRecording() -> [Float] {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        bufferLock.lock()
        let buffer = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        return buffer
    }

    var isRecording: Bool {
        audioEngine?.isRunning ?? false
    }
}

enum AudioCaptureError: LocalizedError {
    case formatConversionFailed

    var errorDescription: String? {
        switch self {
        case .formatConversionFailed:
            return "Could not create audio format converter for the current input device."
        }
    }
}
