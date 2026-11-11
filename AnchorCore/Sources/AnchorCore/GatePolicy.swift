import Foundation

/// What the app knows about today when deciding whether to show the gate.
public struct GateContext: Sendable {
    public var now: Date
    public var completedDays: Set<DayKey>
    /// Days on which an emergency unlock (or the failsafe) released the gate.
    public var emergencyUnlockedDays: Set<DayKey>
    /// The first time Anchor evaluated the gate today, if earlier than `now`.
    /// The grace window is judged against this, so a gate that appeared at
    /// 10:55 doesn't vanish at 11:00 just because the clock moved.
    public var firstCheckToday: Date?
    /// True if the user held Shift while Anchor launched (safe launch).
    public var safeLaunch: Bool

    public init(now: Date, completedDays: Set<DayKey>, emergencyUnlockedDays: Set<DayKey> = [], firstCheckToday: Date? = nil, safeLaunch: Bool = false) {
        self.now = now
        self.completedDays = completedDays
        self.emergencyUnlockedDays = emergencyUnlockedDays
        self.firstCheckToday = firstCheckToday
        self.safeLaunch = safeLaunch
    }
}

public enum GateDecision: Equatable, Sendable {
    case show
    case hidden(Reason)

    public enum Reason: Equatable, Sendable {
        case disabled
        case notScheduledToday
        case completedToday
        case emergencyUnlockedToday
        case outsideGraceWindow
        case safeLaunch
    }

    public var shouldShow: Bool { self == .show }
}

public enum GatePolicy {
    public static func evaluate(_ ctx: GateContext, settings: AnchorSettings, calendar: Calendar = .current) -> GateDecision {
        let today = DayKey(ctx.now, calendar: calendar)
        guard settings.gateEnabled else { return .hidden(.disabled) }
        if ctx.safeLaunch { return .hidden(.safeLaunch) }
        if ctx.completedDays.contains(today) { return .hidden(.completedToday) }
        if ctx.emergencyUnlockedDays.contains(today) { return .hidden(.emergencyUnlockedToday) }
        let weekdays = settings.activeWeekdays.isEmpty ? Set(1...7) : settings.activeWeekdays
        guard weekdays.contains(today.weekday(calendar: calendar)) else { return .hidden(.notScheduledToday) }

        let reference: Date
        if let first = ctx.firstCheckToday, DayKey(first, calendar: calendar) == today, first < ctx.now {
            reference = first
        } else {
            reference = ctx.now
        }
        let cutoff = min(24, max(0, settings.graceCutoffHour))
        if cutoff < 24 {
            let hour = calendar.component(.hour, from: reference)
            if hour >= cutoff { return .hidden(.outsideGraceWindow) }
        }
        return .show
    }

    /// True once the gate has been visible long enough that the failsafe should release it.
    public static func failsafeExpired(gateShownAt: Date, now: Date, settings: AnchorSettings) -> Bool {
        guard settings.failsafeMinutes > 0 else { return false }
        return now.timeIntervalSince(gateShownAt) >= Double(settings.failsafeMinutes) * 60
    }
}

/// The emergency-unlock rules: a continuous 30-second hold, then the exact phrase.
public struct EmergencyUnlock: Sendable {
    public static let holdSeconds: Double = 30

    public static func phraseMatches(_ typed: String, expected: String) -> Bool {
        func norm(_ s: String) -> String {
            s.lowercased()
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        }
        return !expected.isEmpty && norm(typed) == norm(expected)
    }

    public static func holdComplete(heldSeconds: Double) -> Bool {
        heldSeconds >= holdSeconds
    }
}
