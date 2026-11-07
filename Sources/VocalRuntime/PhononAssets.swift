import CryptoKit
import Foundation
import PhononTTS
import ZIPFoundation

enum PhononAssets {
    static var directory: URL { LocalStorage.hfHome.appendingPathComponent("Phonon31m", isDirectory: true) }
    static let url = URL(string: "https://github.com/gradium-ai/xn-ptts/releases/download/v0.6.0/phonon-31m-en-coreml.zip")!
    static let checksum = "2869326ab074f55ed5b644e68b1befef69dc51545b73296d49f5b4dab14c4218"

    static func download() async throws {
        if PhononModels.isInstalled(at: directory) { return }
        let (archive, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw VocalError.message("Phonon model download failed. Retry while online.")
        }
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == checksum else {
            throw VocalError.message("Phonon archive checksum verification failed.")
        }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("vocal-phonon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: archive, to: staging)
        guard let enumerator = FileManager.default.enumerator(at: staging, includingPropertiesForKeys: nil),
              let manifest = enumerator.compactMap({ $0 as? URL }).first(where: { $0.lastPathComponent == "bundle.json" }) else {
            throw VocalError.message("The Phonon archive has no model manifest.")
        }
        _ = try PhononModels.install(bundled: manifest.deletingLastPathComponent(), to: directory)
    }
}
