import Foundation

/// A challenge the user has started.
public struct Challenge: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// Complete the daily session on 30 days, starting today.
        case thirtyDay
        /// Finish a 365-day plan (by default the shuffled whole Bible).
        case bibleInAYear

        public var title: String {
            switch self {
            case .thirtyDay: "30-Day Challenge"
            case .bibleInAYear: "Bible in a Year"
            }
        }

        public var length: Int { self == .thirtyDay ? 30 : 365 }

        /// Badges along the way, in days.
        public var milestones: [Int] {
            switch self {
            case .thirtyDay: [7, 14, 21, 30]
            case .bibleInAYear: [30, 100, 182, 365]
            }
        }
    }

    public var kind: Kind
    public var startedOn: DayKey
    /// For Bible in a Year: the plan being read.
    public var planID: String?
    public var id: String { kind.rawValue }

    public init(kind: Kind, startedOn: DayKey, planID: String? = nil) {
        self.kind = kind
        self.startedOn = startedOn
        self.planID = planID
    }
}

public struct ChallengeStatus: Equatable, Sendable {
    /// Which calendar day of the challenge today is (1-based, capped at the length).
    public var dayNumber: Int
    /// Days of progress: sessions completed (30-day) or plan days read (year).
    public var progress: Int
    public var length: Int
    /// Year challenge: progress minus where an every-day reader would be. Positive = ahead.
    public var pace: Int
    public var isFinished: Bool
    /// The 30-day window has passed (whether or not every day was done).
    public var isOver: Bool
    public var milestonesReached: [Int]

    public var fraction: Double { length == 0 ? 0 : min(1, Double(progress) / Double(length)) }
}

public enum ChallengeTracker {
    /// - Parameters:
    ///   - completedDays: days the daily session was finished.
    ///   - planDaysRead: number of plan days read (year challenge).
    public static func status(_ c: Challenge, today: DayKey, completedDays: Set<DayKey>,
                              planDaysRead: Int, calendar: Calendar = .current) -> ChallengeStatus {
        let length = c.kind.length
        let elapsed = max(0, c.startedOn.days(until: today, calendar: calendar))
        let dayNumber = min(length, elapsed + 1)

        let progress: Int
        switch c.kind {
        case .thirtyDay:
            let end = c.startedOn.adding(days: length - 1, calendar: calendar)
            progress = completedDays.filter { $0 >= c.startedOn && $0 <= end && $0 <= today }.count
        case .bibleInAYear:
            progress = min(length, planDaysRead)
        }

        // Today isn't "behind" until it's over, so pace counts days before today.
        let expected = min(length, elapsed)
        let isOver = c.kind == .thirtyDay && elapsed >= length
        return ChallengeStatus(dayNumber: dayNumber, progress: progress, length: length,
                               pace: progress - expected,
                               isFinished: progress >= length, isOver: isOver,
                               milestonesReached: c.kind.milestones.filter { progress >= $0 })
    }

    /// One-line summary for the Welcome and Unlock screens.
    public static func summary(_ c: Challenge, _ s: ChallengeStatus) -> String {
        if s.isFinished { return "\(c.kind.title) complete 🎉" }
        switch c.kind {
        case .thirtyDay:
            if s.isOver { return "\(c.kind.title) finished · \(s.progress) of 30 days" }
            return "\(c.kind.title) · Day \(s.dayNumber) of 30 · \(s.progress) done"
        case .bibleInAYear:
            let pace = s.pace == 0 ? "on pace" : s.pace > 0 ? "\(s.pace) day\(s.pace == 1 ? "" : "s") ahead"
                : "\(-s.pace) day\(s.pace == -1 ? "" : "s") behind"
            return "\(c.kind.title) · \(s.progress) of 365 days read · \(pace)"
        }
    }
}
