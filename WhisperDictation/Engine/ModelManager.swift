import Foundation

final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadError: String?

    private let fileManager = FileManager.default

    struct ModelInfo: Identifiable {
        let name: String
        let fileName: String
        let size: String
        let speed: String
        let accuracy: String
        let url: URL
        let isQuantized: Bool

        var id: String { fileName }

        // Full precision models
        static let baseEn = ModelInfo(
            name: "Base (English)", fileName: "ggml-base.en.bin",
            size: "142 MB", speed: "Fastest", accuracy: "Good",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
            isQuantized: false
        )
        static let smallEn = ModelInfo(
            name: "Small (English)", fileName: "ggml-small.en.bin",
            size: "466 MB", speed: "Balanced", accuracy: "Better",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
            isQuantized: false
        )
        static let mediumEn = ModelInfo(
            name: "Medium (English)", fileName: "ggml-medium.en.bin",
            size: "1.5 GB", speed: "Slower", accuracy: "Best",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin")!,
            isQuantized: false
        )

        // Quantized models — smaller + faster with near-identical accuracy
        static let baseEnQ5 = ModelInfo(
            name: "Base Q5 (English)", fileName: "ggml-base.en-q5_1.bin",
            size: "57 MB", speed: "Fastest", accuracy: "Good",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-q5_1.bin")!,
            isQuantized: true
        )
        static let smallEnQ5 = ModelInfo(
            name: "Small Q5 (English)", fileName: "ggml-small.en-q5_1.bin",
            size: "181 MB", speed: "Fast", accuracy: "Better",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin")!,
            isQuantized: true
        )
        static let mediumEnQ5 = ModelInfo(
            name: "Medium Q5 (English)", fileName: "ggml-medium.en-q5_0.bin",
            size: "515 MB", speed: "Balanced", accuracy: "Best",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en-q5_0.bin")!,
            isQuantized: true
        )

        // VAD model
        static let vadSilero = ModelInfo(
            name: "Silero VAD v5", fileName: "ggml-silero-v5.1.2.bin",
            size: "2 MB", speed: "", accuracy: "",
            url: URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin")!,
            isQuantized: false
        )

        static let all: [ModelInfo] = [baseEnQ5, smallEnQ5, mediumEnQ5, baseEn, smallEn, mediumEn]
        static let recommended: [ModelInfo] = [baseEnQ5, smallEnQ5, mediumEnQ5]
    }

    var modelsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WhisperDictation/Models", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func activeModelPath() -> String? {
        let selectedModel = AppSettings.shared.selectedModel
        // Try exact match first, then contains
        let info = ModelInfo.all.first { $0.fileName == "ggml-\(selectedModel).bin" }
            ?? ModelInfo.all.first { $0.fileName.contains(selectedModel) }
            ?? ModelInfo.smallEnQ5
        let path = modelsDirectory.appendingPathComponent(info.fileName).path
        return fileManager.fileExists(atPath: path) ? path : nil
    }

    func vadModelPath() -> String? {
        let path = modelsDirectory.appendingPathComponent(ModelInfo.vadSilero.fileName).path
        return fileManager.fileExists(atPath: path) ? path : nil
    }

    func isModelDownloaded(_ model: ModelInfo) -> Bool {
        fileManager.fileExists(atPath: modelsDirectory.appendingPathComponent(model.fileName).path)
    }

    func downloadedModels() -> [ModelInfo] {
        ModelInfo.all.filter { isModelDownloaded($0) }
    }

    func downloadModel(_ model: ModelInfo) async throws {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
            downloadError = nil
        }

        let destination = modelsDirectory.appendingPathComponent(model.fileName)

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: model.url, delegate: DownloadDelegate { progress in
                Task { @MainActor in
                    self.downloadProgress = progress
                }
            })

            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: tempURL, to: destination)

            await MainActor.run {
                isDownloading = false
                downloadProgress = 1.0
            }
        } catch {
            await MainActor.run {
                isDownloading = false
                downloadError = error.localizedDescription
            }
            throw error
        }
    }

    func deleteModel(_ model: ModelInfo) throws {
        let path = modelsDirectory.appendingPathComponent(model.fileName)
        try fileManager.removeItem(at: path)
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Double) -> Void

    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
