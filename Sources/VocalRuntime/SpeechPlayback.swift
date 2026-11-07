import AVFoundation
import Foundation

@MainActor
final class SpeechPlayback {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private var pending = 0
    private var scheduledFrames: Int64 = 0
    private var firstSignalFrame: Int64?
    private var epoch = UUID()
    private(set) var gaps = 0
    var hasPendingAudio: Bool { pending > 0 }

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func begin() throws {
        stop()
        try AudioSession.activate()
        engine.prepare()
        try engine.start()
    }

    func enqueue(_ samples: [Float]) throws {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)), let channel = buffer.floatChannelData?[0] else {
            throw VocalError.message("The speech engine returned an empty audio buffer.")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        if firstSignalFrame == nil, let index = samples.firstIndex(where: { abs($0) > 0.003 }) {
            firstSignalFrame = scheduledFrames + Int64(index)
        }
        if scheduledFrames > 0 && pending == 0 { gaps += 1 }
        scheduledFrames += Int64(samples.count)
        pending += 1
        let currentEpoch = epoch
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.epoch == currentEpoch else { return }
                self.pending -= 1
            }
        }
        if !player.isPlaying { player.play() }
    }

    /// Render timeline + route presentation latency + leading quiet samples.
    /// This estimates audible onset; it is not an acoustic loopback measurement.
    func estimatedOnset() -> Double? {
        guard let signal = firstSignalFrame, let nodeTime = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: nodeTime), nodeTime.isHostTimeValid else { return nil }
        let clockOffset = ProcessInfo.processInfo.systemUptime - AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let renderedAt = AVAudioTime.seconds(forHostTime: nodeTime.hostTime) + clockOffset
        return renderedAt + Double(signal - time.sampleTime) / format.sampleRate
            + engine.outputNode.presentationLatency
    }

    func drain() async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 120
        while pending > 0 {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw VocalError.message("Audio playback did not complete. Check the output route and retry.")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func stop() {
        epoch = UUID()
        player.stop()
        engine.stop()
        pending = 0
        scheduledFrames = 0
        firstSignalFrame = nil
        gaps = 0
    }
}
