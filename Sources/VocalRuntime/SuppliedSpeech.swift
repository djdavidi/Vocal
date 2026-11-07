import Foundation
import PhononTTS

public struct SuppliedVoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
}

struct SpeechChunk: Sendable {
    let samples: [Float]
    let generationElapsed: Double
}

/// Resident Phonon engine. Loading and synthesis use installed local files only.
actor SuppliedSpeech {
    private var phonon: Phonon?
    private var warmedVoices = Set<String>()

    func download() async throws { try await PhononAssets.download() }

    func load() async throws -> [SuppliedVoice] {
        if phonon == nil {
            guard PhononModels.isInstalled(at: PhononAssets.directory) else {
                throw VocalError.message("Install the supplied voices using Settings first.")
            }
            phonon = try await Phonon.load(models: PhononAssets.directory, language: .english)
        }
        return phonon!.voices.map { SuppliedVoice(id: $0, name: $0) }
    }

    func select(_ voice: String) async throws {
        guard let phonon else { throw VocalError.message("Load Phonon first.") }
        if phonon.voice != voice { try await phonon.setVoice(voice) }
    }

    func warmUp(voice: String) async throws {
        guard !warmedVoices.contains(voice) else { return }
        for text in ["Hi.", "Take your time. We can talk about whatever is on your mind."] {
            for try await _ in try stream(text) { try Task.checkCancellation() }
        }
        warmedVoices.insert(voice)
    }

    func stream(_ text: String) throws -> AsyncThrowingStream<SpeechChunk, Error> {
        guard let phonon else { throw VocalError.message("Load Phonon first.") }
        let start = ProcessInfo.processInfo.systemUptime
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await samples in phonon.stream(text) {
                        try Task.checkCancellation()
                        continuation.yield(SpeechChunk(samples: samples,
                            generationElapsed: ProcessInfo.processInfo.systemUptime - start))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
