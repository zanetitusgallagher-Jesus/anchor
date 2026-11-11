import XCTest
@testable import AnchorCore

final class ReadingPlanTests: XCTestCase {
    func testSplitCoversEveryChapterInOrder() {
        let chapters = BookCatalog.chapters(of: BookCatalog.all.map(\.id))
        XCTAssertEqual(chapters.count, 1189)
        let days = ReadingPlanGenerator.split(chapters, days: 365)
        XCTAssertEqual(days.count, 365)
        XCTAssertEqual(days.flatMap { $0 }, chapters)
        XCTAssertTrue(days.allSatisfy { !$0.isEmpty })
        XCTAssertLessThanOrEqual(days.map(\.count).max()! - days.map(\.count).min()!, 1)
    }

    func testSplitBalancesWeights() {
        let chapters = (1...6).map { ChapterRef(bookID: "PSA", chapter: $0) }
        let days = ReadingPlanGenerator.split(chapters, weights: [10, 1, 1, 1, 1, 6], days: 2)
        XCTAssertEqual(days.map(\.count), [1, 5])
    }

    func testMoreDaysThanChapters() {
        let chapters = BookCatalog.chapters(of: ["JUD", "PHM"])
        XCTAssertEqual(ReadingPlanGenerator.split(chapters, days: 30).count, 2)
    }

    func testProgressFollowsCompletedDaysNotCalendar() {
        var p = PlanProgress(planID: "x")
        XCTAssertEqual(p.nextDayIndex(totalDays: 3), 0)
        p.completedDays = [0, 1]
        XCTAssertEqual(p.nextDayIndex(totalDays: 3), 2)
        XCTAssertEqual(p.fractionComplete(totalDays: 4), 0.5)
        p.completedDays = [0, 1, 2]
        XCTAssertNil(p.nextDayIndex(totalDays: 3))
    }

    func testReferences() {
        XCTAssertEqual(ChapterRef(bookID: "JHN", chapter: 3).description, "John 3")
        XCTAssertEqual(ChapterRef(bookID: "1CO", chapter: 13).apiBibleID, "1CO.13")
        XCTAssertEqual(VerseRef(bookID: "PSA", chapter: 23, verse: 1).description, "Psalms 23:1")
        XCTAssertTrue(VerseRef(bookID: "GEN", chapter: 50, verse: 1) < VerseRef(bookID: "EXO", chapter: 1, verse: 1))
    }

    func testDayKeyRoundTrip() {
        XCTAssertEqual(day("2026-02-28").adding(days: 1, calendar: utc), day("2026-03-01"))
        XCTAssertEqual(day("2026-03-01").description, "2026-03-01")
        XCTAssertEqual(day("2026-03-10").weekday(calendar: utc), 3) // Tuesday
    }
}

final class RecallTests: XCTestCase {
    let verse = "For God so loved the world, that he gave his only begotten Son."

    func testFirstLetters() {
        XCTAssertEqual(RecallText.firstLetters("For God so loved the world, that he"), "F G s l t w, t h")
        XCTAssertEqual(RecallText.firstLetters("“Be still.”"), "“B s.”")
    }

    func testPerfectRecallIgnoresCaseAndPunctuation() {
        let a = RecallGrader.accuracy(typed: "for god so loved the world that he gave his only begotten son", target: verse)
        XCTAssertEqual(a, 1, accuracy: 1e-9)
        XCTAssertEqual(RecallGrader.quality(accuracy: a), 5)
    }

    func testPartialRecall() {
        let a = RecallGrader.accuracy(typed: "For God so loved the world", target: verse)
        XCTAssertEqual(RecallGrader.quality(accuracy: a), 2)
        XCTAssertEqual(RecallGrader.accuracy(typed: "", target: verse), 0)
        XCTAssertEqual(RecallGrader.quality(accuracy: 0), 0)
    }

    func testCurlyApostrophes() {
        XCTAssertEqual(RecallGrader.accuracy(typed: "doesnt walk", target: "doesn’t walk"), 1, accuracy: 1e-9)
    }

    func testClozeIsDeterministicAndHidesWords() {
        let a = RecallText.cloze(verse, seed: 42)
        let b = RecallText.cloze(verse, seed: 42)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.map(\.word), RecallText.tokens(verse))
        XCTAssertGreaterThan(a.filter(\.hidden).count, 0)
        XCTAssertTrue(a.filter(\.hidden).allSatisfy { RecallText.normalize($0.word).count >= 3 })
    }

    func testClozeGrading() {
        XCTAssertEqual(RecallGrader.clozeAccuracy(answers: ["World", "gave"], expected: ["world,", "gave"]), 1)
        XCTAssertEqual(RecallGrader.clozeAccuracy(answers: ["earth", "gave"], expected: ["world", "gave"]), 0.5)
    }

    func testSuggestedModeProgression() {
        let d = day("2026-01-01")
        XCTAssertEqual(RecallMode.suggested(for: SM2State(repetitions: 0, due: d)), .firstLetter)
        XCTAssertEqual(RecallMode.suggested(for: SM2State(repetitions: 2, due: d)), .cloze)
        XCTAssertEqual(RecallMode.suggested(for: SM2State(repetitions: 5, due: d)), .fullRecitation)
    }
}

final class DailyContentTests: XCTestCase {
    func testReflectionRotatesDaily() {
        let d = day("2026-05-01")
        let three = (0..<3).map { ReflectionPrompt.forDay(d.adding(days: $0, calendar: utc), calendar: utc) }
        XCTAssertEqual(Set(three).count, 3)
    }

    func testRewireRotation() {
        let d = day("2026-05-01")
        let all = Set(RewireExercise.allCases)
        let picks = (0..<4).flatMap { RewireScheduler.exercises(for: d.adding(days: $0, calendar: utc), enabled: all, perDay: 1, calendar: utc) }
        XCTAssertEqual(Set(picks), all)
        XCTAssertEqual(RewireScheduler.exercises(for: d, enabled: all, perDay: 2, calendar: utc).count, 2)
        XCTAssertEqual(RewireScheduler.exercises(for: d, enabled: [.gratitude], perDay: 2, calendar: utc), [.gratitude])
        XCTAssertTrue(RewireScheduler.exercises(for: d, enabled: [], perDay: 2, calendar: utc).isEmpty)
    }

    func testBoxBreathingPhases() {
        XCTAssertEqual(BoxBreathing.phase(at: 0).phase, .inhale)
        XCTAssertEqual(BoxBreathing.phase(at: 5).phase, .holdFull)
        XCTAssertEqual(BoxBreathing.phase(at: 9).phase, .exhale)
        XCTAssertEqual(BoxBreathing.phase(at: 13).phase, .holdEmpty)
        XCTAssertEqual(BoxBreathing.phase(at: 16).phase, .inhale)
        XCTAssertEqual(BoxBreathing.scale(at: 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(BoxBreathing.scale(at: 6), 1)
    }

    func testTagsParse() {
        XCTAssertEqual(Tags.parse("Faith, #hope  , faith,\nRest"), ["faith", "hope", "rest"])
    }

    func testJournalSearchAndExport() {
        let e = JournalSnapshot(date: date("2026-03-10"), template: .soap,
                                body: JournalBody(fields: [.observation: "God is patient", .application: "Call mom"]),
                                tags: ["patience"], mood: 4, passage: "Romans 5")
        XCTAssertTrue(JournalSearch.matches(e, .init(text: "patient")))
        XCTAssertTrue(JournalSearch.matches(e, .init(tag: "Patience")))
        XCTAssertTrue(JournalSearch.matches(e, .init(bookID: "ROM")))
        XCTAssertFalse(JournalSearch.matches(e, .init(bookID: "JHN")))
        XCTAssertFalse(JournalSearch.matches(e, .init(from: date("2026-03-11"))))

        let md = JournalExporter.markdown([e], calendar: utc)
        XCTAssertTrue(md.contains("SOAP"))
        XCTAssertTrue(md.contains("### Observation\n\nGod is patient"))
        XCTAssertTrue(md.contains("**Tags:** #patience"))
        XCTAssertFalse(md.contains("### Scripture"))
    }

    func testBundledBibleDecodes() throws {
        let json = #"{"id":"T","name":"Test","books":[{"id":"JHN","name":"John","chapters":[["In the beginning",""]]}]}"#
        let b = try Bible.decode(Data(json.utf8))
        XCTAssertEqual(b.verses(ChapterRef(bookID: "JHN", chapter: 1)).count, 1)
        XCTAssertEqual(b.text(VerseRef(bookID: "JHN", chapter: 1, verse: 1)), "In the beginning")
        XCTAssertNil(b.text(VerseRef(bookID: "JHN", chapter: 2, verse: 1)))
    }
}
