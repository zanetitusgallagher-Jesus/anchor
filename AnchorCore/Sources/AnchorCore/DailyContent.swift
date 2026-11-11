import Foundation

public enum ReflectionPrompt: String, CaseIterable, Codable, Sendable {
    case summarize, revealsAboutGod, applyToday

    public var text: String {
        switch self {
        case .summarize: "Summarize the passage in one sentence."
        case .revealsAboutGod: "What does this passage reveal about God?"
        case .applyToday: "What is one thing to obey or apply today?"
        }
    }

    /// Rotates one prompt per calendar day.
    public static func forDay(_ day: DayKey, calendar: Calendar = .current) -> ReflectionPrompt {
        let ordinal = calendar.ordinality(of: .day, in: .era, for: day.date(calendar: calendar)) ?? 0
        return allCases[ordinal % allCases.count]
    }
}

public enum RewireScheduler {
    /// Chooses which exercises run today: `perDay` of the enabled ones,
    /// rotating through them day by day so each gets regular turns.
    public static func exercises(for day: DayKey, enabled: Set<RewireExercise>, perDay: Int, calendar: Calendar = .current) -> [RewireExercise] {
        let pool = RewireExercise.allCases.filter(enabled.contains)
        guard !pool.isEmpty, perDay > 0 else { return [] }
        let n = min(perDay, pool.count)
        let ordinal = calendar.ordinality(of: .day, in: .era, for: day.date(calendar: calendar)) ?? 0
        let start = (ordinal * n) % pool.count
        return (0..<n).map { pool[(start + $0) % pool.count] }
    }
}

public enum CenteringPrompt {
    /// Excerpts from the World English Bible (public domain).
    public static let all: [(text: String, reference: String)] = [
        ("Be still, and know that I am God.", "Psalm 46:10"),
        ("You will be saved in returning and rest. Your strength will be in quietness and in confidence.", "Isaiah 30:15"),
        ("Come to me, all you who labor and are heavily burdened, and I will give you rest.", "Matthew 11:28"),
        ("This is the day that Yahweh has made. We will rejoice and be glad in it!", "Psalm 118:24"),
        ("Draw near to God, and he will draw near to you.", "James 4:8"),
        ("My soul rests in God alone.", "Psalm 62:1"),
        ("His compassion doesn’t fail. They are new every morning. Great is your faithfulness.", "Lamentations 3:22–23"),
    ]

    public static func forDay(_ day: DayKey) -> (text: String, reference: String) {
        all[Int(day.seed % UInt64(all.count))]
    }
}

/// Box breathing: inhale, hold, exhale, hold — four seconds each.
public enum BoxBreathing {
    public enum Phase: String, CaseIterable, Sendable {
        case inhale = "Breathe in"
        case holdFull = "Hold"
        case exhale = "Breathe out"
        case holdEmpty = "Hold "
    }

    public static let phaseSeconds: Double = 4

    public static func phase(at elapsed: Double) -> (phase: Phase, progress: Double) {
        let cycle = phaseSeconds * 4
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        let idx = min(3, Int(t / phaseSeconds))
        let progress = (t - Double(idx) * phaseSeconds) / phaseSeconds
        return (Phase.allCases[idx], progress)
    }

    /// Circle scale 0...1 for the animation: grows on inhale, shrinks on exhale.
    public static func scale(at elapsed: Double) -> Double {
        let (p, f) = phase(at: elapsed)
        switch p {
        case .inhale: return f
        case .holdFull: return 1
        case .exhale: return 1 - f
        case .holdEmpty: return 0
        }
    }
}
