import Foundation

/// Numbers shown on the unlock card and the dashboard.
public struct DailySummary: Equatable, Sendable {
    public var currentStreak: Int
    public var longestStreak: Int
    public var totalMinutesInWord: Int
    public var versesMemorized: Int
    public var versesInDeck: Int

    public init(currentStreak: Int, longestStreak: Int, totalMinutesInWord: Int, versesMemorized: Int, versesInDeck: Int) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalMinutesInWord = totalMinutesInWord
        self.versesMemorized = versesMemorized
        self.versesInDeck = versesInDeck
    }
}

/// The ordered list of steps for today's gate, given settings and context.
public enum GateFlow {
    public static func steps(settings: AnchorSettings, hasDueMemoryVerses: Bool, hasRewireToday: Bool) -> [GateStep] {
        GateStep.allCases.filter { step in
            switch step {
            case .welcome, .unlock: return true
            case .memory: return settings.isEnabled(.memory) && hasDueMemoryVerses
            case .rewire: return settings.isEnabled(.rewire) && hasRewireToday
            default: return settings.isEnabled(step)
            }
        }
    }

    /// Seconds of reading still required before "Continue" unlocks.
    public static func readingSecondsRemaining(elapsed: Double, settings: AnchorSettings) -> Double {
        max(0, Double(settings.minimumReadingMinutes) * 60 - elapsed)
    }
}

/// What today's session contains, given how many minutes the user chose on
/// the Welcome screen. Steps turned Off in Settings stay off.
public struct SessionPlan: Equatable, Sendable {
    public var minutes: Int
    /// Minimum time the Scripture reading stays on screen.
    public var readingMinutes: Int
    public var steps: [GateStep]
    /// Most memory verses to review today.
    public var memoryLimit: Int
    /// How many Rewire exercises today.
    public var rewireCount: Int
}

/// How long a passage takes to read.
public enum ReadingEstimate {
    /// A little above average adult silent reading (~238 wpm, Brysbaert 2019),
    /// so the reading timer is a floor a normal reader reaches naturally.
    public static let wordsPerMinute = 250.0

    public static func words(in texts: [String]) -> Int {
        texts.reduce(0) { $0 + $1.split(whereSeparator: { $0.isWhitespace }).count }
    }

    /// Whole minutes needed to read `words`, at least 1.
    public static func minutes(words: Int) -> Int {
        max(1, Int((Double(words) / wordsPerMinute).rounded(.up)))
    }
}

public enum SessionPlanner {
    /// The usual slider range when today's reading is short (e.g. a verse a day).
    public static let range = 2...15
    public static let defaultMinutes = 10

    /// The slider's range for a day whose reading needs `requiredReadingMinutes`.
    /// The minimum leaves time to read today's passage plus a minute to reflect,
    /// so a Bible-in-a-year day starts around 10 minutes, a single verse at 2.
    public static func range(requiredReadingMinutes: Int) -> ClosedRange<Int> {
        let lower = max(range.lowerBound, requiredReadingMinutes + 1)
        return lower...max(range.upperBound, lower + 10)
    }

    /// Reading gets the time today's passage needs, or about 40% of the
    /// session if that's more. Whatever is left adds steps: reflection (always),
    /// memory verse (3+ spare minutes), journal (5+), one Rewire (7+), two (9+).
    public static func plan(minutes requested: Int, settings: AnchorSettings,
                            hasDueMemoryVerses: Bool, rewireAvailable: Int,
                            requiredReadingMinutes: Int = 1) -> SessionPlan {
        let r = range(requiredReadingMinutes: requiredReadingMinutes)
        let m = min(r.upperBound, max(r.lowerBound, requested))
        let reading = max(max(1, requiredReadingMinutes), Int((Double(m) * 0.4).rounded()))
        let spare = m - reading
        let memoryLimit = spare < 5 ? 2 : 5
        let rewire = spare >= 9 ? min(2, settings.rewirePerDay) : (spare >= 7 ? 1 : 0)
        let rewireCount = min(rewire, rewireAvailable)

        let steps = GateStep.allCases.filter { step in
            switch step {
            case .welcome, .unlock: return true
            case .scripture, .reflection: return settings.isEnabled(step)
            case .memory: return settings.isEnabled(.memory) && hasDueMemoryVerses && spare >= 3
            case .journal: return settings.isEnabled(.journal) && spare >= 5
            case .rewire: return settings.isEnabled(.rewire) && rewireCount > 0
            }
        }
        return SessionPlan(minutes: m, readingMinutes: reading, steps: steps,
                           memoryLimit: memoryLimit, rewireCount: rewireCount)
    }

    // MARK: Short on time

    /// Which plan today's reading comes from.
    public enum ReadingChoice: Equatable, Sendable {
        /// The user's main plan (e.g. Bible in a Year).
        case main
        /// The short fallback (Verse a Day) because less time was chosen than
        /// the main reading needs. The main plan's day waits for tomorrow.
        case short
    }

    /// The fewest minutes that keep the user on their main plan today.
    public static func mainPlanMinimum(mainRequiredMinutes: Int) -> Int {
        range(requiredReadingMinutes: mainRequiredMinutes).lowerBound
    }

    /// The slider's range. With a short fallback available, it always starts
    /// at 2 minutes; without one, it starts at what the main reading needs.
    public static func sliderRange(mainRequiredMinutes: Int, hasShortPlan: Bool) -> ClosedRange<Int> {
        let main = range(requiredReadingMinutes: mainRequiredMinutes)
        return hasShortPlan ? range.lowerBound...main.upperBound : main
    }

    public static func choice(minutes: Int, mainRequiredMinutes: Int, hasShortPlan: Bool) -> ReadingChoice {
        guard hasShortPlan else { return .main }
        return minutes >= mainPlanMinimum(mainRequiredMinutes: mainRequiredMinutes) ? .main : .short
    }

    public static func readingSecondsRemaining(elapsed: Double, readingMinutes: Int) -> Double {
        max(0, Double(readingMinutes) * 60 - elapsed)
    }
}
