import Foundation

public enum RecallMode: String, Codable, CaseIterable, Sendable {
    /// Each word shown only by its first letter.
    case firstLetter
    /// Some words blanked out.
    case cloze
    /// Typed entirely from memory.
    case fullRecitation

    public var title: String {
        switch self {
        case .firstLetter: "First letters"
        case .cloze: "Fill the gaps"
        case .fullRecitation: "From memory"
        }
    }

    /// Harder modes unlock as the card matures.
    public static func suggested(for state: SM2State) -> RecallMode {
        switch state.repetitions {
        case 0...1: .firstLetter
        case 2...3: .cloze
        default: .fullRecitation
        }
    }
}

public enum RecallText {
    /// Splits text into words, keeping punctuation attached so display is natural.
    public static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Lowercased word with punctuation and curly quotes removed; used for comparison.
    public static func normalize(_ word: String) -> String {
        let folded = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    public static func normalizedWords(_ text: String) -> [String] {
        tokens(text).map(normalize).filter { !$0.isEmpty }
    }

    /// "For God so loved" -> "F G s l" (punctuation kept).
    public static func firstLetters(_ text: String) -> String {
        tokens(text).map { token -> String in
            var out = ""
            var tookLetter = false
            for ch in token {
                if ch.isLetter || ch.isNumber {
                    if !tookLetter { out.append(ch); tookLetter = true }
                } else {
                    out.append(ch)
                }
            }
            return out
        }.joined(separator: " ")
    }

    public struct ClozeItem: Equatable, Sendable {
        public let word: String
        public let hidden: Bool
    }

    /// Hides roughly `fraction` of the words (preferring longer ones), deterministically for a seed.
    public static func cloze(_ text: String, fraction: Double = 0.35, seed: UInt64) -> [ClozeItem] {
        let words = tokens(text)
        guard !words.isEmpty else { return [] }
        var rng = SplitMix64(seed: seed)
        let candidates = words.indices.filter { normalize(words[$0]).count >= 3 }
        let pool = candidates.isEmpty ? Array(words.indices) : candidates
        let count = max(1, Int((Double(words.count) * fraction).rounded()))
        var shuffled = pool
        for i in stride(from: shuffled.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            shuffled.swapAt(i, j)
        }
        let hidden = Set(shuffled.prefix(count))
        return words.enumerated().map { ClozeItem(word: $1, hidden: hidden.contains($0)) }
    }
}

/// Grades typed recall against the verse by word-level longest common subsequence.
public enum RecallGrader {
    /// Fraction of the target's words recalled in order (0...1). Extra words reduce the score slightly.
    public static func accuracy(typed: String, target: String) -> Double {
        let a = RecallText.normalizedWords(typed)
        let b = RecallText.normalizedWords(target)
        guard !b.isEmpty else { return 0 }
        guard !a.isEmpty else { return 0 }
        let lcs = lcsLength(a, b)
        let recall = Double(lcs) / Double(b.count)
        let precision = Double(lcs) / Double(a.count)
        // Weighted toward recall: forgetting words matters more than adding one.
        return 0.8 * recall + 0.2 * precision
    }

    /// Maps accuracy to an SM-2 quality score (0...5).
    public static func quality(accuracy: Double) -> Int {
        switch accuracy {
        case 0.98...: 5
        case 0.90..<0.98: 4
        case 0.75..<0.90: 3
        case 0.50..<0.75: 2
        case 0.25..<0.50: 1
        default: 0
        }
    }

    /// Cloze grading: share of blanks filled with the right word.
    public static func clozeAccuracy(answers: [String], expected: [String]) -> Double {
        guard !expected.isEmpty else { return 1 }
        let correct = zip(answers, expected).filter { RecallText.normalize($0) == RecallText.normalize($1) }.count
        return Double(correct) / Double(expected.count)
    }

    static func lcsLength(_ a: [String], _ b: [String]) -> Int {
        var prev = [Int](repeating: 0, count: b.count + 1)
        var cur = prev
        for i in 1...a.count {
            for j in 1...b.count {
                cur[j] = a[i - 1] == b[j - 1] ? prev[j - 1] + 1 : max(prev[j], cur[j - 1])
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}

/// Small deterministic PRNG so rotations and cloze blanks are stable per day.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension DayKey {
    /// A stable seed for "today's" rotations.
    public var seed: UInt64 { UInt64(year * 10_000 + month * 100 + day) }
}
