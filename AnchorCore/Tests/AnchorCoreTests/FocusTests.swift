import XCTest
@testable import AnchorCore

final class FocusTests: XCTestCase {
    private func schedule(_ start: Int, _ end: Int, days: Set<Int> = [2, 3, 4, 5, 6]) -> FocusSchedule {
        var s = FocusSchedule()
        s.enabled = true
        s.startMinutes = start
        s.endMinutes = end
        s.weekdays = days
        s.blockedApps = [BlockedApp(bundleID: "com.example.social", name: "Social")]
        return s
    }

    // 2026-03-10 is a Tuesday, 2026-03-14 a Saturday.

    func testDaytimeWindow() {
        let s = schedule(9 * 60, 17 * 60)
        XCTAssertFalse(FocusPolicy.isActive(s, now: date("2026-03-10", hour: 8, minute: 59), calendar: utc))
        XCTAssertTrue(FocusPolicy.isActive(s, now: date("2026-03-10", hour: 9), calendar: utc))
        XCTAssertTrue(FocusPolicy.isActive(s, now: date("2026-03-10", hour: 16, minute: 59), calendar: utc))
        XCTAssertFalse(FocusPolicy.isActive(s, now: date("2026-03-10", hour: 17), calendar: utc))
        XCTAssertFalse(FocusPolicy.isActive(s, now: date("2026-03-14", hour: 10), calendar: utc), "Weekend is off")
    }

    func testOvernightWindowBelongsToStartDay() {
        let s = schedule(22 * 60, 2 * 60, days: [6]) // Friday night
        XCTAssertTrue(FocusPolicy.isActive(s, now: date("2026-03-13", hour: 23), calendar: utc))   // Fri 23:00
        XCTAssertTrue(FocusPolicy.isActive(s, now: date("2026-03-14", hour: 1), calendar: utc))    // Sat 01:00
        XCTAssertFalse(FocusPolicy.isActive(s, now: date("2026-03-14", hour: 23), calendar: utc))  // Sat 23:00
        XCTAssertFalse(FocusPolicy.isActive(s, now: date("2026-03-13", hour: 1), calendar: utc))   // Fri 01:00
    }

    func testDisabledOrEmpty() {
        var s = schedule(9 * 60, 17 * 60)
        s.enabled = false
        XCTAssertFalse(FocusPolicy.isActive(s, now: date("2026-03-10", hour: 10), calendar: utc))
        s.enabled = true
        s.blockedApps = []
        XCTAssertFalse(FocusPolicy.isActive(s, now: date("2026-03-10", hour: 10), calendar: utc))
    }

    func testShouldPause() {
        let s = schedule(9 * 60, 17 * 60)
        let now = date("2026-03-10", hour: 10)
        func pause(_ id: String?, allowances: [String: Date] = [:]) -> Bool {
            FocusPolicy.shouldPause(bundleID: id, schedule: s, now: now, ownBundleID: "app.anchor.Anchor",
                                    allowances: allowances, calendar: utc)
        }
        XCTAssertTrue(pause("com.example.social"))
        XCTAssertFalse(pause("com.example.other"), "Not on the list")
        XCTAssertFalse(pause(nil))
        XCTAssertFalse(pause("app.anchor.Anchor"))
        XCTAssertFalse(pause("com.example.social", allowances: ["com.example.social": now.addingTimeInterval(60)]))
        XCTAssertTrue(pause("com.example.social", allowances: ["com.example.social": now.addingTimeInterval(-1)]))
    }

    func testSafetyListIsNeverPaused() {
        var s = schedule(0, 24 * 60 - 1, days: Set(1...7))
        s.blockedApps = [BlockedApp(bundleID: "com.apple.finder", name: "Finder"),
                         BlockedApp(bundleID: "com.apple.systempreferences", name: "System Settings")]
        for id in ["com.apple.finder", "com.apple.systempreferences"] {
            XCTAssertFalse(FocusPolicy.shouldPause(bundleID: id, schedule: s, now: date("2026-03-10", hour: 10),
                                                   ownBundleID: nil, calendar: utc))
        }
    }

    func testEndOfWindow() {
        let s = schedule(9 * 60, 17 * 60)
        XCTAssertEqual(FocusPolicy.endOfWindow(s, now: date("2026-03-10", hour: 10), calendar: utc), date("2026-03-10", hour: 17))
        XCTAssertNil(FocusPolicy.endOfWindow(s, now: date("2026-03-10", hour: 18), calendar: utc))
        let night = schedule(22 * 60, 2 * 60, days: [6])
        XCTAssertEqual(FocusPolicy.endOfWindow(night, now: date("2026-03-13", hour: 23), calendar: utc), date("2026-03-14", hour: 2))
    }

    func testOldSettingsDecodeWithFocusDefaults() throws {
        let s = try JSONDecoder().decode(AnchorSettings.self, from: Data(#"{"gateEnabled": true}"#.utf8))
        XCTAssertFalse(s.focus.enabled)
        XCTAssertEqual(s.focus.weekdays, [2, 3, 4, 5, 6])
    }
}
