import AVFoundation

final class AudioCapture {
    private var audioEngine: AVAudioEngine?
    private var mixerNode: AVAudioMixerNode?
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

        engine.prepare()

        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("[AudioCapture] Input format: \(inputFormat)")

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        // Use a mixer node to handle sample rate and channel conversion
        // This is more reliable than manual AVAudioConverter
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(inputNode, to: mixer, format: inputFormat)

        mixer.installTap(onBus: 0, bufferSize: 4096, format: Self.desiredFormat) { [weak self] buffer, _ in
            guard let self, let floatData = buffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(
                start: floatData[0],
                count: Int(buffer.frameLength)
            ))
            self.bufferLock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.bufferLock.unlock()
        }

        try engine.start()
        self.audioEngine = engine
        self.mixerNode = mixer
        print("[AudioCapture] Recording started")
    }

    func stopRecording() -> [Float] {
        mixerNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        mixerNode = nil

        bufferLock.lock()
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
