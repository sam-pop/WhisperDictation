import Foundation
import CryptoKit

final class ModelManager: ObservableObject, @unchecked Sendable {
    static nonisolated(unsafe) let shared = ModelManager()

    /// Progress (0...1) of in-flight downloads, keyed by model `fileName`. A model
    /// is present here only while it is actively downloading, so each Settings row
    /// shows progress for its own model — not a single shared bar.
    @Published var activeDownloads: [String: Double] = [:]
    /// Latest download failure, surfaced regardless of which tab is visible.
    @Published var downloadError: String?

    /// In-flight download tasks keyed by model `fileName`, for cancellation.
    /// Confined to the main actor (mutated only from `startDownload`/`cancelDownload`).
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    private let fileManager = FileManager.default

    struct ModelInfo: Identifiable {
        let name: String
        let fileName: String
        let size: String
        let speed: String
        let accuracy: String
        let url: URL
        let isQuantized: Bool
        /// Pinned SHA256 of the exact file at `url`, taken from the HuggingFace LFS
        /// pointer (`.../raw/main/<file>` → `oid sha256:`). Verified after download.
        let sha256: String

        var id: String { fileName }

        // Full precision models
        static let baseEn = ModelInfo(
            name: "Base (English)", fileName: "ggml-base.en.bin",
            size: "142 MB", speed: "Fastest", accuracy: "Good",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
            isQuantized: false,
            sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
        )
        static let smallEn = ModelInfo(
            name: "Small (English)", fileName: "ggml-small.en.bin",
            size: "466 MB", speed: "Balanced", accuracy: "Better",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
            isQuantized: false,
            sha256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
        )
        static let mediumEn = ModelInfo(
            name: "Medium (English)", fileName: "ggml-medium.en.bin",
            size: "1.5 GB", speed: "Slower", accuracy: "Best",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin")!,
            isQuantized: false,
            sha256: "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356"
        )

        // Quantized models — smaller + faster with near-identical accuracy
        static let baseEnQ5 = ModelInfo(
            name: "Base Q5 (English)", fileName: "ggml-base.en-q5_1.bin",
            size: "57 MB", speed: "Fastest", accuracy: "Good",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-q5_1.bin")!,
            isQuantized: true,
            sha256: "4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f"
        )
        static let smallEnQ5 = ModelInfo(
            name: "Small Q5 (English)", fileName: "ggml-small.en-q5_1.bin",
            size: "181 MB", speed: "Fast", accuracy: "Better",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin")!,
            isQuantized: true,
            sha256: "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30"
        )
        static let mediumEnQ5 = ModelInfo(
            name: "Medium Q5 (English)", fileName: "ggml-medium.en-q5_0.bin",
            size: "515 MB", speed: "Balanced", accuracy: "Best",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en-q5_0.bin")!,
            isQuantized: true,
            sha256: "76733e26ad8fe1c7a5bf7531a9d41917b2adc0f20f2e4f5531688a8c6cd88eb0"
        )

        // VAD model
        static let vadSilero = ModelInfo(
            name: "Silero VAD v5", fileName: "ggml-silero-v5.1.2.bin",
            size: "2 MB", speed: "", accuracy: "",
            url: URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin")!,
            isQuantized: false,
            sha256: "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf"
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

    // MARK: - Per-model download state (read by SwiftUI on main)

    func isDownloading(_ model: ModelInfo) -> Bool {
        activeDownloads[model.fileName] != nil
    }

    func downloadProgress(for model: ModelInfo) -> Double? {
        activeDownloads[model.fileName]
    }

    // MARK: - Download control

    // Each (re)start of a download for a key bumps its generation. Only the current
    // generation may write that key's published state, so a cancelled or superseded
    // download can never clobber the UI state of a newer one (cancel → restart race).
    private var downloadGeneration: [String: Int] = [:]

    /// Fire-and-forget download entry point for the UI. Registers a cancellable
    /// task keyed by the model's fileName; ignores duplicate starts.
    @MainActor
    func startDownload(_ model: ModelInfo) {
        let key = model.fileName
        guard downloadTasks[key] == nil else { return }
        let generation = (downloadGeneration[key] ?? 0) + 1
        downloadGeneration[key] = generation
        activeDownloads[key] = 0
        downloadError = nil
        downloadTasks[key] = Task { [weak self] in
            await self?.runDownload(model, generation: generation)
        }
    }

    /// Cancel an in-flight download by model `fileName`.
    @MainActor
    func cancelDownload(name key: String) {
        downloadTasks[key]?.cancel()
        downloadTasks[key] = nil
        // Bump the generation so any late writes from the cancelled task are ignored.
        downloadGeneration[key] = (downloadGeneration[key] ?? 0) + 1
        activeDownloads[key] = nil
    }

    @MainActor
    private func reportProgress(_ progress: Double, key: String, generation: Int) {
        guard downloadGeneration[key] == generation else { return }
        activeDownloads[key] = progress
    }

    @MainActor
    private func finishDownload(key: String, generation: Int, error: String?) {
        guard downloadGeneration[key] == generation else { return }
        activeDownloads[key] = nil
        downloadTasks[key] = nil
        if let error { downloadError = error }
    }

    /// Downloads, verifies (HTTP status + pinned SHA256), and installs a model.
    /// Safe to run twice: the temp file is verified before it replaces any existing
    /// model, and a mismatch throws without touching the installed copy.
    private func runDownload(_ model: ModelInfo, generation: Int) async {
        let key = model.fileName
        let destination = modelsDirectory.appendingPathComponent(model.fileName)

        do {
            try Task.checkCancellation()

            let (tempURL, response) = try await URLSession.shared.download(
                from: model.url,
                delegate: DownloadDelegate { progress in
                    Task { @MainActor [weak self] in
                        self?.reportProgress(progress, key: key, generation: generation)
                    }
                }
            )

            // Validate HTTP status before trusting the bytes.
            if let http = response as? HTTPURLResponse, !Self.isAcceptableStatusCode(http.statusCode) {
                try? fileManager.removeItem(at: tempURL)
                throw ModelError.badStatus(http.statusCode)
            }

            // Verify integrity against the pinned hash (streamed, not loaded whole).
            let actual = try Self.sha256Hex(ofFileAt: tempURL)
            guard actual.caseInsensitiveCompare(model.sha256) == .orderedSame else {
                try? fileManager.removeItem(at: tempURL)
                throw ModelError.checksumMismatch(expected: model.sha256, actual: actual)
            }

            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: tempURL, to: destination)

            await finishDownload(key: key, generation: generation, error: nil)
        } catch is CancellationError {
            // cancelDownload() already performed cleanup.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Cancelled mid-transfer — cleanup handled by cancelDownload().
        } catch {
            fputs("[ModelManager] Download failed for \(model.name): \(error)\n", stderr)
            await finishDownload(key: key, generation: generation,
                                 error: "Couldn’t download \(model.name): \(error.localizedDescription)")
        }
    }

    func deleteModel(_ model: ModelInfo) throws {
        let path = modelsDirectory.appendingPathComponent(model.fileName)
        try fileManager.removeItem(at: path)
    }

    // MARK: - Integrity helpers (testable, pure)

    static func isAcceptableStatusCode(_ code: Int) -> Bool {
        (200..<300).contains(code)
    }

    /// Streams the file in 1 MB chunks through SHA256 so large models (up to ~1.5 GB)
    /// are never loaded into memory at once. Returns a lowercase hex digest.
    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum ModelError: LocalizedError {
    case badStatus(Int)
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "Server returned HTTP \(code)."
        case .checksumMismatch:
            return "Downloaded file failed integrity check (checksum mismatch). It was discarded."
        }
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
