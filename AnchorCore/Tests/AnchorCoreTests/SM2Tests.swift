import XCTest
@testable import AnchorCore

final class SM2Tests: XCTestCase {
    let start = day("2026-01-01")

    func testNewCardIsDueImmediately() {
        let s = SM2State.new(on: start)
        XCTAssertTrue(s.isDue(on: start))
        XCTAssertEqual(s.easeFactor, 2.5)
        XCTAssertEqual(s.repetitions, 0)
    }

    func testFirstThreeIntervalsWithPerfectRecall() {
        var s = SM2State.new(on: start)
        s = SM2.review(s, quality: 5, on: start, calendar: utc)
        XCTAssertEqual(s.interval, 1)
        XCTAssertEqual(s.due, day("2026-01-02"))
        XCTAssertEqual(s.easeFactor, 2.6, accuracy: 1e-9)

        s = SM2.review(s, quality: 5, on: s.due, calendar: utc)
        XCTAssertEqual(s.interval, 6)
        XCTAssertEqual(s.due, day("2026-01-08"))
        XCTAssertEqual(s.easeFactor, 2.7, accuracy: 1e-9)

        s = SM2.review(s, quality: 5, on: s.due, calendar: utc)
        // round(6 * 2.7) = 16
        XCTAssertEqual(s.interval, 16)
        XCTAssertEqual(s.repetitions, 3)
        XCTAssertEqual(s.due, day("2026-01-24"))
    }

    func testQualityFourLeavesEaseUnchanged() {
        let s = SM2.review(.new(on: start), quality: 4, on: start, calendar: utc)
        XCTAssertEqual(s.easeFactor, 2.5, accuracy: 1e-9)
    }

    func testQualityThreeLowersEase() {
        let s = SM2.review(.new(on: start), quality: 3, on: start, calendar: utc)
        // 2.5 + (0.1 - 2 * (0.08 + 2 * 0.02)) = 2.36
        XCTAssertEqual(s.easeFactor, 2.36, accuracy: 1e-9)
        XCTAssertEqual(s.repetitions, 1)
    }

    func testLapseResetsRepetitionsButKeepsEase() {
        var s = SM2State(repetitions: 4, interval: 30, easeFactor: 2.2, due: start)
        s = SM2.review(s, quality: 2, on: start, calendar: utc)
        XCTAssertEqual(s.repetitions, 0)
        XCTAssertEqual(s.interval, 1)
        XCTAssertEqual(s.easeFactor, 2.2, accuracy: 1e-9)
        XCTAssertEqual(s.due, day("2026-01-02"))
    }

    func testEaseNeverDropsBelowFloor() {
        var s = SM2State.new(on: start)
        for _ in 0..<20 { s = SM2.review(s, quality: 3, on: start, calendar: utc) }
        XCTAssertEqual(s.easeFactor, SM2State.minimumEase, accuracy: 1e-9)
    }

    func testQualityIsClamped() {
        let hi = SM2.review(.new(on: start), quality: 9, on: start, calendar: utc)
        let five = SM2.review(.new(on: start), quality: 5, on: start, calendar: utc)
        XCTAssertEqual(hi, five)
        let lo = SM2.review(.new(on: start), quality: -3, on: start, calendar: utc)
        XCTAssertEqual(lo.repetitions, 0)
    }

    func testMemorizedThreshold() {
        XCTAssertFalse(SM2State(repetitions: 3, interval: 16, due: start).isMemorized)
        XCTAssertTrue(SM2State(repetitions: 4, interval: 21, due: start).isMemorized)
    }

    func testSessionRepeatRule() {
        XCTAssertTrue(SM2.needsRepeatInSession(quality: 3))
        XCTAssertFalse(SM2.needsRepeatInSession(quality: 4))
    }

    func testIntervalsGrowAcrossMonthBoundary() {
        var s = SM2State(repetitions: 2, interval: 6, easeFactor: 2.5, due: day("2026-01-29"))
        s = SM2.review(s, quality: 4, on: day("2026-01-29"), calendar: utc)
        XCTAssertEqual(s.interval, 15)
        XCTAssertEqual(s.due, day("2026-02-13"))
    }
}
