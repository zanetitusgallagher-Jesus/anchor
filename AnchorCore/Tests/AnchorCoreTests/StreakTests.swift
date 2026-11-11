import XCTest
@testable import AnchorCore

final class StreakTests: XCTestCase {
    let calc = StreakCalculator(calendar: utc)

    func testEmpty() {
        XCTAssertEqual(calc.currentStreak(completed: [], today: day("2026-03-10")), 0)
        XCTAssertEqual(calc.longestStreak(completed: []), 0)
    }

    func testConsecutiveDaysIncludingToday() {
        let done: Set = [day("2026-03-08"), day("2026-03-09"), day("2026-03-10")]
        XCTAssertEqual(calc.currentStreak(completed: done, today: day("2026-03-10")), 3)
    }

    func testTodayNotYetDoneDoesNotBreakStreak() {
        let done: Set = [day("2026-03-08"), day("2026-03-09")]
        XCTAssertEqual(calc.currentStreak(completed: done, today: day("2026-03-10")), 2)
    }

    func testMissedYesterdayBreaksStreak() {
        let done: Set = [day("2026-03-07"), day("2026-03-08")]
        XCTAssertEqual(calc.currentStreak(completed: done, today: day("2026-03-10")), 0)
    }

    func testUnscheduledDaysDoNotBreakStreak() {
        // Weekdays only (Mon=2 ... Fri=6). 2026-03-06 is a Friday, 03-09 a Monday.
        let weekdays = StreakCalculator(scheduledWeekdays: [2, 3, 4, 5, 6], calendar: utc)
        let done: Set = [day("2026-03-05"), day("2026-03-06"), day("2026-03-09")]
        XCTAssertEqual(weekdays.currentStreak(completed: done, today: day("2026-03-09")), 3)
        XCTAssertEqual(weekdays.longestStreak(completed: done), 3)
        // With every day scheduled, the weekend breaks it.
        XCTAssertEqual(calc.currentStreak(completed: done, today: day("2026-03-09")), 1)
    }

    func testBonusCompletionOnUnscheduledDayCounts() {
        let weekdays = StreakCalculator(scheduledWeekdays: [2, 3, 4, 5, 6], calendar: utc)
        let done: Set = [day("2026-03-06"), day("2026-03-07"), day("2026-03-09")] // Fri, Sat, Mon
        XCTAssertEqual(weekdays.currentStreak(completed: done, today: day("2026-03-09")), 3)
    }

    func testLongestStreakFindsBestRun() {
        let done: Set = [
            day("2026-01-01"), day("2026-01-02"),
            day("2026-01-05"), day("2026-01-06"), day("2026-01-07"), day("2026-01-08"),
            day("2026-01-10"),
        ]
        XCTAssertEqual(calc.longestStreak(completed: done), 4)
        XCTAssertEqual(calc.currentStreak(completed: done, today: day("2026-01-10")), 1)
    }

    func testAcrossYearBoundary() {
        let done: Set = [day("2025-12-30"), day("2025-12-31"), day("2026-01-01")]
        XCTAssertEqual(calc.currentStreak(completed: done, today: day("2026-01-02")), 3)
    }

    func testEmptyWeekdaySetMeansEveryDay() {
        let c = StreakCalculator(scheduledWeekdays: [], calendar: utc)
        XCTAssertEqual(c.scheduledWeekdays, Set(1...7))
    }
}
