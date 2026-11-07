import CryptoKit
import Foundation

enum LFMAssets {
    static let repo = "LiquidAI/LFM2.5-1.2B-Instruct-GGUF"
    static let revision = "8ed288026e23958ad9dfa92d53ed773a8eee7125"
    static let filename = "LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
    static let bytes: Int64 = 730_895_168
    static let checksum = "b1b3de114215d9507409a662a501a631095a479a419584e8a2ded6304b19b4f5"
    static var file: URL { LocalStorage.hfHome.appendingPathComponent(filename) }
    static var installed: Bool {
        (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(bytes)
    }

    static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        if installed { progress(1); return }
        try FileManager.default.createDirectory(at: LocalStorage.hfHome, withIntermediateDirectories: true)
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(filename)")!
        let delegate = DownloadProgress(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              (try temporary.resourceValues(forKeys: [.fileSizeKey])).fileSize == Int(bytes) else {
            throw VocalError.message("The LFM download was incomplete. Retry while online.")
        }
        let handle = try FileHandle(forReadingFrom: temporary)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == checksum else { throw VocalError.message("LFM checksum verification failed. Retry the download.") }
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        try FileManager.default.moveItem(at: temporary, to: file)
        progress(1)
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(min(1, Double(totalBytesWritten) / Double(LFMAssets.bytes)))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
