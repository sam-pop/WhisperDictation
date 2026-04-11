import Foundation

final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadError: String?

    private let fileManager = FileManager.default

    struct ModelInfo {
        let name: String
        let fileName: String
        let size: String
        let url: URL

        static let baseEn = ModelInfo(
            name: "Base (English)",
            fileName: "ggml-base.en.bin",
            size: "142 MB",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!
        )
        static let smallEn = ModelInfo(
            name: "Small (English)",
            fileName: "ggml-small.en.bin",
            size: "466 MB",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!
        )
        static let mediumEn = ModelInfo(
            name: "Medium (English)",
            fileName: "ggml-medium.en.bin",
            size: "1.5 GB",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin")!
        )

        static let all: [ModelInfo] = [baseEn, smallEn, mediumEn]
    }

    var modelsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WhisperDictation/Models", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func activeModelPath() -> String? {
        let selectedModel = AppSettings.shared.selectedModel
        let info = ModelInfo.all.first { $0.fileName.contains(selectedModel) } ?? ModelInfo.smallEn
        let path = modelsDirectory.appendingPathComponent(info.fileName).path
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

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by async download
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
