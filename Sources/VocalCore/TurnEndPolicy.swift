import Foundation

/// A conservative, adjustable silence policy. It does not infer intent from
/// audio; stable transcription and detected microphone activity must agree.
public struct TurnEndPolicy {
    public init() {}

    public func shouldReply(text: String, silence: Double, textStableFor: Double, voicedSeconds: Double) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, voicedSeconds >= 0.06, textStableFor >= 0.25 else { return false }
        let last = text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).last.map(String.init) ?? ""
        let unfinished = ["and", "but", "because", "so", "to", "the", "a", "an", "of", "with", "if", "when", "i", "my"]
        let threshold: Double
        if unfinished.contains(last) || text.hasSuffix("...") || text.hasSuffix("…") {
            threshold = 1.35
        } else if text.last.map({ ".!?".contains($0) }) == true {
            threshold = 0.65
        } else {
            threshold = 0.85
        }
        return silence >= threshold
    }
}
