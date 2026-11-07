import Foundation
import VocalRuntime

@main
struct EngineCheck {
    static func main() async throws {
        if CommandLine.arguments.contains("--download") { try await EngineDiagnostics.install() }
        if CommandLine.arguments.contains("--conversation") {
            let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("conversation-output")
            let index = CommandLine.arguments.firstIndex(of: "--label")
            let label = index.flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil } ?? "conversation"
            print(try await EngineDiagnostics.conversation(outputDirectory: output, label: label, prewarm: CommandLine.arguments.contains("--prewarm")))
        }
    }
}
