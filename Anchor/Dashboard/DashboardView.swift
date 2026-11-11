import AnchorCore
import SwiftData
import SwiftUI

struct DashboardView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview", plan = "Reading plan", memory = "Memory verses"
        case journal = "Journal", prayers = "Answered prayers", log = "Unlock log"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: "calendar"
            case .plan: "book"
            case .memory: "brain.head.profile"
            case .journal: "square.and.pencil"
            case .prayers: "hands.sparkles"
            case .log: "lock.open"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var section: Section? = .overview

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            ScrollView {
                Group {
                    switch section ?? .overview {
                    case .overview: OverviewPanel()
                    case .plan: PlanPanel()
                    case .memory: MemoryPanel()
                    case .journal: JournalPanel()
                    case .prayers: PrayerTimelinePanel()
                    case .log: UnlockLogPanel()
                    }
                }
                .padding(28)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)
        }
        .frame(minWidth: 860, minHeight: 600)
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(Theme.colorScheme(model.settings.appearance))
    }
}

struct PanelTitle: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.display(30))
            if let subtitle { Text(subtitle).foregroundStyle(Theme.secondaryInk) }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Overview

struct OverviewPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let store = model.store
        let summary = store.summary(settings: model.settings)
        let done = store.completedDays()
        let unlocked = store.unlockedDays()
        let today = DayKey(.now)
        let decision = model.gate.currentDecision()

        VStack(alignment: .leading, spacing: 24) {
            PanelTitle(title: "Overview", subtitle: done.contains(today) ? "Today’s session is complete." : "Today’s session is waiting.")

            HStack(spacing: 14) {
                StatTile(value: "\(summary.currentStreak)", label: "Current streak", icon: "flame")
                StatTile(value: "\(summary.longestStreak)", label: "Longest streak", icon: "trophy")
                StatTile(value: "\(summary.totalMinutesInWord)", label: "Minutes in the Word", icon: "book")
                StatTile(value: "\(summary.versesMemorized)/\(summary.versesInDeck)", label: "Verses memorized", icon: "brain.head.profile")
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Last 26 weeks").font(.headline)
                    StreakHeatmap(completed: done, unlocked: unlocked, today: today, weeks: 26)
                    HStack(spacing: 14) {
                        legend(Theme.heat, "Completed")
                        legend(Theme.hairline, "Missed")
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.accent, lineWidth: 1).frame(width: 10, height: 10)
                            Text("Emergency unlock")
                        }
                    }
                    .font(.caption).foregroundStyle(Theme.secondaryInk)
                }
            }

            if !done.contains(today) {
                HStack {
                    Text(gateDescription(decision)).foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    Button("Start today’s session") { model.gate.present(.voluntary) }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private func gateDescription(_ d: GateDecision) -> String {
        switch d {
        case .show: "The gate will appear now."
        case .hidden(.disabled): "The gate is turned off."
        case .hidden(.notScheduledToday): "No gate today (not a scheduled day)."
        case .hidden(.completedToday): "Done for today."
        case .hidden(.emergencyUnlockedToday): "Unlocked for today."
        case .hidden(.outsideGraceWindow): "Past today’s gate window — you can still do the session."
        case .hidden(.safeLaunch): "Safe launch (Shift held) — no gate today."
        }
    }

    private func legend(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(label)
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(Theme.accent)
            Text(value).font(Theme.display(30)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline))
    }
}

/// GitHub-style calendar: one column per week, Sunday at the top.
struct StreakHeatmap: View {
    let completed: Set<DayKey>
    let unlocked: Set<DayKey>
    let today: DayKey
    let weeks: Int
    private let cell: CGFloat = 13
    private let gap: CGFloat = 3

    var body: some View {
        let start = startOfGrid()
        HStack(alignment: .top, spacing: gap) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { d in
                        let day = start.adding(days: w * 7 + d)
                        square(day)
                    }
                }
            }
        }
    }

    @ViewBuilder private func square(_ day: DayKey) -> some View {
        if day > today {
            Color.clear.frame(width: cell, height: cell)
        } else if completed.contains(day) {
            RoundedRectangle(cornerRadius: 3).fill(Theme.heat).frame(width: cell, height: cell)
                .help("\(day): completed")
        } else if unlocked.contains(day) {
            RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.accent, lineWidth: 1).frame(width: cell, height: cell)
                .help("\(day): emergency unlock")
        } else {
            RoundedRectangle(cornerRadius: 3).fill(Theme.hairline).frame(width: cell, height: cell)
                .help("\(day)")
        }
    }

    private func startOfGrid() -> DayKey {
        // Go back to the Sunday `weeks - 1` weeks ago.
        let back = (weeks - 1) * 7 + (today.weekday() - 1)
        return today.adding(days: -back)
    }
}

// MARK: - Reading plan

struct PlanPanel: View {
    @Environment(AppModel.self) private var model
    @State private var showBuilder = false

    var body: some View {
        let _ = model.revision
        let plans = model.plans.seedPlans
        let custom = model.customPlans()
        VStack(alignment: .leading, spacing: 20) {
            PanelTitle(title: "Reading plan", subtitle: "Missing a day never skips a reading — you simply pick up where you left off.")
            if let plan = model.currentPlan {
                let rec = model.store.progress(for: plan.id)
                let progress = PlanProgress(planID: plan.id, completedDays: Set(rec.completedDays))
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(plan.name).font(Theme.display(24))
                        Text(plan.summary).foregroundStyle(Theme.secondaryInk)
                        ProgressView(value: progress.fractionComplete(totalDays: plan.days.count)).tint(Theme.accent)
                        Text("\(progress.completedDays.count) of \(plan.days.count) days")
                            .font(.callout).foregroundStyle(Theme.secondaryInk)
                        if let next = progress.nextDayIndex(totalDays: plan.days.count) {
                            Text("Next: \(DailyFlow.TodayReading.describe(plan.days[next]))").font(.callout)
                        }
                    }
                }
            }
            Text("Choose a plan").font(.headline)
            ForEach(plans) { p in planRow(p.id, p.name, p.summary) }
            ForEach(custom) { c in planRow(c.planID, c.name, "\(c.bookIDs.count) book(s) over \(c.days) days") }
            Button("Create a custom plan…") { showBuilder = true }
        }
        .sheet(isPresented: $showBuilder) { CustomPlanBuilder() }
    }

    private func planRow(_ id: String, _ name: String, _ summary: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name).font(.system(size: 15, weight: .medium))
                Text(summary).font(.caption).foregroundStyle(Theme.secondaryInk)
            }
            Spacer()
            if model.settings.planID == id {
                Label("Current", systemImage: "checkmark").foregroundStyle(Theme.accent)
            } else {
                Button("Use this plan") { model.settings.planID = id; model.touch() }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CustomPlanBuilder: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = "My plan"
    @State private var selected: Set<String> = []
    @State private var days = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Custom plan").font(Theme.display(24))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            Stepper("Spread over \(days) days", value: $days, in: 1...730)
            Text("Books").font(.headline)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading, spacing: 6) {
                    ForEach(BookCatalog.all, id: \.id) { b in
                        Toggle(b.name, isOn: Binding(get: { selected.contains(b.id) },
                                                     set: { if $0 { selected.insert(b.id) } else { selected.remove(b.id) } }))
                    }
                }
            }
            .frame(height: 280)
            let chapters = BookCatalog.chapters(of: BookCatalog.all.map(\.id).filter(selected.contains)).count
            Text("\(chapters) chapters").font(.caption).foregroundStyle(Theme.secondaryInk)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create & use") {
                    let id = "custom-\(UUID().uuidString.prefix(8))"
                    let ordered = BookCatalog.all.map(\.id).filter(selected.contains)
                    model.container.mainContext.insert(CustomPlanRecord(planID: id, name: name, bookIDs: ordered, days: days))
                    model.store.save()
                    model.settings.planID = id
                    model.touch()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selected.isEmpty || name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

// MARK: - Memory

struct MemoryPanel: View {
    @Environment(AppModel.self) private var model
    @State private var reviewing = false

    var body: some View {
        let _ = model.revision
        let verses = model.store.allVerses()
        let due = model.store.dueVerses(on: DayKey(.now), limit: 50)
        VStack(alignment: .leading, spacing: 18) {
            PanelTitle(title: "Memory verses", subtitle: "Star a verse while reading to add it. Reviews are scheduled with SM-2.")
            if !due.isEmpty {
                Button("Review \(due.count) due now") { reviewing = true }.buttonStyle(PrimaryButtonStyle())
            }
            if verses.isEmpty {
                Text("No verses yet.").foregroundStyle(Theme.secondaryInk)
            }
            ForEach(verses) { v in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(VerseRef(bookID: v.bookID, chapter: v.chapter, verse: v.verse).description) · \(v.translationID)")
                            .font(.system(size: 14, weight: .semibold))
                        Text(v.text).font(.system(size: 14, design: .serif)).foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(v.interval >= 21 ? "Memorized" : "Learning").font(.caption.weight(.medium))
                            .foregroundStyle(v.interval >= 21 ? Theme.accent : Theme.secondaryInk)
                        Text("Due \(v.dueKey)").font(.caption).foregroundStyle(Theme.secondaryInk)
                        Text("Every \(max(1, v.interval))d · ease \(v.easeFactor, specifier: "%.2f")").font(.caption2).foregroundStyle(Theme.secondaryInk)
                    }
                    Button { model.container.mainContext.delete(v); model.store.save(); model.touch() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove from deck")
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        .sheet(isPresented: $reviewing) {
            VStack {
                MemoryReviewView(verses: due) { reviewing = false }
                Button("Close") { reviewing = false }.buttonStyle(QuietButtonStyle())
            }
            .padding(24)
            .frame(width: 640)
            .background(Theme.background)
        }
    }
}

// MARK: - Prayers & log

struct PrayerTimelinePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let store = model.store
        let answered = store.prayers().filter { $0.answeredAt != nil }.sorted { $0.answeredAt! > $1.answeredAt! }
        VStack(alignment: .leading, spacing: 18) {
            PanelTitle(title: "Prayer", subtitle: "Open requests, and a record of how God has answered.")
            Card { PrayerListView() }
            Text("Answered").font(.headline)
            if answered.isEmpty {
                Text("When you mark a request answered, it appears here.").foregroundStyle(Theme.secondaryInk)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(answered) { p in
                    let payload = store.payload(p)
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle().fill(Theme.accent).frame(width: 10, height: 10)
                            Rectangle().fill(Theme.hairline).frame(width: 2).frame(maxHeight: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.answeredAt!.formatted(date: .long, time: .omitted)).font(.caption).foregroundStyle(Theme.secondaryInk)
                            Text(payload?.title ?? "—").font(.system(size: 16, design: .serif))
                            if let note = payload?.answerNote { Text(note).foregroundStyle(Theme.secondaryInk) }
                            let days = Calendar.current.dateComponents([.day], from: p.createdAt, to: p.answeredAt!).day ?? 0
                            Text("Prayed for \(days) day\(days == 1 ? "" : "s")").font(.caption2).foregroundStyle(Theme.secondaryInk)
                        }
                        .padding(.bottom, 18)
                    }
                }
            }
        }
    }
}

struct UnlockLogPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let events = model.store.unlockEvents()
        VStack(alignment: .leading, spacing: 14) {
            PanelTitle(title: "Unlock log", subtitle: "Every emergency unlock, failsafe release and Shift safe-launch.")
            if events.isEmpty { Text("No unlocks. 🙏").foregroundStyle(Theme.secondaryInk) }
            ForEach(events) { e in
                HStack {
                    Image(systemName: e.kind == "emergency" ? "lock.open" : e.kind == "failsafe" ? "timer" : "shift")
                        .foregroundStyle(Theme.accent).frame(width: 20)
                    VStack(alignment: .leading) {
                        Text(label(e.kind)).font(.system(size: 14, weight: .medium))
                        if let r = e.reason { Text(r).font(.caption).foregroundStyle(Theme.secondaryInk) }
                    }
                    Spacer()
                    Text(e.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.secondaryInk)
                }
                Divider()
            }
        }
    }

    private func label(_ kind: String) -> String {
        switch kind {
        case "emergency": "Emergency unlock"
        case "failsafe": "Failsafe released the gate"
        case "safeLaunch": "Safe launch (Shift held)"
        default: kind
        }
    }
}
