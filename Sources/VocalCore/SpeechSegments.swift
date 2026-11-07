import Foundation

/// Consumes cumulative LLM text. Prefer complete thoughts; let the first useful
/// clause start early without turning every comma into a separate utterance.
public struct SpeechSegments {
    private var emitted = ""
    private var hasSpoken = false
    public init() {}

    public mutating func append(snapshot: String, finished: Bool = false) -> [String] {
        guard snapshot.hasPrefix(emitted) else { return [] }
        let suffix = String(snapshot.dropFirst(emitted.count))
        let chars = Array(suffix)
        var result: [String] = []
        var pending = ""
        for (index, character) in chars.enumerated() {
            pending.append(character)
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            let followedBySpace = next?.isWhitespace == true
            let words = pending.split(whereSeparator: \.isWhitespace).count
            let sentenceEnd = ".!?".contains(character)
                && (followedBySpace || (finished && next == nil))
                && !Self.isAbbreviation(pending)
            let earlyClause = !hasSpoken && words >= 5 && pending.count >= 24
                && ",;:—".contains(character) && followedBySpace
            // A long unpunctuated first sentence must not delay speech forever.
            // Later chunks are longer to preserve rhythm once playback is underway.
            let overflow = character.isWhitespace && pending.count >= (hasSpoken ? 280 : 180)
            if sentenceEnd || earlyClause || overflow {
                emitted += pending
                let text = pending.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result.append(text); hasSpoken = true }
                pending = ""
            }
        }
        if finished {
            emitted += pending
            let text = pending.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(text); hasSpoken = true }
        }
        return result
    }

    private static func isAbbreviation(_ text: String) -> Bool {
        guard text.last == "." else { return false }
        let word = String(text.split(whereSeparator: \.isWhitespace).last ?? "").lowercased()
        if ["mr.", "mrs.", "ms.", "dr.", "prof.", "st.", "e.g.", "i.e.", "vs."].contains(word) { return true }
        // Preserve initials such as A. Smith.
        return word.count == 2 && word.first?.isLetter == true
    }
}
