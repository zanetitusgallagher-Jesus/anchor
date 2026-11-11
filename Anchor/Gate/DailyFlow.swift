import AnchorCore
import Foundation
import Observation

/// State of one pass through the gate. Steps already finished earlier today
/// (for example before a restart) are skipped.
@MainActor
@Observable
final class DailyFlow {
    struct TodayReading {
        let plan: ReadingPlan
        let dayIndex: Int
        let chapters: [ChapterRef]
        var title: String {
            Self.describe(chapters)
        }

        /// "Genesis 1–3" or "Psalms 1–5, Proverbs 1".
        static func describe(_ chapters: [ChapterRef]) -> String {
            var groups: [(book: String, first: Int, last: Int)] = []
            for c in chapters {
                if let g = groups.last, g.book == c.bookID, g.last + 1 == c.chapter {
                    groups[groups.count - 1].last = c.chapter
                } else {
                    groups.append((c.bookID, c.chapter, c.chapter))
                }
            }
            return groups.map { g in
                let name = BookCatalog.name(g.book)
                return g.first == g.last ? "\(name) \(g.first)" : "\(name) \(g.first)–\(g.last)"
            }.joined(separator: ", ")
        }
    }

    @ObservationIgnored unowned var model: AppModel
    @ObservationIgnored unowned var controller: GateController

    let today = DayKey(.now)
    private(set) var steps: [GateStep]
    private(set) var index = 0
    let reading: TodayReading?
    let prompt: ReflectionPrompt
    let rewireToday: [RewireExercise]
    var readingSeconds: Double = 0
    var reflectionAnswer = ""

    init(model: AppModel, controller: GateController) {
        self.model = model
        self.controller = controller
        let settings = model.settings
        let store = model.store
        prompt = ReflectionPrompt.forDay(today)
        rewireToday = RewireScheduler.exercises(for: today, enabled: settings.enabledRewire, perDay: settings.rewirePerDay)
        if let r = model.todaysReading() {
            reading = TodayReading(plan: r.plan, dayIndex: r.dayIndex, chapters: r.chapters)
        } else {
            reading = nil
        }
        let all = GateFlow.steps(settings: settings,
                                 hasDueMemoryVerses: !store.dueVerses(on: today).isEmpty,
                                 hasRewireToday: !rewireToday.isEmpty)
        let done = Set(store.session(for: today, create: false)?.stepsCompleted ?? [])
        steps = all.filter { $0 == .welcome || $0 == .unlock || !done.contains($0.rawValue) }
        readingSeconds = store.session(for: today, create: false)?.readingSeconds ?? 0
    }

    var current: GateStep { steps[min(index, steps.count - 1)] }
    var progress: Double { steps.count <= 1 ? 1 : Double(index) / Double(steps.count - 1) }

    func isRequired(_ step: GateStep) -> Bool { model.settings.isRequired(step) }

    /// Marks the current step done (persisted, so a restart resumes here) and moves on.
    func advance() {
        let step = current
        if step != .welcome && step != .unlock, let s = model.store.session(for: today) {
            if !s.stepsCompleted.contains(step.rawValue) { s.stepsCompleted.append(step.rawValue) }
            model.store.save()
        }
        index = min(index + 1, steps.count - 1)
    }

    /// Optional steps can be skipped without being marked complete.
    func skip() {
        guard !isRequired(current) else { return }
        index = min(index + 1, steps.count - 1)
    }

    func finishScripture() {
        guard let reading else { advance(); return }
        let store = model.store
        store.markPlanDay(reading.dayIndex, planID: reading.plan.id)
        if let s = store.session(for: today) {
            s.readingSeconds = readingSeconds
            s.passage = reading.title
            store.save()
        }
        advance()
    }

    func recordReadingTick(_ seconds: Double) {
        readingSeconds += seconds
    }
}
