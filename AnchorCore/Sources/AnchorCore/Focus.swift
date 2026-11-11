import Foundation

/// An app the user chose to pause during focus hours.
public struct BlockedApp: Codable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// When focus hours apply. Times are minutes after local midnight; an end
/// earlier than the start means the window runs past midnight (e.g. 22:00–02:00).
public struct FocusSchedule: Codable, Equatable, Sendable {
    public var enabled = false
    public var startMinutes = 9 * 60
    public var endMinutes = 17 * 60
    /// 1 = Sunday ... 7 = Saturday. Defaults to Monday–Friday.
    public var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    /// How long "Allow for a few minutes" lasts.
    public var allowanceMinutes = 5
    public var blockedApps: [BlockedApp] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let d = FocusSchedule()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback
        }
        enabled = v(.enabled, d.enabled)
        startMinutes = v(.startMinutes, d.startMinutes)
        endMinutes = v(.endMinutes, d.endMinutes)
        weekdays = v(.weekdays, d.weekdays)
        allowanceMinutes = v(.allowanceMinutes, d.allowanceMinutes)
        blockedApps = v(.blockedApps, d.blockedApps)
    }
}

public enum FocusPolicy {
    /// Apps that are never paused, whatever the list says, so the Mac stays usable.
    public static let neverBlock: Set<String> = [
        "com.apple.finder", "com.apple.systempreferences", "com.apple.Settings",
        "com.apple.loginwindow", "com.apple.dock", "com.apple.ActivityMonitor",
        "com.apple.Terminal", "com.apple.SecurityAgent", "com.apple.notificationcenterui",
    ]

    /// Whether focus hours are in effect at `now`.
    public static func isActive(_ s: FocusSchedule, now: Date, calendar: Calendar = .current) -> Bool {
        guard s.enabled, !s.blockedApps.isEmpty, s.startMinutes != s.endMinutes else { return false }
        let c = calendar.dateComponents([.hour, .minute, .weekday], from: now)
        let minute = c.hour! * 60 + c.minute!
        let weekdays = s.weekdays.isEmpty ? Set(1...7) : s.weekdays

        if s.startMinutes < s.endMinutes {
            return weekdays.contains(c.weekday!) && minute >= s.startMinutes && minute < s.endMinutes
        }
        // Overnight window: the part after midnight belongs to the previous day's schedule.
        if minute >= s.startMinutes { return weekdays.contains(c.weekday!) }
        if minute < s.endMinutes {
            let yesterday = c.weekday! == 1 ? 7 : c.weekday! - 1
            return weekdays.contains(yesterday)
        }
        return false
    }

    /// Whether the app with `bundleID` should be paused right now.
    /// `allowances` maps bundle IDs to the time a temporary allowance ends.
    public static func shouldPause(bundleID: String?, schedule: FocusSchedule, now: Date,
                                   ownBundleID: String?, allowances: [String: Date] = [:],
                                   calendar: Calendar = .current) -> Bool {
        guard let bundleID, bundleID != ownBundleID, !neverBlock.contains(bundleID) else { return false }
        guard schedule.blockedApps.contains(where: { $0.bundleID == bundleID }) else { return false }
        if let until = allowances[bundleID], until > now { return false }
        return isActive(schedule, now: now, calendar: calendar)
    }

    /// "9:00 AM – 5:00 PM"
    public static func describe(_ s: FocusSchedule, calendar: Calendar = .current) -> String {
        func t(_ m: Int) -> String {
            let d = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: m / 60, minute: m % 60))!
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.dateStyle = .none
            f.timeStyle = .short
            return f.string(from: d)
        }
        return "\(t(s.startMinutes)) – \(t(s.endMinutes))"
    }

    /// When the current focus window ends (for the shield's "Paused until …").
    public static func endOfWindow(_ s: FocusSchedule, now: Date, calendar: Calendar = .current) -> Date? {
        guard isActive(s, now: now, calendar: calendar) else { return nil }
        let startOfDay = calendar.startOfDay(for: now)
        var end = calendar.date(byAdding: .minute, value: s.endMinutes, to: startOfDay)!
        if end <= now { end = calendar.date(byAdding: .day, value: 1, to: end)! }
        return end
    }
}
