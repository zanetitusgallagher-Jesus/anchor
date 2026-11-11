import Foundation

/// Streak arithmetic over the set of days on which the daily session was completed.
///
/// Days that are not scheduled (the gate is off that weekday) neither extend
/// nor break a streak. Today, if scheduled but not yet completed, does not break
/// the streak either: the user still has the rest of the day.
public struct StreakCalculator: Sendable {
    public var scheduledWeekdays: Set<Int>
    public var calendar: Calendar

    public init(scheduledWeekdays: Set<Int> = Set(1...7), calendar: Calendar = .current) {
        self.scheduledWeekdays = scheduledWeekdays.isEmpty ? Set(1...7) : scheduledWeekdays
        self.calendar = calendar
    }

    private func isScheduled(_ day: DayKey) -> Bool {
        scheduledWeekdays.contains(day.weekday(calendar: calendar))
    }

    public func currentStreak(completed: Set<DayKey>, today: DayKey) -> Int {
        var streak = 0
        var day = today
        // A completion on an unscheduled day still counts (bonus day).
        if completed.contains(today) { streak += 1 }
        day = today.adding(days: -1, calendar: calendar)

        guard let earliest = completed.min() else { return streak }
        while day >= earliest {
            if completed.contains(day) {
                streak += 1
            } else if isScheduled(day) {
                break
            }
            day = day.adding(days: -1, calendar: calendar)
        }
        return streak
    }

    public func longestStreak(completed: Set<DayKey>) -> Int {
        guard let first = completed.min(), let last = completed.max() else { return 0 }
        var best = 0
        var run = 0
        var day = first
        while day <= last {
            if completed.contains(day) {
                run += 1
                best = max(best, run)
            } else if isScheduled(day) {
                run = 0
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return best
    }
}
