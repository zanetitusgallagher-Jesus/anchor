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
        plans.plan(id: settings.planID, custom: customPlans(), bible: localBible)
    }

    /// Next unread day of the current plan. Missing days never skip readings.
    func todaysReading() -> (plan: ReadingPlan, dayIndex: Int, chapters: [ChapterRef])? {
        guard let plan = currentPlan else { return nil }
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
}
