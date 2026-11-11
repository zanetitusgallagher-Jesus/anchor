import AnchorCore
import SwiftUI

/// Gate step: review the verses SM-2 says are due today.
struct MemoryStep: View {
    let flow: DailyFlow
    @Environment(AppModel.self) private var model
    @State private var finished = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Hide it in your heart")
                .font(.callout).foregroundStyle(Theme.secondaryInk).textCase(.uppercase).tracking(1.2)
            if finished {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reviews done").font(Theme.display(26))
                        Text("Each verse is scheduled for its next review.").foregroundStyle(Theme.secondaryInk)
                    }
                }
                StepFooter(flow: flow)
            } else {
                MemoryReviewView(verses: model.store.dueVerses(on: flow.today)) { finished = true }
                StepFooter(flow: flow, canContinue: !flow.isRequired(.memory))
            }
        }
    }
}

/// A review session over a set of cards. Cards graded below 4 come back once
/// at the end (SM-2 step 7) without being rescheduled twice.
struct MemoryReviewView: View {
    let verses: [MemoryVerse]
    var onFinished: () -> Void

    @Environment(AppModel.self) private var model
    @State private var queue: [MemoryVerse] = []
    @State private var reviewed: Set<UUID> = []
    @State private var position = 0
    @State private var mode: RecallMode = .firstLetter
    @State private var typed = ""
    @State private var clozeAnswers: [Int: String] = [:]
    @State private var checked: (accuracy: Double, quality: Int)?
    @State private var started = false

    var body: some View {
        Group {
            if position < queue.count {
                card(queue[position])
            } else if started {
                Color.clear.frame(height: 1).onAppear(perform: onFinished)
            }
        }
        .onAppear {
            guard !started else { return }
            queue = verses
            started = true
            if let first = queue.first { mode = RecallMode.suggested(for: state(first)) }
            if queue.isEmpty { onFinished() }
        }
    }

    private func state(_ v: MemoryVerse) -> SM2State {
        SM2State(repetitions: v.repetitions, interval: v.interval, easeFactor: v.easeFactor,
                 due: DayKey(string: v.dueKey) ?? DayKey(.now))
    }

    private func ref(_ v: MemoryVerse) -> String {
        VerseRef(bookID: v.bookID, chapter: v.chapter, verse: v.verse).description
    }

    @ViewBuilder private func card(_ v: MemoryVerse) -> some View {
        let settings = model.settings
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(ref(v)).font(Theme.display(26))
                    Text(v.translationID).font(.caption).foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    Text("\(position + 1) of \(queue.count)").font(.caption).foregroundStyle(Theme.secondaryInk)
                }
                Picker("Mode", selection: $mode) {
                    ForEach(RecallMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(checked != nil)

                switch mode {
                case .firstLetter:
                    Text(RecallText.firstLetters(v.text))
                        .font(Theme.scripture(settings, scale: 0.9))
                        .foregroundStyle(Theme.secondaryInk)
                        .textSelection(.disabled)
                    ParchmentEditor(text: $typed, placeholder: "Type the verse using the letters as hints…")
                case .cloze:
                    ClozeView(items: RecallText.cloze(v.text, seed: DayKey(.now).seed ^ UInt64(v.verse)),
                              answers: $clozeAnswers, revealed: checked != nil, font: Theme.scripture(settings, scale: 0.9))
                case .fullRecitation:
                    ParchmentEditor(text: $typed, placeholder: "Type the verse from memory…", minHeight: 120)
                }

                if let checked {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(v.text)
                            .font(Theme.scripture(settings, scale: 0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(Int((checked.accuracy * 100).rounded()))% recalled")
                            .font(.callout).foregroundStyle(Theme.secondaryInk)
                        HStack(spacing: 10) {
                            gradeButton("Forgot", 1, suggested: checked.quality, v)
                            gradeButton("Hard", 3, suggested: checked.quality, v)
                            gradeButton("Good", 4, suggested: checked.quality, v)
                            gradeButton("Easy", 5, suggested: checked.quality, v)
                        }
                    }
                } else {
                    HStack {
                        Button("Show me") { check(v, giveUp: true) }.buttonStyle(QuietButtonStyle())
                        Spacer()
                        Button("Check") { check(v, giveUp: false) }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
        }
    }

    private func gradeButton(_ title: String, _ q: Int, suggested: Int, _ v: MemoryVerse) -> some View {
        let isSuggested = (suggested <= 2 && q == 1) || suggested == q
        return Button(title) { grade(v, q) }
            .buttonStyle(.bordered)
            .tint(isSuggested ? Theme.accent : nil)
            .controlSize(.large)
    }

    private func check(_ v: MemoryVerse, giveUp: Bool) {
        var accuracy = 0.0
        if !giveUp {
            switch mode {
            case .firstLetter, .fullRecitation:
                accuracy = RecallGrader.accuracy(typed: typed, target: v.text)
            case .cloze:
                let items = RecallText.cloze(v.text, seed: DayKey(.now).seed ^ UInt64(v.verse))
                let hidden = items.indices.filter { items[$0].hidden }
                accuracy = RecallGrader.clozeAccuracy(answers: hidden.map { clozeAnswers[$0] ?? "" },
                                                      expected: hidden.map { items[$0].word })
            }
        }
        // Hints make recall easier, so cap the suggestion in the easier modes.
        var q = RecallGrader.quality(accuracy: accuracy)
        if mode == .firstLetter { q = min(q, 4) }
        checked = (accuracy, q)
    }

    private func grade(_ v: MemoryVerse, _ q: Int) {
        if !reviewed.contains(v.id) {
            model.store.review(v, quality: q)
            reviewed.insert(v.id)
            if SM2.needsRepeatInSession(quality: q) { queue.append(v) }
        }
        typed = ""
        clozeAnswers = [:]
        checked = nil
        position += 1
        if position < queue.count { mode = RecallMode.suggested(for: state(queue[position])) }
        model.touch()
    }
}

/// Verse text with blanks to fill in.
struct ClozeView: View {
    let items: [RecallText.ClozeItem]
    @Binding var answers: [Int: String]
    let revealed: Bool
    let font: Font

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 10) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                if item.hidden {
                    if revealed {
                        let ok = RecallText.normalize(answers[i] ?? "") == RecallText.normalize(item.word)
                        Text(item.word)
                            .font(font)
                            .foregroundStyle(ok ? Theme.accent : .red)
                            .underline()
                    } else {
                        TextField("", text: Binding(get: { answers[i] ?? "" }, set: { answers[i] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: max(60, CGFloat(item.word.count) * 11))
                    }
                } else {
                    Text(item.word).font(font)
                }
            }
        }
    }
}

/// Minimal wrapping layout for words.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(width, maxX), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
