import XCTest
@testable import AnchorCore

final class ShuffledPlanTests: XCTestCase {
    /// Synthetic verse counts: every chapter of the real canon, with varied lengths (1–60).
    let counts: [String: [Int]] = Dictionary(uniqueKeysWithValues: BookCatalog.all.enumerated().map { bi, b in
        (b.id, (1...b.chapters).map { ((bi * 7 + $0 * 13) % 60) + 1 })
    })

    private func expand(_ r: ChapterRef) -> [String] {
        let n = counts[r.bookID]![r.chapter - 1]
        return Array((r.verseStart ?? 1)...(r.verseEnd ?? n)).map { "\(r.bookID).\(r.chapter).\($0)" }
    }

    func testEveryVerseExactlyOnce() {
        let plan = ReadingPlanGenerator.shuffledWholeBible(verseCounts: counts, seed: 42)
        XCTAssertEqual(plan.days.count, 365)
        XCTAssertTrue(plan.days.allSatisfy { !$0.isEmpty })
        let read = plan.days.flatMap { $0 }.flatMap(expand)
        let all = counts.flatMap { id, cs in cs.enumerated().flatMap { ci, n in (1...n).map { "\(id).\(ci + 1).\($0)" } } }
        XCTAssertEqual(read.count, all.count, "No verse read twice")
        XCTAssertEqual(Set(read), Set(all), "Every verse read")
    }

    func testPassagesAreShortAndDaysBalanced() {
        let plan = ReadingPlanGenerator.shuffledWholeBible(verseCounts: counts, seed: 7, maxVerses: 25)
        XCTAssertTrue(plan.days.flatMap { $0 }.allSatisfy { expand($0).count <= 25 })
        let sizes = plan.days.map { $0.flatMap(expand).count }
        let mean = Double(sizes.reduce(0, +)) / Double(sizes.count)
        XCTAssertLessThan(Double(sizes.max()!), mean * 1.6)
    }

    func testDaysMixDifferentPartsOfTheBible() {
        let plan = ReadingPlanGenerator.shuffledWholeBible(verseCounts: counts, seed: 99)
        let multiBook = plan.days.filter { Set($0.map(\.bookID)).count > 1 }.count
        XCTAssertGreaterThan(multiBook, 300, "Most days draw from more than one book")
        XCTAssertNotEqual(plan.days[0].first, ChapterRef(bookID: "GEN", chapter: 1), "Doesn't simply start at Genesis 1")
    }

    func testDeterministicPerSeedAndDifferentAcrossSeeds() {
        let a = ReadingPlanGenerator.shuffledWholeBible(verseCounts: counts, seed: 1)
        let b = ReadingPlanGenerator.shuffledWholeBible(verseCounts: counts, seed: 1)
        let c = ReadingPlanGenerator.shuffledWholeBible(verseCounts: counts, seed: 2)
        XCTAssertEqual(a.days, b.days)
        XCTAssertNotEqual(a.days, c.days)
        XCTAssertEqual(ReadingPlanGenerator.seed(fromShuffledID: a.id), 1)
        XCTAssertNil(ReadingPlanGenerator.seed(fromShuffledID: "nt-90"))
    }

    func testDaysListPassagesInCanonicalOrder() {
        let plan = ReadingPlanGenerator.shuffledWholeBible(verseCounts: counts, seed: 3)
        for day in plan.days {
            let keys = day.map { (BookCatalog.order($0.bookID), $0.chapter, $0.verseStart ?? 0) }
            XCTAssertTrue(zip(keys, keys.dropFirst()).allSatisfy { $0 < $1 })
        }
    }

    func testVerseRangeReferences() {
        XCTAssertEqual(ChapterRef(bookID: "JHN", chapter: 3, verseStart: 1, verseEnd: 18).description, "John 3:1–18")
        XCTAssertEqual(ChapterRef(bookID: "JHN", chapter: 3, verseStart: 19).description, "John 3:19–end")
        XCTAssertEqual(ChapterRef(bookID: "JHN", chapter: 3).description, "John 3")
        XCTAssertEqual(ChapterRef(bookID: "JHN", chapter: 3, verseStart: 1, verseEnd: 18).apiBibleID, "JHN.3.1-JHN.3.18")
        let json = #"{"id":"T","name":"T","books":[{"id":"JHN","name":"John","chapters":[["a","b","c","d"]]}]}"#
        let bible = try! Bible.decode(Data(json.utf8))
        XCTAssertEqual(bible.verses(ChapterRef(bookID: "JHN", chapter: 1, verseStart: 2, verseEnd: 3)).map(\.text), ["b", "c"])
        XCTAssertEqual(bible.verses(ChapterRef(bookID: "JHN", chapter: 1, verseStart: 3)).map(\.text), ["c", "d"])
    }

    func testOldPlanJSONStillDecodes() throws {
        let json = #"{"id":"x","name":"x","summary":"x","days":[[{"bookID":"GEN","chapter":1}]]}"#
        let plan = try JSONDecoder().decode(ReadingPlan.self, from: Data(json.utf8))
        XCTAssertTrue(plan.days[0][0].isWholeChapter)
    }
}

final class ChallengeTests: XCTestCase {
    func testThirtyDayCountsCompletedDaysInWindow() {
        let c = Challenge(kind: .thirtyDay, startedOn: day("2026-03-01"))
        let done: Set = [day("2026-02-28"), day("2026-03-01"), day("2026-03-02"), day("2026-03-05")]
        let s = ChallengeTracker.status(c, today: day("2026-03-05"), completedDays: done, planDaysRead: 0, calendar: utc)
        XCTAssertEqual(s.dayNumber, 5)
        XCTAssertEqual(s.progress, 3, "The day before the start doesn't count")
        XCTAssertFalse(s.isOver)
        XCTAssertEqual(ChallengeTracker.summary(c, s), "30-Day Challenge · Day 5 of 30 · 3 done")
    }

    func testThirtyDayFinishAndMilestones() {
        let start = day("2026-03-01")
        let c = Challenge(kind: .thirtyDay, startedOn: start)
        let done = Set((0..<30).map { start.adding(days: $0, calendar: utc) })
        let s = ChallengeTracker.status(c, today: start.adding(days: 29, calendar: utc), completedDays: done, planDaysRead: 0, calendar: utc)
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.milestonesReached, [7, 14, 21, 30])

        let partial = ChallengeTracker.status(c, today: start.adding(days: 40, calendar: utc),
                                              completedDays: Set(done.prefix(20)), planDaysRead: 0, calendar: utc)
        XCTAssertTrue(partial.isOver)
        XCTAssertFalse(partial.isFinished)
        XCTAssertEqual(partial.dayNumber, 30)
    }

    func testYearPace() {
        let c = Challenge(kind: .bibleInAYear, startedOn: day("2026-01-01"), planID: "shuffled-1")
        let today = day("2026-01-11") // 10 days have passed
        XCTAssertEqual(ChallengeTracker.status(c, today: today, completedDays: [], planDaysRead: 10, calendar: utc).pace, 0)
        let ahead = ChallengeTracker.status(c, today: today, completedDays: [], planDaysRead: 12, calendar: utc)
        XCTAssertEqual(ahead.pace, 2)
        XCTAssertEqual(ChallengeTracker.summary(c, ahead), "Bible in a Year · 12 of 365 days read · 2 days ahead")
        let behind = ChallengeTracker.status(c, today: today, completedDays: [], planDaysRead: 9, calendar: utc)
        XCTAssertEqual(ChallengeTracker.summary(c, behind), "Bible in a Year · 9 of 365 days read · 1 day behind")
        XCTAssertEqual(ChallengeTracker.status(c, today: day("2026-01-01"), completedDays: [], planDaysRead: 0, calendar: utc).pace, 0,
                       "Not behind on day one")
    }

    func testSettingsKeepChallenges() throws {
        var s = AnchorSettings()
        s.challenges = [Challenge(kind: .thirtyDay, startedOn: day("2026-03-01"))]
        let back = try JSONDecoder().decode(AnchorSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.challenges, s.challenges)
    }
}
