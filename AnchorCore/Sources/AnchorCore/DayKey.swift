import Foundation

/// A calendar day in the user's local calendar, independent of time of day.
/// Used as the identity of a daily session, streak cell or plan day.
public struct DayKey: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Parses `yyyy-MM-dd`.
    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Midnight at the start of this day.
    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        let d = calendar.date(byAdding: .day, value: days, to: date(calendar: calendar))!
        return DayKey(d, calendar: calendar)
    }

    /// 1 = Sunday ... 7 = Saturday (Gregorian `weekday`).
    public func weekday(calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date(calendar: calendar))
    }

    public func days(until other: DayKey, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: date(calendar: calendar), to: other.date(calendar: calendar)).day!
    }

    public static func < (a: DayKey, b: DayKey) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}
