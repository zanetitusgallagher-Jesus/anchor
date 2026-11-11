import Foundation
@testable import AnchorCore

/// A fixed Gregorian calendar so tests don't depend on the machine's locale or zone.
let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

func day(_ s: String) -> DayKey { DayKey(string: s)! }

func date(_ s: String, hour: Int = 9, minute: Int = 0) -> Date {
    let d = day(s)
    return utc.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: hour, minute: minute))!
}
