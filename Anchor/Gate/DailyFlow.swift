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
        /// "Genesis 1–3", "Psalms 1–5, Proverbs 1", "Isaiah 40:1–15, John 6:22–end".
        static func describe(_ chapters: [ChapterRef]) -> String {
            var groups: [(book: String, first: Int, last: Int, range: ChapterRef?)] = []
            for c in chapters {
                if c.isWholeChapter, let g = groups.last, g.range == nil, g.book == c.bookID, g.last + 1 == c.chapter {
                    groups[groups.count - 1].last = c.chapter
                } else {
                    groups.append((c.bookID, c.chapter, c.chapter, c.isWholeChapter ? nil : c))
                }
            }
            return groups.map { g in
                if let r = g.range { return r.description }
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
    /// The reading for this session: from the main plan, or from Verse a Day
    /// when less time was chosen than the main reading needs.
    private(set) var reading: TodayReading?
    /// Today's day of the main plan (e.g. Bible in a Year).
    let mainReading: TodayReading?
    /// The short fallback (Verse a Day), if the main plan isn't already it.
    let shortReading: TodayReading?
    let prompt: ReflectionPrompt
    private(set) var rewireToday: [RewireExercise]
    /// Today's shape, chosen with the Welcome screen's time slider.
    private(set) var plan: SessionPlan
    /// Words in the main plan's reading today, and the minutes they take.
    let readingWords: Int
    let requiredReadingMinutes: Int
    var minutesRange: ClosedRange<Int> {
        SessionPlanner.sliderRange(mainRequiredMinutes: requiredReadingMinutes, hasShortPlan: shortReading != nil)
    }
    /// The fewest minutes that keep today on the main plan.
    var mainPlanMinimum: Int { SessionPlanner.mainPlanMinimum(mainRequiredMinutes: requiredReadingMinutes) }

    func choice(minutes: Int) -> SessionPlanner.ReadingChoice {
        SessionPlanner.choice(minutes: minutes, mainRequiredMinutes: requiredReadingMinutes, hasShortPlan: shortReading != nil)
    }
    var readingSeconds: Double = 0
    var reflectionAnswer = ""

    init(model: AppModel, controller: GateController) {
        self.model = model
        self.controller = controller
        let settings = model.settings
        let store = model.store
        prompt = ReflectionPrompt.forDay(today)
        let main = model.todaysReading().map { TodayReading(plan: $0.plan, dayIndex: $0.dayIndex, chapters: $0.chapters) }
        let short = model.shortReading().map { TodayReading(plan: $0.plan, dayIndex: $0.dayIndex, chapters: $0.chapters) }
        mainReading = main
        shortReading = short
        let words = Self.words(main, model: model)
        readingWords = words
        requiredReadingMinutes = ReadingEstimate.minutes(words: words)
        let minutes = settings.sessionMinutes
        let useShort = short != nil && SessionPlanner.choice(minutes: minutes, mainRequiredMinutes: requiredReadingMinutes,
                                                             hasShortPlan: true) == .short
        reading = useShort ? short : main
        let built = Self.build(minutes: minutes, model: model, today: today,
                               requiredReading: ReadingEstimate.minutes(words: Self.words(useShort ? short : main, model: model)))
        plan = built.plan
        rewireToday = built.rewire
        steps = built.steps
        readingSeconds = store.session(for: today, create: false)?.readingSeconds ?? 0
    }

    private static func words(_ r: TodayReading?, model: AppModel) -> Int {
        guard let r else { return 0 }
        return ReadingEstimate.words(in: r.chapters.flatMap { model.localBible?.verses($0).map(\.text) ?? [] })
    }

    /// The reading and session shape for a slider value.
    private func shape(minutes: Int) -> (reading: TodayReading?, built: (plan: SessionPlan, rewire: [RewireExercise], steps: [GateStep])) {
        let r = choice(minutes: minutes) == .short ? shortReading : mainReading
        let need = ReadingEstimate.minutes(words: Self.words(r, model: model))
        return (r, Self.build(minutes: minutes, model: model, today: today, requiredReading: need))
    }

    private static func build(minutes: Int, model: AppModel, today: DayKey, requiredReading: Int)
        -> (plan: SessionPlan, rewire: [RewireExercise], steps: [GateStep]) {
        let settings = model.settings
        let store = model.store
        let available = RewireScheduler.exercises(for: today, enabled: settings.enabledRewire, perDay: 2)
        let plan = SessionPlanner.plan(minutes: minutes, settings: settings,
                                       hasDueMemoryVerses: !store.dueVerses(on: today).isEmpty,
                                       rewireAvailable: available.count,
                                       requiredReadingMinutes: requiredReading)
        // Steps already finished earlier today (e.g. before a restart) are skipped.
        let done = Set(store.session(for: today, create: false)?.stepsCompleted ?? [])
        let steps = plan.steps.filter { $0 == .welcome || $0 == .unlock || !done.contains($0.rawValue) }
        return (plan, Array(available.prefix(plan.rewireCount)), steps)
    }

    /// Called from the Welcome screen's Begin button with the slider's value.
    func begin(minutes: Int) {
        model.settings.sessionMinutes = minutes
        let shaped = shape(minutes: minutes)
        reading = shaped.reading
        let built = shaped.built
        plan = built.plan
        rewireToday = built.rewire
        steps = built.steps
        index = 0
        advance()
    }

    /// Preview for the slider: what a session of `minutes` would include.
    func preview(minutes: Int) -> SessionPlan {
        shape(minutes: minutes).built.plan
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
            s.planID = reading.plan.id
            s.planName = reading.plan.name
            store.save()
        }
        advance()
    }

    func recordReadingTick(_ seconds: Double) {
        readingSeconds += seconds
    }
}
