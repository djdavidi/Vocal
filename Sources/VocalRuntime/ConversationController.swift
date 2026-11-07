import Foundation
import Observation
import VocalCore

@MainActor @Observable
public final class ConversationController {
    public enum Phase: String {
        case idle = "Ready", setup = "Installing models", loading = "Loading local models"
        case startingMic = "Starting microphone", listening = "Listening"
        case responding = "Generating response", speaking = "Speaking", stopping = "Stopping"
    }
    public private(set) var phase: Phase = .idle
    public private(set) var status = "Preparing your offline conversation…"
    public private(set) var voiceID = ""
    public private(set) var availableVoices: [SuppliedVoice] = []
    public private(set) var modelsPrepared = false
    public private(set) var userText = ""
    public private(set) var responseText = ""
    public private(set) var metrics: [TurnMetrics] = []
    public private(set) var loadSeconds: Double?
    public private(set) var exportURL: URL?
    public private(set) var automaticConversation = false
    public var typedPrompt = ""
    public var canTalk: Bool { idle && modelsPrepared && !voiceID.isEmpty }
    public var idle: Bool { phase == .idle }
    @ObservationIgnored private let voices = SuppliedSpeech()
    @ObservationIgnored private let speech = SpeechInput()
    @ObservationIgnored private let playback = SpeechPlayback()
    @ObservationIgnored private let language = LocalLanguageModel()
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var turnWatcher: Task<Void, Never>?
    @ObservationIgnored private var lastTextChange = 0.0
    @ObservationIgnored private let turnPolicy = TurnEndPolicy()
    @ObservationIgnored private var activeMetric: TurnMetrics?
    @ObservationIgnored private var spokenKeys = Set<String>()

    public init() {
        do { try LocalStorage.prepare() } catch { status = error.localizedDescription }
    }

    public func downloadAssets() {
        guard idle else { return }
        phase = .setup
        status = "Checking the local LFM model…"
        operation = Task {
            do {
                try await LocalLanguageModel.download { _ in }
                status = "Installing Phonon and its supplied voices…"
                try await voices.download()
                try Task.checkCancellation()
                status = "Preparing English speech-recognition assets…"
                try await SpeechInput.installAssets()
                try await prepareSelectedVoice()
                try await language.prewarm()
                modelsPrepared = true
                status = "Ready. Start talking, or type a message."
            } catch { report(error) }
            phase = .idle
        }
    }

    public func prepareOffline() {
        guard idle else { return }
        phase = .loading
        status = "Loading local models. First-use preparation can take longer."
        operation = Task {
            let start = ProcessInfo.processInfo.systemUptime
            do {
                try await SpeechInput.requireInstalledAssets()
                try await prepareSelectedVoice()
                try await language.prewarm()
                try Task.checkCancellation()
                modelsPrepared = true
                loadSeconds = ProcessInfo.processInfo.systemUptime - start
                status = "Ready. Start talking, or type a message."
            } catch { report(error) }
            phase = .idle
        }
    }

    public func setVoice(_ selected: String) {
        guard idle, availableVoices.contains(where: { $0.id == selected }) else { return }
        voiceID = selected
        phase = .loading
        status = "Preparing the selected voice…"
        operation = Task {
            let start = ProcessInfo.processInfo.systemUptime
            do {
                try await voices.select(selected)
                try await voices.warmUp(voice: selected)
                spokenKeys.insert(selected)
                loadSeconds = ProcessInfo.processInfo.systemUptime - start
                UserDefaults.standard.set(selected, forKey: "suppliedVoice")
                status = "Voice ready."
            } catch { report(error) }
            phase = .idle
        }
    }

    private func prepareSelectedVoice() async throws {
        availableVoices = try await voices.load()
        let saved = UserDefaults.standard.string(forKey: "suppliedVoice")
        // Prefer conversational female voices when the release contains named voices.
        let preferred = ["juniper", "zoey", "harper", "everly"]
            .compactMap { preferred in availableVoices.first { $0.id.lowercased().contains(preferred) } }.first
        guard let selected = availableVoices.first(where: { $0.id == saved }) ?? preferred ?? availableVoices.first else {
            throw VocalError.message("This model bundle has no supplied voices.")
        }
        voiceID = selected.id
        UserDefaults.standard.set(selected.id, forKey: "suppliedVoice")
        try await voices.select(selected.id)
        status = "Warming Phonon. This first-use cost is counted as preparation…"
        try await voices.warmUp(voice: selected.id)
        spokenKeys.insert(selected.id)
    }

    public func replayLastReply() { playText(responseText, mode: "replay") }

    private func playText(_ text: String, mode: String) {
        guard idle, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        phase = .loading
        status = "Preparing Phonon…"
        operation = Task {
            do {
                let loadStart = ProcessInfo.processInfo.systemUptime
                try await prepareSelectedVoice()
                try Task.checkCancellation()
                loadSeconds = ProcessInfo.processInfo.systemUptime - loadStart
                beginMetric(mode: mode, send: ProcessInfo.processInfo.systemUptime, speechEnd: nil)
                try playback.begin()
                phase = .speaking
                status = "Speaking with Phonon…"
                var segmenter = SpeechSegments()
                for sentence in segmenter.append(snapshot: text, finished: true) { try await speak(sentence) }
                try await finishPlayback()
                status = "Finished. Ready when you are."
            } catch {
                failMetric()
                report(error)
            }
            playback.stop()
            phase = .idle
        }
    }

    public func startListening() {
        guard canTalk else { return }
        phase = .startingMic
        userText = ""
        status = "Starting on-device transcription…"
        operation = Task {
            do {
                lastTextChange = ProcessInfo.processInfo.systemUptime
                try await speech.start { [weak self] text in
                    guard let self else { return }
                    if self.userText != text { self.lastTextChange = ProcessInfo.processInfo.systemUptime }
                    self.userText = text
                }
                try Task.checkCancellation()
                phase = .listening
                status = automaticConversation ? "Listening. Take your time." : "Speak, then tap Send."
                if automaticConversation { watchForEndOfTurn() }
            } catch {
                automaticConversation = false
                turnWatcher?.cancel()
                await speech.cancel()
                report(error)
                phase = .idle
            }
        }
    }

    public func sendTurn() {
        guard phase == .listening else { return }
        turnWatcher?.cancel()
        turnWatcher = nil
        let send = ProcessInfo.processInfo.systemUptime
        phase = .responding
        status = "Finalizing transcription…"
        operation = Task {
            do {
                let transcript = try await speech.finish()
                try Task.checkCancellation()
                try await conversation(text: transcript.text, send: send, speechEnd: transcript.speechEnd)
            } catch { await failConversation(error) }
            playback.stop()
            await speech.cancel()
            if automaticConversation {
                // Keep controls busy while the speaker tail decays.
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard automaticConversation, !Task.isCancelled else { return }
                phase = .idle
                startListening()
            } else if !Task.isCancelled {
                phase = .idle
            }
        }
    }

    public func sendTypedPrompt() {
        guard canTalk else { return }
        let text = typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedPrompt = ""
        phase = .responding
        operation = Task {
            do { try await conversation(text: text, send: ProcessInfo.processInfo.systemUptime, speechEnd: nil) }
            catch { await failConversation(error) }
            playback.stop()
            phase = .idle
        }
    }

    public func startConversation() {
        guard canTalk else { return }
        automaticConversation = true
        startListening()
    }

    private func watchForEndOfTurn() {
        turnWatcher?.cancel()
        turnWatcher = Task {
            while !Task.isCancelled, automaticConversation, phase == .listening {
                let now = ProcessInfo.processInfo.systemUptime
                let activity = speech.activity
                if let last = activity.lastSpeech,
                   turnPolicy.shouldReply(text: userText, silence: now - last,
                       textStableFor: now - lastTextChange, voicedSeconds: activity.voicedSeconds) {
                    sendTurn()
                    return
                }
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
    }

    private func conversation(text: String, send: Double, speechEnd: Double?) async throws {
        guard !text.isEmpty else { throw VocalError.message("No speech was recognized. Start the conversation again to retry.") }
        userText = text
        responseText = ""
        beginMetric(mode: speechEnd == nil ? "typed conversation" : "spoken conversation", send: send, speechEnd: speechEnd)
        activeMetric?.transcriptReady = ProcessInfo.processInfo.systemUptime
        try playback.begin()
        status = "LFM is generating a local reply…"
        let (segments, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let producer = Task { @MainActor in
            do {
                var segmenter = SpeechSegments()
                var latest = ""
                for try await snapshot in language.streamResponse(to: text) {
                    try Task.checkCancellation()
                    latest = snapshot
                    responseText = snapshot
                    if !snapshot.isEmpty, activeMetric?.firstModelText == nil {
                        activeMetric?.firstModelText = ProcessInfo.processInfo.systemUptime
                    }
                    for sentence in segmenter.append(snapshot: snapshot) { continuation.yield(sentence) }
                }
                for sentence in segmenter.append(snapshot: latest, finished: true) { continuation.yield(sentence) }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
        defer { producer.cancel() }
        do {
            for try await sentence in segments { try await speak(sentence) }
            if Task.isCancelled { producer.cancel() }
            await producer.value
            try await finishPlayback()
            status = "I’m listening when you’re ready."
        } catch {
            producer.cancel()
            await producer.value
            throw error
        }
    }

    private func speak(_ text: String) async throws {
        try Task.checkCancellation()
        if activeMetric?.firstSpeechSegment == nil { activeMetric?.firstSpeechSegment = ProcessInfo.processInfo.systemUptime }
        var previousElapsed = 0.0
        for try await chunk in try await voices.stream(text) {
            try Task.checkCancellation()
            if activeMetric?.firstPCM == nil { activeMetric?.firstPCM = ProcessInfo.processInfo.systemUptime }
            activeMetric?.audioSeconds += Double(chunk.samples.count) / 24000
            activeMetric?.ttsComputeSeconds += max(0, chunk.generationElapsed - previousElapsed)
            previousElapsed = chunk.generationElapsed
            try playback.enqueue(chunk.samples)
            phase = .speaking
            status = "Speaking…"
            // Do not stall the producer to poll playback: streaming engines may
            // deliver 80 ms frames faster than real time. Read onset opportunistically.
            if activeMetric?.estimatedAudibleOnset == nil { activeMetric?.estimatedAudibleOnset = playback.estimatedOnset() }
        }
    }

    private func finishPlayback() async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 120
        while activeMetric?.estimatedAudibleOnset == nil, playback.hasPendingAudio {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw VocalError.message("Audio playback did not start. Check the output device and retry.") }
            activeMetric?.estimatedAudibleOnset = playback.estimatedOnset()
            if activeMetric?.estimatedAudibleOnset == nil { try await Task.sleep(for: .milliseconds(5)) }
        }
        try await playback.drain()
        try Task.checkCancellation()
        guard activeMetric?.estimatedAudibleOnset != nil else { throw VocalError.message("No audible speech onset was detected.") }
        activeMetric?.completed = ProcessInfo.processInfo.systemUptime
        activeMetric?.playbackGaps = playback.gaps
        activeMetric?.status = "complete"
        spokenKeys.insert(voiceID)
        commitMetric()
    }

    private func beginMetric(mode: String, send: Double, speechEnd: Double?) {
        let key = voiceID
        activeMetric = TurnMetrics(turn: metrics.count + 1, sendTime: send, estimatedSpeechEnd: speechEnd,
            thermalState: String(describing: ProcessInfo.processInfo.thermalState), outputRoute: AudioSession.route,
            engine: "Phonon", voice: voiceID, mode: mode, warm: spokenKeys.contains(key))
    }
    private func failMetric() {
        activeMetric?.status = Task.isCancelled ? "cancelled" : "failed"
        commitMetric()
    }
    private func failConversation(_ error: Error) async {
        automaticConversation = false
        turnWatcher?.cancel()
        failMetric()
        await language.reset()
        report(error)
        if !Task.isCancelled { status += " Conversation context was reset." }
    }

    public func stop() {
        guard phase != .stopping else { return }
        automaticConversation = false
        turnWatcher?.cancel()
        turnWatcher = nil
        let previous = operation
        phase = .stopping
        previous?.cancel()
        playback.stop()
        operation = Task {
            await speech.cancel()
            await previous?.value
            await language.reset()
            userText = ""
            responseText = ""
            phase = .idle
            status = "Stopped. Conversation context cleared."
        }
    }
    public func shutdown() async {
        automaticConversation = false
        turnWatcher?.cancel()
        operation?.cancel()
        playback.stop()
        await speech.cancel()
        await operation?.value
        await language.unload()
    }

    public func newConversation() {
        guard idle else { return }
        automaticConversation = false
        turnWatcher?.cancel()
        phase = .loading
        operation = Task {
            await language.reset()
            userText = ""
            responseText = ""
            phase = .idle
            status = "Conversation cleared."
        }
    }
    public func exportMetrics() {
        do {
            struct Report: Encodable {
                let generatedAt: Date
                let os: String
                let llm: String
                let note: String
                let modelLoadSeconds: Double?
                let turns: [TurnMetrics]
            }
            let report = Report(generatedAt: Date(), os: ProcessInfo.processInfo.operatingSystemVersionString,
                llm: LocalLanguageModel.identity,
                note: "Local Phonon conversation. Automatic turns use stable text and 0.65–1.35 s of level-detected silence. This is a heuristic, not semantic end-of-turn detection. No audio or transcript. Each turn identifies engine, supplied voice, test mode, and warm status. Voices are explicitly warmed with discarded audio during preparation before Ready. First PCM is not audible onset. Audible onset is estimated from render timing, leading silence and output route latency; speech end is a level estimate. ttsComputeSeconds is measured generation wall time, not accelerator-only compute. Sample and replay timings exclude model/voice loading and warm-up. Monotonic timestamps are seconds since boot.",
                modelLoadSeconds: loadSeconds, turns: metrics)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("vocal-latency.json")
            try encoder.encode(report).write(to: url, options: .atomic)
            exportURL = url
        } catch { report(error) }
    }
    private func commitMetric() {
        if let activeMetric { metrics.append(activeMetric) }
        activeMetric = nil
    }
    private func report(_ error: Error) {
        if !Task.isCancelled { status = error.localizedDescription }
    }
}
