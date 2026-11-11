import XCTest
@testable import AnchorCore

final class SessionPlannerTests: XCTestCase {
    private func plan(_ m: Int, due: Bool = true, rewire: Int = 4, settings: AnchorSettings = {
        var s = AnchorSettings(); s.rewirePerDay = 2; return s
    }()) -> SessionPlan {
        SessionPlanner.plan(minutes: m, settings: settings, hasDueMemoryVerses: due, rewireAvailable: rewire)
    }

    func testTwoMinutesIsReadAndReflect() {
        let p = plan(2)
        XCTAssertEqual(p.steps, [.welcome, .scripture, .reflection, .unlock])
        XCTAssertEqual(p.readingMinutes, 1)
    }

    func testFiveMinutesAddsMemory() {
        let p = plan(5)
        XCTAssertEqual(p.steps, [.welcome, .scripture, .reflection, .memory, .unlock])
        XCTAssertEqual(p.readingMinutes, 2)
        XCTAssertEqual(p.memoryLimit, 2)
        XCTAssertEqual(plan(5, due: false).steps, [.welcome, .scripture, .reflection, .unlock])
    }

    func testTenMinutesAddsJournal() {
        let p = plan(10)
        XCTAssertEqual(p.steps, [.welcome, .scripture, .reflection, .memory, .journal, .unlock])
        XCTAssertEqual(p.readingMinutes, 4)
        XCTAssertEqual(p.rewireCount, 0)
    }

    func testFifteenMinutesIsEverything() {
        let p = plan(15)
        XCTAssertEqual(p.steps, GateStep.allCases)
        XCTAssertEqual(p.readingMinutes, 6)
        XCTAssertEqual(p.rewireCount, 2)
        XCTAssertEqual(plan(12).rewireCount, 1)
    }

    func testClampsToRange() {
        XCTAssertEqual(plan(0).minutes, 2)
        XCTAssertEqual(plan(60).minutes, 15)
    }

    func testRespectsSettings() {
        var s = AnchorSettings()
        s.rewirePerDay = 1
        s.disabledSteps = [.journal]
        let p = plan(15, settings: s)
        XCTAssertFalse(p.steps.contains(.journal))
        XCTAssertEqual(p.rewireCount, 1)
        XCTAssertEqual(plan(15, rewire: 0).rewireCount, 0)
        XCTAssertFalse(plan(15, rewire: 0).steps.contains(.rewire))
    }

    func testLongReadingRaisesTheMinimum() {
        // A Bible-in-a-year day: ~2,100 words -> 9 minutes of reading.
        let words = 2100
        let need = ReadingEstimate.minutes(words: words)
        XCTAssertEqual(need, 9)
        XCTAssertEqual(SessionPlanner.range(requiredReadingMinutes: need), 10...20)

        let shortest = SessionPlanner.plan(minutes: 2, settings: AnchorSettings(), hasDueMemoryVerses: true,
                                           rewireAvailable: 2, requiredReadingMinutes: need)
        XCTAssertEqual(shortest.minutes, 10, "Can't pick less time than the reading needs")
        XCTAssertEqual(shortest.readingMinutes, 9)
        XCTAssertEqual(shortest.steps, [.welcome, .scripture, .reflection, .unlock])

        let full = SessionPlanner.plan(minutes: 20, settings: AnchorSettings(), hasDueMemoryVerses: true,
                                       rewireAvailable: 2, requiredReadingMinutes: need)
        XCTAssertEqual(full.readingMinutes, 9)
        XCTAssertTrue(full.steps.contains(.journal))
        XCTAssertTrue(full.steps.contains(.rewire))
    }

    func testShortReadingKeepsTheTwoMinuteFloor() {
        XCTAssertEqual(ReadingEstimate.minutes(words: 25), 1)
        XCTAssertEqual(ReadingEstimate.minutes(words: 0), 1)
        XCTAssertEqual(SessionPlanner.range(requiredReadingMinutes: 1), 2...15)
        XCTAssertEqual(ReadingEstimate.words(in: ["For God so loved", "the world."]), 6)
    }

    func testShortOnTimeSwitchesToTheShortPlan() {
        // Bible in a Year day needs 9 minutes of reading -> 10 minutes keeps you on it.
        XCTAssertEqual(SessionPlanner.mainPlanMinimum(mainRequiredMinutes: 9), 10)
        XCTAssertEqual(SessionPlanner.sliderRange(mainRequiredMinutes: 9, hasShortPlan: true), 2...20)
        XCTAssertEqual(SessionPlanner.sliderRange(mainRequiredMinutes: 9, hasShortPlan: false), 10...20)
        XCTAssertEqual(SessionPlanner.choice(minutes: 2, mainRequiredMinutes: 9, hasShortPlan: true), .short)
        XCTAssertEqual(SessionPlanner.choice(minutes: 9, mainRequiredMinutes: 9, hasShortPlan: true), .short)
        XCTAssertEqual(SessionPlanner.choice(minutes: 10, mainRequiredMinutes: 9, hasShortPlan: true), .main)
        XCTAssertEqual(SessionPlanner.choice(minutes: 2, mainRequiredMinutes: 9, hasShortPlan: false), .main)
        // A short main plan never needs the fallback.
        XCTAssertEqual(SessionPlanner.choice(minutes: 2, mainRequiredMinutes: 1, hasShortPlan: true), .main)
    }

    func testReadingTimer() {
        XCTAssertEqual(SessionPlanner.readingSecondsRemaining(elapsed: 30, readingMinutes: 1), 30)
        XCTAssertEqual(SessionPlanner.readingSecondsRemaining(elapsed: 90, readingMinutes: 1), 0)
    }
}
