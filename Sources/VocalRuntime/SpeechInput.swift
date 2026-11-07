import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechInput {
    static let locale = Locale(identifier: "en-US")
    private var analyzer: SpeechAnalyzer?
    private var engine: AVAudioEngine?
    private var pipe: MicrophonePipe?
    private var results: Task<Void, Error>?
    private var finalText = ""
    private var partialText = ""

    var activity: (lastSpeech: Double?, voicedSeconds: Double) {
        let value = pipe?.snapshot()
        return (value?.lastSpeech, value?.voicedSeconds ?? 0)
    }

    static func installAssets() async throws {
        guard await SpeechTranscriber.supportedLocales.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) else { throw VocalError.message("English (US) on-device transcription is unavailable.") }
        try await AssetInventory.reserve(locale: locale)
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    static func requireInstalledAssets() async throws {
        guard await SpeechTranscriber.installedLocales.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) else { throw VocalError.message("Install the speech assets while online before starting an offline test.") }
    }

    func start(onText: @escaping (String) -> Void) async throws {
        await cancel()
        guard await AudioSession.permission() else { throw VocalError.message("Microphone access is required. Enable it in Settings.") }
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard permission else { throw VocalError.message("Speech recognition permission is required. Enable it in Settings.") }
        try await Self.requireInstalledAssets() // Never downloads on this path.
        try AudioSession.activate()
        finalText = ""
        partialText = ""
        let transcriber = SpeechTranscriber(locale: Self.locale, transcriptionOptions: [],
            reportingOptions: [.volatileResults], attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VocalError.message("No compatible transcription audio format.")
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let engine = AVAudioEngine()
        self.engine = engine
        let sourceFormat = engine.inputNode.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw VocalError.message("The microphone has no available audio input.")
        }
        let pipe = try MicrophonePipe(source: sourceFormat, target: format, continuation: continuation)
        self.pipe = pipe
        results = Task { [weak self] in
            for try await result in transcriber.results {
                guard let self else { return }
                if result.isFinal {
                    self.finalText += String(result.text.characters)
                    self.partialText = ""
                } else { self.partialText = String(result.text.characters) }
                onText(self.finalText + self.partialText)
            }
        }
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat) { buffer, _ in
            pipe.receive(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            await cancel()
            throw error
        }
    }

    func finish() async throws -> (text: String, speechEnd: Double?) {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        let speechEnd = pipe?.snapshot().lastSpeech
        let failure = pipe?.snapshot().failure
        pipe?.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        try await results?.value
        engine = nil
        analyzer = nil
        results = nil
        pipe = nil
        if let failure { throw VocalError.message(failure) }
        return ((finalText + partialText).trimmingCharacters(in: .whitespacesAndNewlines), speechEnd)
    }

    func cancel() async {
        engine?.stop()
        if engine != nil, pipe != nil { engine?.inputNode.removeTap(onBus: 0) }
        pipe?.finish()
        results?.cancel()
        await analyzer?.cancelAndFinishNow()
        results = nil
        analyzer = nil
        engine = nil
        pipe = nil
        finalText = ""
        partialText = ""
    }
}

/// Only the serial audio tap accesses the converter. A lock protects the small
/// status snapshot shared with the UI; no raw microphone audio is written to disk.
private final class MicrophonePipe: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let lock = NSLock()
    private var lastSpeech: Double?
    private var failure: String?
    private var voicedSeconds = 0.0

    init(source: AVAudioFormat, target: AVAudioFormat,
         continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        guard let converter = AVAudioConverter(from: source, to: target) else {
            throw VocalError.message("Could not create the microphone sample-rate converter.")
        }
        converter.primeMethod = .none
        self.converter = converter
        self.target = target
        self.continuation = continuation
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        // A simple level-based estimate, NOT semantic voice activity detection.
        // End timestamp is corrected for the captured buffer's duration.
        if let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            let count = Int(buffer.frameLength)
            let rms = sqrt((0..<count).reduce(Float(0)) { $0 + channel[$1] * channel[$1] } / Float(count))
            if rms > 0.008 {
                var last = count - 1
                while last > 0 && abs(channel[last]) < 0.008 { last -= 1 }
                let end = ProcessInfo.processInfo.systemUptime - Double(count - 1 - last) / buffer.format.sampleRate
                lock.lock()
                lastSpeech = end
                voicedSeconds += Double(count) / buffer.format.sampleRate
                lock.unlock()
            }
        }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate))
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            lock.lock(); failure = error?.localizedDescription ?? "Microphone conversion failed."; lock.unlock()
            continuation.finish()
        } else if output.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: output))
        }
    }
    func snapshot() -> (lastSpeech: Double?, failure: String?, voicedSeconds: Double) {
        lock.lock(); defer { lock.unlock() }
        return (lastSpeech, failure, voicedSeconds)
    }
    func finish() { continuation.finish() }
}
