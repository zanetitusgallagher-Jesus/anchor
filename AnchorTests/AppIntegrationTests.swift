import AnchorCore
import CryptoKit
import SwiftData
import XCTest
@testable import Anchor

/// App-level tests over an in-memory SwiftData store. The pure logic
/// (SM-2, streaks, gate policy) is tested in AnchorCore.
@MainActor
final class AppIntegrationTests: XCTestCase {
    var store: DataStore!

    override func setUp() async throws {
        store = DataStore(context: AnchorSchema.makeContainer(inMemory: true).mainContext)
    }

    func testCompletingTodayHidesTheGate() {
        let today = DayKey(.now)
        var settings = AnchorSettings()
        settings.graceCutoffHour = 24
        settings.activeWeekdays = Set(1...7)

        func decision() -> GateDecision {
            GatePolicy.evaluate(GateContext(now: .now, completedDays: store.completedDays(),
                                            emergencyUnlockedDays: store.unlockedDays()), settings: settings)
        }
        XCTAssertEqual(decision(), .show)

        let s = store.session(for: today)!
        XCTAssertEqual(decision(), .show, "Starting a session is not completing it")
        s.completedAt = .now
        store.save()
        XCTAssertEqual(decision(), .hidden(.completedToday))
    }

    func testEmergencyUnlockIsLoggedAndReleasesToday() {
        var settings = AnchorSettings()
        settings.graceCutoffHour = 24
        store.logUnlock(kind: "emergency", reason: "test")
        XCTAssertEqual(store.unlockEvents().count, 1)
        let d = GatePolicy.evaluate(GateContext(now: .now, completedDays: [], emergencyUnlockedDays: store.unlockedDays()), settings: settings)
        XCTAssertEqual(d, .hidden(.emergencyUnlockedToday))
    }

    func testSafeLaunchIsLoggedButNotCountedAsUnlock() {
        store.logUnlock(kind: "safeLaunch")
        XCTAssertEqual(store.unlockEvents().count, 1)
        XCTAssertTrue(store.unlockedDays().isEmpty)
    }

    func testMemoryVerseScheduling() {
        let verse = Verse(ref: VerseRef(bookID: "JHN", chapter: 3, verse: 16), text: "For God so loved the world")
        store.toggleMemorize(verse, translationID: "WEB")
        let today = DayKey(.now)
        XCTAssertEqual(store.dueVerses(on: today).count, 1)
        store.review(store.allVerses()[0], quality: 5, today: today)
        XCTAssertTrue(store.dueVerses(on: today).isEmpty)
        XCTAssertEqual(store.dueVerses(on: today.adding(days: 1)).count, 1)
        store.toggleMemorize(verse, translationID: "WEB")
        XCTAssertTrue(store.allVerses().isEmpty)
    }

    func testPlanProgress() {
        store.markPlanDay(0, planID: "nt-90")
        store.markPlanDay(0, planID: "nt-90")
        store.markPlanDay(1, planID: "nt-90")
        XCTAssertEqual(store.progress(for: "nt-90").completedDays, [0, 1])
    }

    func testEncryptionRoundTripAndTamperDetection() throws {
        let key = SymmetricKey(size: .bits256)
        let payload = Data("Lord, teach me to pray.".utf8)
        let sealed = try JournalCrypto.seal(payload, key: key)
        XCTAssertNotEqual(sealed, payload)
        XCTAssertFalse(String(decoding: sealed, as: UTF8.self).contains("pray"))
        XCTAssertEqual(try JournalCrypto.open(sealed, key: key), payload)

        var tampered = sealed
        tampered[tampered.count - 1] ^= 0xFF
        XCTAssertThrowsError(try JournalCrypto.open(tampered, key: key))
        XCTAssertThrowsError(try JournalCrypto.open(sealed, key: SymmetricKey(size: .bits256)))
    }

    func testBundledResourcesLoad() {
        let bibles = BibleStore()
        let web = bibles.bible("WEB")
        XCTAssertEqual(web?.books.count, 66)
        XCTAssertEqual(web?.verses(ChapterRef(bookID: "PSA", chapter: 23)).count, 6)
        XCTAssertEqual(bibles.bible("KJV")?.text(VerseRef(bookID: "JHN", chapter: 11, verse: 35)), "Jesus wept.")
        let plans = PlanStore()
        XCTAssertEqual(plans.seedPlans.map(\.id), PlanStore.seedIDs)
        XCTAssertEqual(plans.seedPlans.first?.days.count, 365)
    }

    func testReadingTitle() {
        let t = DailyFlow.TodayReading.describe([
            ChapterRef(bookID: "PSA", chapter: 1), ChapterRef(bookID: "PSA", chapter: 2),
            ChapterRef(bookID: "PSA", chapter: 3), ChapterRef(bookID: "PRO", chapter: 1),
        ])
        XCTAssertEqual(t, "Psalms 1–3, Proverbs 1")
    }
}
