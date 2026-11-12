import XCTest
@testable import AnchorCore

final class NarrationTimingTests: XCTestCase {
    func testWholeChapterIsTheWholeRecording() {
        let e = NarrationTiming.estimate(verseLengths: [100, 100, 100], start: nil, end: nil, duration: 90)
        XCTAssertEqual(e.start, 0)
        XCTAssertEqual(e.end, 90)
    }

    func testEstimateIsProportionalToText() {
        // Intro 24 + three verses of 100 chars (+6 pause each) = 342 units over 342 seconds.
        let e = NarrationTiming.estimate(verseLengths: [100, 100, 100], start: 2, end: 2, duration: 342)
        XCTAssertEqual(e.start, 130, accuracy: 0.001)   // 24 + 106
        XCTAssertEqual(e.end, 236, accuracy: 0.001)     // 24 + 212
        let tail = NarrationTiming.estimate(verseLengths: [100, 100, 100], start: 3, end: nil, duration: 342)
        XCTAssertEqual(tail.end, 342)
    }

    func testEndPastTheLastVerseRunsToTheEnd() {
        let e = NarrationTiming.estimate(verseLengths: [50, 50], start: 1, end: 9, duration: 60)
        XCTAssertEqual(e.start, 0)
        XCTAssertEqual(e.end, 60)
    }

    /// Speech at level 1.0 with pauses (0.02) at 10.0–10.5 s and 13.0–13.5 s.
    private func levels(step: Double = 0.05, from: Double = 5, to: Double = 20) -> [Float] {
        stride(from: from, to: to, by: step).map { t in
            (t >= 10 && t < 10.5) || (t >= 13 && t < 13.5) ? 0.02 : 1.0
        }
    }

    func testSnapsToTheNearestPause() {
        let l = levels()
        let s = NarrationTiming.snapToPause(levels: l, step: 0.05, offset: 5, target: 11, lean: .earlier)
        XCTAssertEqual(s, 10.25, accuracy: 0.06)
        let e = NarrationTiming.snapToPause(levels: l, step: 0.05, offset: 5, target: 12.6, lean: .later)
        XCTAssertEqual(e, 13.25, accuracy: 0.06)
    }

    func testLeansSoThePassageIsNeverClipped() {
        let l = levels()
        // Halfway between the pauses: a start leans earlier, an end leans later.
        XCTAssertEqual(NarrationTiming.snapToPause(levels: l, step: 0.05, offset: 5, target: 11.75, lean: .earlier), 10.25, accuracy: 0.06)
        XCTAssertEqual(NarrationTiming.snapToPause(levels: l, step: 0.05, offset: 5, target: 11.75, lean: .later), 13.25, accuracy: 0.06)
    }

    func testNoPauseNearbyKeepsTheEstimate() {
        let speech = [Float](repeating: 1, count: 300)
        XCTAssertEqual(NarrationTiming.snapToPause(levels: speech, step: 0.05, offset: 0, target: 7, lean: .earlier), 7)
        XCTAssertEqual(NarrationTiming.snapToPause(levels: levels(), step: 0.05, offset: 5, target: 40, lean: .earlier, maxShift: 2), 40)
    }

    func testVerseIndexForHighlighting() {
        let lengths = [100, 100, 100]
        XCTAssertNil(NarrationTiming.verseIndex(at: 10, duration: 342, verseLengths: lengths))  // intro
        XCTAssertEqual(NarrationTiming.verseIndex(at: 30, duration: 342, verseLengths: lengths), 1)
        XCTAssertEqual(NarrationTiming.verseIndex(at: 200, duration: 342, verseLengths: lengths), 2)
        XCTAssertEqual(NarrationTiming.verseIndex(at: 340, duration: 342, verseLengths: lengths), 3)
    }
}
