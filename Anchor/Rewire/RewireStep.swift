import AnchorCore
import SwiftUI

/// Short habit and mindset exercises. The copy describes what the research
/// supports and no more.
struct RewireStep: View {
    let flow: DailyFlow
    @Environment(AppModel.self) private var model
    @State private var position = 0

    var body: some View {
        let exercises = flow.rewireToday
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Rewire").font(.callout).foregroundStyle(Theme.secondaryInk).textCase(.uppercase).tracking(1.2)
                Spacer()
                if exercises.count > 1 {
                    Text("\(min(position + 1, exercises.count)) of \(exercises.count)")
                        .font(.caption).foregroundStyle(Theme.secondaryInk)
                }
            }
            if position < exercises.count {
                RewireExerciseView(exercise: exercises[position]) { answers in
                    try? model.store.saveRewire(exercises[position], answers: answers)
                    if position + 1 < exercises.count { position += 1 } else { flow.advance() }
                }
                .id(exercises[position])
                if !flow.isRequired(.rewire) {
                    StepFooter(flow: flow, continueTitle: "Done for today", canContinue: true)
                }
            } else {
                StepFooter(flow: flow)
            }
        }
    }
}

struct RewireExerciseView: View {
    let exercise: RewireExercise
    let onDone: ([String: String]) -> Void

    var body: some View {
        switch exercise {
        case .gratitude: GratitudeExercise(onDone: onDone)
        case .implementationIntention: IntentionExercise(onDone: onDone)
        case .thoughtReframe: ReframeExercise(onDone: onDone)
        case .visualization: VisualizationExercise(onDone: onDone)
        }
    }
}

private struct ExerciseHeader: View {
    let title: String
    let why: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.display(30))
            Text(why).font(.callout).foregroundStyle(Theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func filled(_ values: [String]) -> Bool {
    values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct GratitudeExercise: View {
    let onDone: ([String: String]) -> Void
    @State private var items = Array(repeating: "", count: 3)
    @State private var whys = Array(repeating: "", count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ExerciseHeader(title: "Gratitude, specifically",
                           why: "Name three good things from the last day and why each happened. Regularly writing down specific things you’re thankful for has been linked in studies to small improvements in well-being; being specific, and noticing the cause, keeps it from becoming a rote list. “Every good gift and every perfect gift is from above.” (James 1:17)")
            ForEach(0..<3, id: \.self) { i in
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Something good, specifically…", text: $items[i]).textFieldStyle(.roundedBorder)
                        TextField("Why did it happen?", text: $whys[i]).textFieldStyle(.roundedBorder)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Save") {
                    var out: [String: String] = [:]
                    for i in 0..<3 { out["item\(i + 1)"] = items[i]; out["why\(i + 1)"] = whys[i] }
                    onDone(out)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!filled(items) || !filled(whys))
            }
        }
    }
}

struct IntentionExercise: View {
    let onDone: ([String: String]) -> Void
    @State private var goal = ""
    @State private var situation = ""
    @State private var action = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ExerciseHeader(title: "When–then plan",
                           why: "Pick one goal for today and decide in advance exactly when and how you’ll act on it. These “implementation intentions” (Gollwitzer, 1999) have been shown across many studies to make people more likely to follow through than a goal on its own.")
            TextField("Today’s goal (e.g. pray for my sister)", text: $goal).textFieldStyle(.roundedBorder)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("When").font(Theme.display(20)).frame(width: 70, alignment: .leading)
                        TextField("situation — e.g. I pour my first coffee", text: $situation).textFieldStyle(.roundedBorder) }
                    HStack { Text("I will").font(Theme.display(20)).frame(width: 70, alignment: .leading)
                        TextField("action — e.g. text her a short prayer", text: $action).textFieldStyle(.roundedBorder) }
                }
            }
            if filled([situation, action]) {
                Text("When \(situation), I will \(action).")
                    .font(.system(size: 17, design: .serif)).italic()
                    .foregroundStyle(Theme.accent)
            }
            HStack {
                Spacer()
                Button("Save") { onDone(["goal": goal, "when": situation, "then": action]) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!filled([situation, action]))
            }
        }
    }
}

struct ReframeExercise: View {
    let onDone: ([String: String]) -> Void
    @Environment(AppModel.self) private var model
    @State private var thought = ""
    @State private var evidenceFor = ""
    @State private var evidenceAgainst = ""
    @State private var reframe = ""
    @State private var verse = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ExerciseHeader(title: "Thought reframe",
                           why: "A cognitive-behavioral exercise: write down an anxious thought, weigh the evidence on both sides, then write a more accurate and truthful way to see it. Practicing this is a core part of CBT, which has good evidence for reducing anxiety. If a thought feels overwhelming or persistent, please also talk with someone you trust or a counselor.")
            labeled("The anxious thought", $thought, "e.g. I’m going to fail this presentation")
            HStack(alignment: .top, spacing: 14) {
                labeled("Evidence for it", $evidenceFor, "What actually supports it?")
                labeled("Evidence against it", $evidenceAgainst, "What doesn’t fit?")
            }
            labeled("A truer way to see it", $reframe, "e.g. I’ve prepared, and one talk doesn’t define me.")
            VStack(alignment: .leading, spacing: 6) {
                Text("Anchor it to a verse (optional)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondaryInk)
                HStack {
                    TextField("e.g. Philippians 4:6–7", text: $verse).textFieldStyle(.roundedBorder)
                    Menu("Suggestions") {
                        ForEach(Self.suggestions, id: \.self) { s in Button(s) { verse = s } }
                    }
                    .fixedSize()
                }
            }
            HStack {
                Spacer()
                Button("Save") {
                    onDone(["thought": thought, "for": evidenceFor, "against": evidenceAgainst, "reframe": reframe, "verse": verse])
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!filled([thought, reframe]))
            }
        }
    }

    static let suggestions = [
        "Philippians 4:6–7", "Isaiah 41:10", "Matthew 6:34", "1 Peter 5:7",
        "Psalm 56:3", "Joshua 1:9", "Romans 8:28", "2 Timothy 1:7",
    ]

    private func labeled(_ title: String, _ text: Binding<String>, _ placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondaryInk)
            ParchmentEditor(text: text, placeholder: placeholder, minHeight: 60)
        }
    }
}

struct VisualizationExercise: View {
    let onDone: ([String: String]) -> Void
    @State private var task = ""
    @State private var start: Date?
    @State private var note = ""
    private let seconds: Double = 60

    private let cues = [
        "Picture where you’ll be when you start.",
        "See the first small step. What do you do with your hands?",
        "Imagine the part where it gets hard. How do you keep going?",
        "Notice who is affected by doing it well.",
        "Picture finishing, and handing it to God.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ExerciseHeader(title: "Walk through the day",
                           why: "For about a minute, picture yourself doing today’s most important task well — the steps, not just the result. Research on mental simulation (e.g. Taylor et al., 1998) found that rehearsing the process tends to help planning and follow-through more than imagining only the outcome.")
            TextField("Today’s most important task", text: $task).textFieldStyle(.roundedBorder)
                .disabled(start != nil)

            if let start {
                TimelineView(.periodic(from: start, by: 1)) { ctx in
                    let elapsed = ctx.date.timeIntervalSince(start)
                    let i = min(cues.count - 1, Int(elapsed / (seconds / Double(cues.count))))
                    VStack(alignment: .leading, spacing: 16) {
                        ProgressView(value: min(1, elapsed / seconds))
                            .tint(Theme.accent)
                        Text(elapsed >= seconds ? "Open your eyes. What’s one thing you’ll do differently?" : cues[i])
                            .font(Theme.display(24))
                            .fixedSize(horizontal: false, vertical: true)
                            .animation(.easeInOut, value: i)
                        if elapsed >= seconds {
                            TextField("Optional note", text: $note).textFieldStyle(.roundedBorder)
                            HStack {
                                Spacer()
                                Button("Save") { onDone(["task": task, "note": note]) }.buttonStyle(PrimaryButtonStyle())
                            }
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Button("Begin (60 seconds)") { start = .now }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!filled([task]))
                }
            }
        }
    }
}
