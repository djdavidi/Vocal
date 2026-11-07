import Foundation

public struct TurnMetrics: Codable, Identifiable, Sendable {
    public let id: UUID
    public let turn: Int
    public let sendTime: Double
    public let estimatedSpeechEnd: Double?
    public var transcriptReady: Double?
    public var firstModelText: Double?
    public var firstSpeechSegment: Double?
    public var firstPCM: Double?
    public var estimatedAudibleOnset: Double?
    public var completed: Double?
    public var audioSeconds: Double = 0
    public var ttsComputeSeconds: Double = 0
    public var playbackGaps: Int = 0
    public var thermalState: String
    public var outputRoute: String
    public var status: String = "running"
    public var engine: String
    public var voice: String
    public var mode: String
    public var warm: Bool

    public init(turn: Int, sendTime: Double, estimatedSpeechEnd: Double?,
                thermalState: String, outputRoute: String,
                engine: String = "unknown", voice: String = "unknown", mode: String = "conversation", warm: Bool = false) {
        id = UUID()
        self.turn = turn
        self.sendTime = sendTime
        self.estimatedSpeechEnd = estimatedSpeechEnd
        self.thermalState = thermalState
        self.outputRoute = outputRoute
        self.engine = engine
        self.voice = voice
        self.mode = mode
        self.warm = warm
    }

    public var buttonToAudioMS: Double? { estimatedAudibleOnset.map { ($0 - sendTime) * 1000 } }
    public var speechToAudioMS: Double? {
        guard let onset = estimatedAudibleOnset, let end = estimatedSpeechEnd else { return nil }
        return (onset - end) * 1000
    }
    public static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(ceil(fraction * Double(sorted.count))) - 1))
        return sorted[index]
    }
}
