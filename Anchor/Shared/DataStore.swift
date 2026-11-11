import AnchorCore
import Foundation
import SwiftData

/// Queries and writes over the SwiftData store, used by every module.
@MainActor
struct DataStore {
    let context: ModelContext

    // MARK: Sessions & streaks

    func completedDays() -> Set<DayKey> {
        let all = (try? context.fetch(FetchDescriptor<DailySession>())) ?? []
        return Set(all.filter { $0.completedAt != nil }.compactMap { DayKey(string: $0.dayKey) })
    }

    func session(for day: DayKey, create: Bool = true) -> DailySession? {
        let key = day.description
        var d = FetchDescriptor<DailySession>(predicate: #Predicate { $0.dayKey == key })
        d.fetchLimit = 1
        if let s = try? context.fetch(d).first { return s }
        guard create else { return nil }
        let s = DailySession(dayKey: key)
        context.insert(s)
        save()
        return s
    }

    func sessions() -> [DailySession] {
        (try? context.fetch(FetchDescriptor<DailySession>(sortBy: [SortDescriptor(\.dayKey)]))) ?? []
    }

    // MARK: Unlock log

    func unlockedDays() -> Set<DayKey> {
        let all = (try? context.fetch(FetchDescriptor<UnlockEvent>())) ?? []
        return Set(all.filter { $0.kind != "safeLaunch" }.compactMap { DayKey(string: $0.dayKey) })
    }

    func logUnlock(kind: String, reason: String? = nil, now: Date = .now) {
        context.insert(UnlockEvent(date: now, dayKey: DayKey(now).description, kind: kind, reason: reason))
        save()
    }

    func unlockEvents() -> [UnlockEvent] {
        (try? context.fetch(FetchDescriptor<UnlockEvent>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    // MARK: Memory

    func allVerses() -> [MemoryVerse] {
        (try? context.fetch(FetchDescriptor<MemoryVerse>(sortBy: [SortDescriptor(\.addedAt)]))) ?? []
    }

    func dueVerses(on day: DayKey, limit: Int = 5) -> [MemoryVerse] {
        allVerses()
            .filter { (DayKey(string: $0.dueKey) ?? day) <= day }
            .sorted { $0.dueKey < $1.dueKey }
            .prefix(limit)
            .map { $0 }
    }

    func isMemorizing(_ ref: VerseRef) -> Bool {
        allVerses().contains { $0.bookID == ref.bookID && $0.chapter == ref.chapter && $0.verse == ref.verse }
    }

    func toggleMemorize(_ verse: Verse, translationID: String) {
        if let existing = allVerses().first(where: { $0.bookID == verse.ref.bookID && $0.chapter == verse.ref.chapter && $0.verse == verse.ref.verse }) {
            context.delete(existing)
        } else {
            context.insert(MemoryVerse(bookID: verse.ref.bookID, chapter: verse.ref.chapter, verse: verse.ref.verse,
                                       translationID: translationID, text: verse.text, today: DayKey(.now).description))
        }
        save()
    }

    func review(_ verse: MemoryVerse, quality: Int, today: DayKey = DayKey(.now)) {
        let state = SM2State(repetitions: verse.repetitions, interval: verse.interval, easeFactor: verse.easeFactor,
                             due: DayKey(string: verse.dueKey) ?? today)
        let next = SM2.review(state, quality: quality, on: today)
        verse.repetitions = next.repetitions
        verse.interval = next.interval
        verse.easeFactor = next.easeFactor
        verse.dueKey = next.due.description
        verse.lastReviewedAt = .now
        save()
    }

    // MARK: Plans

    func progress(for planID: String) -> PlanProgressRecord {
        let id = planID
        var d = FetchDescriptor<PlanProgressRecord>(predicate: #Predicate { $0.planID == id })
        d.fetchLimit = 1
        if let p = try? context.fetch(d).first { return p }
        let p = PlanProgressRecord(planID: planID)
        context.insert(p)
        save()
        return p
    }

    func markPlanDay(_ index: Int, planID: String) {
        let p = progress(for: planID)
        guard !p.completedDays.contains(index) else { return }
        p.completedDays.append(index)
        p.completedDates.append(.now)
        save()
    }

    // MARK: Journal

    func saveJournal(template: JournalTemplate, payload: JournalPayload, richText: Data?, existing: JournalEntry? = nil) throws -> JournalEntry {
        let cipher = try JournalCrypto.seal(json: payload)
        let rich = try richText.map { try JournalCrypto.seal($0) }
        if let e = existing {
            e.payloadCipher = cipher
            e.richTextCipher = rich
            e.templateRaw = template.rawValue
            e.updatedAt = .now
            save()
            return e
        }
        let e = JournalEntry(dayKey: DayKey(.now).description, templateRaw: template.rawValue, payloadCipher: cipher, richTextCipher: rich)
        context.insert(e)
        save()
        return e
    }

    func journalEntries() -> [JournalEntry] {
        (try? context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    func snapshot(_ e: JournalEntry) -> JournalSnapshot? {
        guard let p = try? JournalCrypto.open(JournalPayload.self, from: e.payloadCipher) else { return nil }
        var body = p.body
        if body.text.isEmpty, let rich = richText(e), let attr = NSAttributedString(rtf: rich, documentAttributes: nil) {
            body.text = attr.string
        }
        return JournalSnapshot(date: e.createdAt, template: JournalTemplate(rawValue: e.templateRaw) ?? .freeWrite,
                               body: body, tags: p.tags, mood: p.mood, passage: p.passage)
    }

    func richText(_ e: JournalEntry) -> Data? {
        e.richTextCipher.flatMap { try? JournalCrypto.open($0) }
    }

    // MARK: Prayer

    func prayers() -> [PrayerRequest] {
        (try? context.fetch(FetchDescriptor<PrayerRequest>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    func addPrayer(title: String, details: String) throws {
        context.insert(PrayerRequest(cipher: try JournalCrypto.seal(json: PrayerPayload(title: title, details: details))))
        save()
    }

    func payload(_ p: PrayerRequest) -> PrayerPayload? {
        try? JournalCrypto.open(PrayerPayload.self, from: p.cipher)
    }

    func markAnswered(_ p: PrayerRequest, note: String) throws {
        guard var payload = payload(p) else { return }
        payload.answerNote = note.isEmpty ? nil : note
        p.cipher = try JournalCrypto.seal(json: payload)
        p.answeredAt = .now
        save()
    }

    // MARK: Rewire

    func saveRewire(_ kind: RewireExercise, answers: [String: String]) throws {
        context.insert(RewireEntry(dayKey: DayKey(.now).description, kindRaw: kind.rawValue,
                                   cipher: try JournalCrypto.seal(json: answers)))
        save()
    }

    // MARK: Summary

    func summary(settings: AnchorSettings, today: DayKey = DayKey(.now)) -> DailySummary {
        let done = completedDays()
        let calc = StreakCalculator(scheduledWeekdays: settings.activeWeekdays)
        let verses = allVerses()
        let seconds = sessions().reduce(0) { $0 + $1.readingSeconds }
        return DailySummary(currentStreak: calc.currentStreak(completed: done, today: today),
                            longestStreak: calc.longestStreak(completed: done),
                            totalMinutesInWord: Int(seconds / 60),
                            versesMemorized: verses.filter { $0.interval >= 21 }.count,
                            versesInDeck: verses.count)
    }

    func save() {
        do { try context.save() } catch { NSLog("Anchor: save failed: \(error)") }
    }
}
