import Foundation

class ModelDownloader: ObservableObject {
    static let shared = ModelDownloader()

    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var currentModel: WhisperModel?
    @Published var error: String?

    private var downloadTask: URLSessionDownloadTask?

    private init() {}

    func downloadModel(_ model: WhisperModel) async -> Bool {
        await MainActor.run {
            isDownloading = true
            progress = 0
            currentModel = model
            error = nil
        }

        let destination = Settings.shared.modelsDirectory.appendingPathComponent(model.rawValue)

        do {
            let (tempURL, _) = try await downloadWithProgress(from: model.downloadURL, expectedSize: model.fileSize)

            try FileManager.default.moveItem(at: tempURL, to: destination)

            await MainActor.run {
                isDownloading = false
                progress = 1.0
                currentModel = nil
            }

            print("[ModelDownloader] Successfully downloaded \(model.displayName)")
            return true

        } catch {
            await MainActor.run {
                self.isDownloading = false
                self.error = error.localizedDescription
                self.currentModel = nil
            }

            print("[ModelDownloader] Failed to download: \(error)")
            return false
        }
    }

    private func downloadWithProgress(from url: URL, expectedSize: Int64) async throws -> (URL, URLResponse) {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempFile.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempFile)

        var downloadedSize: Int64 = 0
        var buffer = [UInt8]()
        buffer.reserveCapacity(65536)

        for try await byte in asyncBytes {
            buffer.append(byte)
            downloadedSize += 1

            if buffer.count >= 65536 {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)

                if expectedSize > 0 {
                    let prog = Double(downloadedSize) / Double(expectedSize)
                    await MainActor.run {
                        self.progress = prog
                    }
                }
            }
        }

        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
        }

        try fileHandle.close()

        await MainActor.run {
            self.progress = 1.0
        }

        return (tempFile, response)
    }

    func cancel() {
        downloadTask?.cancel()
        isDownloading = false
        currentModel = nil
        progress = 0
    }
}
