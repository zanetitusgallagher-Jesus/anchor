import AnchorCore
import Foundation
import Observation
import SwiftData

/// Root object shared by the menu bar, dashboard, settings and gate.
@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let settingsStore: SettingsStore
    let bibles = BibleStore()
    let plans = PlanStore()
    @ObservationIgnored private(set) lazy var gate = GateController(model: self)
    @ObservationIgnored private(set) lazy var focus = FocusController(model: self)
    /// Reads today's passage aloud (narrator over HTTPS, or the built-in voice).
    let listen = ListenController()

    /// Bumped whenever data changes outside SwiftUI queries, so summary views refresh.
    var revision = 0

    init(container: ModelContainer, settingsStore: SettingsStore? = nil) {
        self.container = container
        self.settingsStore = settingsStore ?? SettingsStore()
    }

    var settings: AnchorSettings {
        get { settingsStore.settings }
        set { settingsStore.settings = newValue }
    }

    var store: AnchorStore { AnchorStore(context: container.mainContext) }

    /// The bundled translation used for reading, memorizing and AI prompts.
    /// When an API.Bible translation is selected, WEB is the local fallback.
    var localTranslationID: String {
        BibleStore.bundled.contains { $0.id == settings.translationID } ? settings.translationID : "WEB"
    }

    var localBible: Bible? { bibles.bible(localTranslationID) }

    func customPlans() -> [CustomPlanRecord] {
        (try? container.mainContext.fetch(FetchDescriptor<CustomPlanRecord>())) ?? []
    }

    var currentPlan: ReadingPlan? {
        plans.plan(id: settings.planID, custom: customPlans(), bible: localBible, structure: bibles.bible("KJV"))
    }

    /// Next unread day of the current plan. Missing days never skip readings.
    func todaysReading() -> (plan: ReadingPlan, dayIndex: Int, chapters: [ChapterRef])? {
        guard let plan = currentPlan else { return nil }
        return reading(in: plan)
    }

    static let shortPlanID = "verse-a-day"

    /// The short fallback for days with little time, unless it's already the main plan.
    /// It starts over after its last day.
    func shortReading() -> (plan: ReadingPlan, dayIndex: Int, chapters: [ChapterRef])? {
        guard settings.planID != Self.shortPlanID,
              let plan = plans.plan(id: Self.shortPlanID, custom: [], bible: localBible) else { return nil }
        if let r = reading(in: plan) { return r }
        let record = store.progress(for: plan.id)
        record.completedDays = []
        record.completedDates = []
        store.save()
        return reading(in: plan)
    }

    private func reading(in plan: ReadingPlan) -> (plan: ReadingPlan, dayIndex: Int, chapters: [ChapterRef])? {
        let record = store.progress(for: plan.id)
        let progress = PlanProgress(planID: plan.id, completedDays: Set(record.completedDays))
        // If today's reading was already finished in this session, keep showing it.
        if let session = store.session(for: DayKey(.now), create: false),
           session.stepsCompleted.contains(GateStep.scripture.rawValue),
           let last = record.completedDays.last, last < plan.days.count {
            return (plan, last, plan.days[last])
        }
        guard let next = progress.nextDayIndex(totalDays: plan.days.count) else { return nil }
        return (plan, next, plan.days[next])
    }

    func touch() { revision += 1 }

    // MARK: Challenges

    func challengeStatuses(countingToday: Bool = false) -> [(challenge: Challenge, status: ChallengeStatus)] {
        let today = DayKey(.now)
        var done = store.completedDays()
        if countingToday { done.insert(today) }
        return settings.challenges.map { c in
            let read = c.planID.map { store.progress(for: $0).completedDays.count } ?? 0
            return (c, ChallengeTracker.status(c, today: today, completedDays: done, planDaysRead: read))
        }
    }

    /// Starts (or restarts) a challenge. Bible in a Year begins a freshly
    /// shuffled whole-Bible plan and makes it the current reading plan.
    func startChallenge(_ kind: Challenge.Kind) {
        var c = Challenge(kind: kind, startedOn: DayKey(.now))
        if kind == .bibleInAYear {
            let id = ReadingPlanGenerator.shuffledID(seed: UInt64.random(in: 1...999_999_999))
            c.planID = id
            settings.planID = id
        }
        settings.challenges.removeAll { $0.kind == kind }
        settings.challenges.append(c)
        touch()
    }

    func endChallenge(_ kind: Challenge.Kind) {
        settings.challenges.removeAll { $0.kind == kind }
        touch()
    }
}
