import Foundation

enum LocalStorage {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vocal", isDirectory: true)
    }
    static var hfHome: URL { root.appendingPathComponent("Models", isDirectory: true) }

    static func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        // Voice samples are ephemeral, including after an interrupted previous launch.
        for url in try FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory,
                                                               includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix("vocal-voice-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

enum VocalError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
