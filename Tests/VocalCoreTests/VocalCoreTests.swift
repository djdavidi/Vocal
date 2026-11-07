import Foundation
import VocalCore

func cumulativeStreamingDoesNotRepeatSpokenText() {
    var segments = SpeechSegments()
    precondition(segments.append(snapshot: "That sounds") == [])
    precondition(segments.append(snapshot: "That sounds hard.") == [])
    precondition(segments.append(snapshot: "That sounds hard. I'm here") == ["That sounds hard."])
    precondition(segments.append(snapshot: "That sounds hard. I'm here") == [])
    precondition(segments.append(snapshot: "That sounds hard. I'm here with you.", finished: true) == ["I'm here with you."])
}

func partialSentenceFlushesAtEnd() {
    var segments = SpeechSegments()
    precondition(segments.append(snapshot: "Tell me more") == [])
    precondition(segments.append(snapshot: "Tell me more", finished: true) == ["Tell me more"])
    precondition(segments.append(snapshot: "Tell me more", finished: true) == [])
}

func longResponsesStartBeforeFullSentenceFinishes() {
    var segments = SpeechSegments()
    let text = String(repeating: "word ", count: 40)
    let first = segments.append(snapshot: text)
    precondition(first.count == 1)
    let rest = segments.append(snapshot: text, finished: true)
    precondition((first + rest).joined(separator: " ") == text.trimmingCharacters(in: .whitespaces))
}

func latencySeparatesManualDelayFromPipeline() {
    var metrics = TurnMetrics(turn: 1, sendTime: 10, estimatedSpeechEnd: 9,
                              thermalState: "nominal", outputRoute: "speaker")
    metrics.estimatedAudibleOnset = 11.25
    precondition(metrics.buttonToAudioMS == 1250)
    precondition(metrics.speechToAudioMS == 2250)
    precondition(TurnMetrics.percentile([], fraction: 0.95) == nil)
    precondition(TurnMetrics.percentile([300, 100, 200, 400], fraction: 0.5) == 200)
    precondition(TurnMetrics.percentile([300, 100, 200, 400], fraction: 0.95) == 400)
}

func unknownSpeechEndIsNotReplacedWithButtonTime() {
    var metrics = TurnMetrics(turn: 1, sendTime: 10, estimatedSpeechEnd: nil,
                              thermalState: "nominal", outputRoute: "speaker")
    metrics.estimatedAudibleOnset = 11
    precondition(metrics.buttonToAudioMS == 1000)
    precondition(metrics.speechToAudioMS == nil)
}

func clausesStreamWithoutRepeating() {
    var segments = SpeechSegments()
    let clause = "If you want some company, "
    precondition(segments.append(snapshot: clause + "we") == ["If you want some company,"])
    precondition(segments.append(snapshot: clause + "we can chat.", finished: true) == ["we can chat."])
    precondition(segments.append(snapshot: clause + "we can chat.", finished: true).isEmpty)
}

func abbreviationsAndDecimalsStayTogether() {
    var segments = SpeechSegments()
    precondition(segments.append(snapshot: "Dr. Smith measured 3.5 cm. Next") == ["Dr. Smith measured 3.5 cm."])
    precondition(segments.append(snapshot: "Dr. Smith measured 3.5 cm. Next", finished: true) == ["Next"])
}

func automaticTurnsWaitForSpeechAndStableText() {
    let policy = TurnEndPolicy()
    precondition(!policy.shouldReply(text: "", silence: 10, textStableFor: 10, voicedSeconds: 1))
    precondition(!policy.shouldReply(text: "Hello.", silence: 10, textStableFor: 10, voicedSeconds: 0))
    precondition(!policy.shouldReply(text: "Hello.", silence: 1, textStableFor: 0.1, voicedSeconds: 1))
    precondition(!policy.shouldReply(text: "Hello.", silence: 0.6, textStableFor: 1, voicedSeconds: 1))
    precondition(policy.shouldReply(text: "Hello.", silence: 0.7, textStableFor: 1, voicedSeconds: 1))
    precondition(!policy.shouldReply(text: "I wanted to", silence: 1, textStableFor: 1, voicedSeconds: 1))
    precondition(policy.shouldReply(text: "I wanted to", silence: 1.4, textStableFor: 1, voicedSeconds: 1))
    precondition(!policy.shouldReply(text: "Tell me more", silence: 0.7, textStableFor: 1, voicedSeconds: 1))
    precondition(policy.shouldReply(text: "Tell me more", silence: 0.9, textStableFor: 1, voicedSeconds: 1))
}

@main
struct CoreChecks {
    static func main() {
        cumulativeStreamingDoesNotRepeatSpokenText()
        partialSentenceFlushesAtEnd()
        longResponsesStartBeforeFullSentenceFinishes()
        latencySeparatesManualDelayFromPipeline()
        unknownSpeechEndIsNotReplacedWithButtonTime()
        clausesStreamWithoutRepeating()
        abbreviationsAndDecimalsStayTogether()
        automaticTurnsWaitForSpeechAndStableText()
        print("Passed all 8 streaming, turn-taking and latency checks.")
    }
}
