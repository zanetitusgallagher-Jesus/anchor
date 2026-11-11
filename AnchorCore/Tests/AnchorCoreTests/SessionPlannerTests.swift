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

    func testReadingTimer() {
        XCTAssertEqual(SessionPlanner.readingSecondsRemaining(elapsed: 30, readingMinutes: 1), 30)
        XCTAssertEqual(SessionPlanner.readingSecondsRemaining(elapsed: 90, readingMinutes: 1), 0)
    }
}
