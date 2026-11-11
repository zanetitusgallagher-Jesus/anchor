import XCTest
@testable import AnchorCore

final class GatePolicyTests: XCTestCase {
    var settings = AnchorSettings()

    override func setUp() {
        settings = AnchorSettings()
        settings.graceCutoffHour = 11
    }

    private func eval(_ ctx: GateContext) -> GateDecision {
        GatePolicy.evaluate(ctx, settings: settings, calendar: utc)
    }

    func testShowsWhenNotCompletedToday() {
        let ctx = GateContext(now: date("2026-03-10", hour: 7), completedDays: [day("2026-03-09")])
        XCTAssertEqual(eval(ctx), .show)
    }

    func testHiddenWhenCompletedToday() {
        let ctx = GateContext(now: date("2026-03-10", hour: 7), completedDays: [day("2026-03-10")])
        XCTAssertEqual(eval(ctx), .hidden(.completedToday))
    }

    func testCompletionYesterdayDoesNotCountForToday() {
        let ctx = GateContext(now: date("2026-03-10", hour: 0, minute: 1), completedDays: [day("2026-03-09")])
        XCTAssertTrue(eval(ctx).shouldShow)
    }

    func testDisabled() {
        settings.gateEnabled = false
        let ctx = GateContext(now: date("2026-03-10", hour: 7), completedDays: [])
        XCTAssertEqual(eval(ctx), .hidden(.disabled))
    }

    func testWeekdaySchedule() {
        settings.activeWeekdays = [2, 3, 4, 5, 6] // weekdays; 2026-03-14 is a Saturday
        let sat = GateContext(now: date("2026-03-14", hour: 7), completedDays: [])
        XCTAssertEqual(eval(sat), .hidden(.notScheduledToday))
        let mon = GateContext(now: date("2026-03-16", hour: 7), completedDays: [])
        XCTAssertEqual(eval(mon), .show)
    }

    func testGraceWindow() {
        let late = GateContext(now: date("2026-03-10", hour: 11), completedDays: [])
        XCTAssertEqual(eval(late), .hidden(.outsideGraceWindow))
        let early = GateContext(now: date("2026-03-10", hour: 10, minute: 59), completedDays: [])
        XCTAssertEqual(eval(early), .show)
    }

    func testGateThatStartedInsideWindowStaysAfterCutoff() {
        let ctx = GateContext(now: date("2026-03-10", hour: 11, minute: 5), completedDays: [],
                              firstCheckToday: date("2026-03-10", hour: 10, minute: 55))
        XCTAssertEqual(eval(ctx), .show)
    }

    func testFirstCheckFromYesterdayIsIgnored() {
        let ctx = GateContext(now: date("2026-03-10", hour: 12), completedDays: [],
                              firstCheckToday: date("2026-03-09", hour: 8))
        XCTAssertEqual(eval(ctx), .hidden(.outsideGraceWindow))
    }

    func testAllDayCutoff() {
        settings.graceCutoffHour = 24
        let ctx = GateContext(now: date("2026-03-10", hour: 23), completedDays: [])
        XCTAssertEqual(eval(ctx), .show)
    }

    func testEmergencyUnlockReleasesForTheDayOnly() {
        let unlocked: Set = [day("2026-03-10")]
        XCTAssertEqual(eval(GateContext(now: date("2026-03-10", hour: 8), completedDays: [], emergencyUnlockedDays: unlocked)),
                       .hidden(.emergencyUnlockedToday))
        XCTAssertEqual(eval(GateContext(now: date("2026-03-11", hour: 8), completedDays: [], emergencyUnlockedDays: unlocked)),
                       .show)
    }

    func testSafeLaunch() {
        let ctx = GateContext(now: date("2026-03-10", hour: 8), completedDays: [], safeLaunch: true)
        XCTAssertEqual(eval(ctx), .hidden(.safeLaunch))
    }

    func testFailsafe() {
        settings.failsafeMinutes = 90
        let shown = date("2026-03-10", hour: 7)
        XCTAssertFalse(GatePolicy.failsafeExpired(gateShownAt: shown, now: shown.addingTimeInterval(89 * 60), settings: settings))
        XCTAssertTrue(GatePolicy.failsafeExpired(gateShownAt: shown, now: shown.addingTimeInterval(90 * 60), settings: settings))
        settings.failsafeMinutes = 0
        XCTAssertFalse(GatePolicy.failsafeExpired(gateShownAt: shown, now: shown.addingTimeInterval(1e6), settings: settings))
    }

    func testEmergencyPhrase() {
        XCTAssertTrue(EmergencyUnlock.phraseMatches("  i choose to UNLOCK my mac. ", expected: "I choose to unlock my Mac"))
        XCTAssertFalse(EmergencyUnlock.phraseMatches("unlock", expected: "I choose to unlock my Mac"))
        XCTAssertFalse(EmergencyUnlock.phraseMatches("", expected: ""))
        XCTAssertFalse(EmergencyUnlock.holdComplete(heldSeconds: 29.9))
        XCTAssertTrue(EmergencyUnlock.holdComplete(heldSeconds: 30))
    }

    func testSettingsDecodeToleratesMissingKeys() throws {
        let json = #"{"minimumReadingMinutes": 8, "unknownFutureKey": true}"#
        let s = try JSONDecoder().decode(AnchorSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.minimumReadingMinutes, 8)
        XCTAssertEqual(s.graceCutoffHour, AnchorSettings().graceCutoffHour)
        XCTAssertTrue(s.gateEnabled)
    }

    func testFlowSkipsMemoryWithoutDueCards() {
        let steps = GateFlow.steps(settings: AnchorSettings(), hasDueMemoryVerses: false, hasRewireToday: true)
        XCTAssertEqual(steps, [.welcome, .scripture, .reflection, .journal, .rewire, .unlock])
    }

    func testFlowRespectsDisabledSteps() {
        var s = AnchorSettings()
        s.disabledSteps = [.journal, .rewire]
        XCTAssertEqual(GateFlow.steps(settings: s, hasDueMemoryVerses: true, hasRewireToday: true),
                       [.welcome, .scripture, .reflection, .memory, .unlock])
    }

    func testReadingTimer() {
        var s = AnchorSettings()
        s.minimumReadingMinutes = 5
        XCTAssertEqual(GateFlow.readingSecondsRemaining(elapsed: 60, settings: s), 240)
        XCTAssertEqual(GateFlow.readingSecondsRemaining(elapsed: 400, settings: s), 0)
    }
}
