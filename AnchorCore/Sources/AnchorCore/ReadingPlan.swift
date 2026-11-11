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
