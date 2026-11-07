import Foundation
import VocalCore

public enum EngineDiagnostics {
    public static func install() async throws {
        try LocalStorage.prepare()
        try await LocalLanguageModel.download { _ in }
        try await SuppliedSpeech().download()
    }

    public static func conversation(outputDirectory: URL, label: String, prewarm: Bool = false) async throws -> String {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let speech = SuppliedSpeech()
        let choices = try await speech.load()
        let selected = choices.first { $0.id == "Juniper" } ?? choices.first!
        try await speech.select(selected.id)
        try await speech.warmUp(voice: selected.id)
        let language = LocalLanguageModel()
        try await language.load()
        if prewarm { try await language.prewarm() }
        let prompts = [
            "I've had a long day. I don't want advice, just a little company.",
            "Can we talk about something ordinary instead?",
            "Tell me one interesting thing about octopuses, briefly.",
            "My sister Maya is visiting on Friday. I'm looking forward to it.",
            "What was my sister's name, and when is she visiting?",
            "Everything feels like too much today. Please don't tell me to breathe or relax.",
            "That wasn't quite what I meant. I'm more annoyed than anxious.",
            "Just a short reply, please."
        ]
        var rows: [[String: Any]] = []
        for (index, prompt) in prompts.enumerated() {
            let start = ProcessInfo.processInfo.systemUptime
            let (segments, continuation) = AsyncThrowingStream<String, Error>.makeStream()
            let producer = Task { () throws -> (String, Double) in
                do {
                    var segmenter = SpeechSegments()
                    var latest = ""
                    var first = 0.0
                    for try await text in language.streamResponse(to: prompt) {
                        if first == 0 { first = ProcessInfo.processInfo.systemUptime - start }
                        latest = text
                        for segment in segmenter.append(snapshot: text) { continuation.yield(segment) }
                    }
                    for segment in segmenter.append(snapshot: latest, finished: true) { continuation.yield(segment) }
                    continuation.finish()
                    return (latest, first)
                } catch { continuation.finish(throwing: error); throw error }
            }
            var firstSegment: Double?
            var firstPCM: Double?
            var samples = 0
            do {
                for try await segment in segments {
                    if firstSegment == nil { firstSegment = ProcessInfo.processInfo.systemUptime - start }
                    for try await chunk in try await speech.stream(segment) {
                        if firstPCM == nil { firstPCM = ProcessInfo.processInfo.systemUptime - start }
                        guard chunk.samples.allSatisfy(\.isFinite) else { throw VocalError.message("Invalid PCM output.") }
                        samples += chunk.samples.count
                    }
                }
                let (reply, firstText) = try await producer.value
                guard samples > 0 else { throw VocalError.message("No speech generated.") }
                rows.append(["turn": index + 1, "prompt": prompt, "reply": reply,
                    "firstTextMS": firstText * 1000, "firstSegmentMS": (firstSegment ?? 0) * 1000,
                    "firstPCM_MS": (firstPCM ?? 0) * 1000, "audioSeconds": Double(samples) / 24000,
                    "promptTokens": await language.lastPromptTokens, "reusedTokens": await language.lastReusedTokens])
                print("Turn \(index + 1): \(Int((firstPCM ?? 0) * 1000)) ms to first PCM. \(reply)")
            } catch { producer.cancel(); throw error }
        }
        let data = try JSONSerialization.data(withJSONObject: ["label": label, "results": rows,
            "note": "Synthetic text only. Full LFM-to-Phonon generation without microphone or playback. First PCM is not audible latency."], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputDirectory.appendingPathComponent("\(label).json"))
        return String(decoding: data, as: UTF8.self)
    }
}
