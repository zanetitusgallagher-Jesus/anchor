import Foundation

/// A reading plan: an ordered list of days, each a list of chapters.
/// Seed plans ship as JSON in `Resources/Plans`; custom plans are generated.
public struct ReadingPlan: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let days: [[ChapterRef]]

    public init(id: String, name: String, summary: String, days: [[ChapterRef]]) {
        self.id = id
        self.name = name
        self.summary = summary
        self.days = days
    }
}

public enum ReadingPlanGenerator {
    /// Splits `chapters` (kept in order) into `days` consecutive groups whose
    /// weights (typically verse counts) are as even as possible. Every day gets
    /// at least one chapter when there are at least as many chapters as days.
    public static func split(_ chapters: [ChapterRef], weights: [Double]? = nil, days requested: Int) -> [[ChapterRef]] {
        guard !chapters.isEmpty, requested > 0 else { return [] }
        let w = weights ?? Array(repeating: 1, count: chapters.count)
        precondition(w.count == chapters.count)
        let days = min(requested, chapters.count)
        let total = w.reduce(0, +)

        var result: [[ChapterRef]] = []
        var i = 0
        var cumulative = 0.0
        for d in 0..<days {
            let remainingDays = days - d - 1
            let target = total * Double(d + 1) / Double(days)
            var today: [ChapterRef] = []
            // Always take at least one chapter.
            repeat {
                today.append(chapters[i])
                cumulative += w[i]
                i += 1
            } while i < chapters.count
                && chapters.count - i > remainingDays
                && (d == days - 1 || cumulative + w[i] / 2 <= target)
            result.append(today)
        }
        // Anything left (only possible through rounding) goes on the final day.
        if i < chapters.count { result[result.count - 1].append(contentsOf: chapters[i...]) }
        return result
    }

    public static func custom(id: String = "custom", name: String, bookIDs: [String], days: Int, bible: Bible? = nil) -> ReadingPlan {
        let chapters = BookCatalog.chapters(of: bookIDs)
        let weights = bible.map { b in chapters.map { Double(max(1, b.verses($0).count)) } }
        return ReadingPlan(id: id, name: name, summary: "\(bookIDs.count) book(s) over \(days) days",
                           days: split(chapters, weights: weights, days: days))
    }
}

extension ReadingPlanGenerator {
    public static let shuffledPrefix = "shuffled-"

    /// The id of a shuffled whole-Bible plan for a seed.
    public static func shuffledID(seed: UInt64) -> String { "\(shuffledPrefix)\(seed)" }

    public static func seed(fromShuffledID id: String) -> UInt64? {
        guard id.hasPrefix(shuffledPrefix) else { return nil }
        return UInt64(id.dropFirst(shuffledPrefix.count))
    }

    /// The whole Bible in a random order: every chapter is cut into passages of
    /// at most `maxVerses`, the passages are shuffled (deterministically for
    /// `seed`), and then grouped into `days` days of roughly equal length.
    /// Each day lists its passages in canonical order. Every verse is read
    /// exactly once by the last day.
    ///
    /// - Parameter verseCounts: verses per chapter, `[bookID: [count per chapter]]`.
    public static func shuffledWholeBible(verseCounts: [String: [Int]], days: Int = 365, seed: UInt64,
                                          maxVerses: Int = 25) -> ReadingPlan {
        var passages: [(ref: ChapterRef, weight: Double)] = []
        for book in BookCatalog.all {
            guard let counts = verseCounts[book.id] else { continue }
            for (ci, n) in counts.enumerated() where n > 0 {
                let parts = Int((Double(n) / Double(maxVerses)).rounded(.up))
                for p in 0..<parts {
                    let start = p * n / parts + 1
                    let end = (p + 1) * n / parts
                    let ref = parts == 1
                        ? ChapterRef(bookID: book.id, chapter: ci + 1)
                        : ChapterRef(bookID: book.id, chapter: ci + 1,
                                     verseStart: start, verseEnd: p == parts - 1 ? nil : end)
                    passages.append((ref, Double(end - start + 1)))
                }
            }
        }
        var rng = SplitMix64(seed: seed)
        for i in stride(from: passages.count - 1, to: 0, by: -1) {
            passages.swapAt(i, Int(rng.next() % UInt64(i + 1)))
        }
        let grouped = split(passages.map(\.ref), weights: passages.map(\.weight), days: days)
        let ordered = grouped.map { day in
            day.sorted { a, b in
                (BookCatalog.order(a.bookID), a.chapter, a.verseStart ?? 0) < (BookCatalog.order(b.bookID), b.chapter, b.verseStart ?? 0)
            }
        }
        return ReadingPlan(id: shuffledID(seed: seed), name: "Whole Bible, Shuffled",
                           summary: "Every verse of the Bible in \(days) days, as a fresh mix of passages from across Scripture each day.",
                           days: ordered)
    }

    public static func verseCounts(of bible: Bible) -> [String: [Int]] {
        Dictionary(uniqueKeysWithValues: bible.books.map { ($0.id, $0.chapters.map(\.count)) })
    }
}

/// Progress through a plan is tracked by completed day indices, not by calendar
/// date: missing a day never skips a reading, it just shifts the finish date.
public struct PlanProgress: Codable, Equatable, Sendable {
    public var planID: String
    public var completedDays: Set<Int>

    public init(planID: String, completedDays: Set<Int> = []) {
        self.planID = planID
        self.completedDays = completedDays
    }

    /// The first day not yet completed, or nil when the plan is finished.
    public func nextDayIndex(totalDays: Int) -> Int? {
        (0..<totalDays).first { !completedDays.contains($0) }
    }

    public func fractionComplete(totalDays: Int) -> Double {
        guard totalDays > 0 else { return 0 }
        return Double(completedDays.filter { $0 < totalDays }.count) / Double(totalDays)
    }
}
