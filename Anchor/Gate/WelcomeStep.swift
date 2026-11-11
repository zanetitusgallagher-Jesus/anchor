import AnchorCore
import SwiftUI

struct WelcomeStep: View {
    let flow: DailyFlow
    @Environment(AppModel.self) private var model
    @State private var started = Date()
    @State private var minutes: Double = -1

    var body: some View {
        let settings = model.settings
        let summary = model.store.summary(settings: settings)
        let centering = CenteringPrompt.forDay(flow.today)

        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.secondaryInk)
                    .textCase(.uppercase)
                    .tracking(1.5)
                if summary.currentStreak > 0 {
                    Label("\(summary.currentStreak)-day streak", systemImage: "flame")
                        .font(.callout)
                        .foregroundStyle(Theme.accent)
                }
                ForEach(model.challengeStatuses(), id: \.challenge.id) { item in
                    Label(ChallengeTracker.summary(item.challenge, item.status), systemImage: "flag")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }

            VStack(spacing: 10) {
                Text(centering.text)
                    .font(Theme.display(34))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(centering.reference)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(Theme.secondaryInk)
            }
            .padding(.top, 20)

            timePicker
                .padding(.top, 8)

            if settings.breathingEnabled {
                BreathingView(totalSeconds: Double(settings.breathingSeconds))
                    .frame(height: 300)
                breathingButtons(settings)
            } else {
                Button("Begin") { begin() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            if minutes < 0 {
                let r = flow.minutesRange
                minutes = Double(min(r.upperBound, max(r.lowerBound, settings.sessionMinutes)))
            }
        }
    }

    private var chosenMinutes: Int {
        let r = flow.minutesRange
        let value = minutes < 0 ? model.settings.sessionMinutes : Int(minutes.rounded())
        return min(r.upperBound, max(r.lowerBound, value))
    }

    private func begin() { flow.begin(minutes: chosenMinutes) }

    /// "How much time do you have today?" — 2 to 15 minutes.
    private var timePicker: some View {
        let range = flow.minutesRange
        let preview = flow.preview(minutes: chosenMinutes)
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("How much time do you have today?")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Text("\(chosenMinutes) min")
                        .font(Theme.display(28))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: chosenMinutes)
                }
                Slider(value: $minutes, in: Double(range.lowerBound)...Double(range.upperBound), step: 1) {
                    Text("Session length")
                } minimumValueLabel: {
                    Text("\(range.lowerBound) min").font(.caption).foregroundStyle(Theme.secondaryInk)
                } maximumValueLabel: {
                    Text("\(range.upperBound) min").font(.caption).foregroundStyle(Theme.secondaryInk)
                }
                .tint(Theme.accent)
                .accessibilityValue("\(chosenMinutes) minutes")

                Text(describe(preview))
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                planNote

            }
        }
        .frame(maxWidth: 560)
    }

    /// Explains which plan today's choice reads from, and nudges toward the main plan.
    @ViewBuilder private var planNote: some View {
        if let main = flow.mainReading, let short = flow.shortReading {
            let goal = flow.mainPlanMinimum
            if flow.choice(minutes: chosenMinutes) == .short {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Short on time? Today will be **Verse a Day** (\(short.title)), so your day still counts.",
                          systemImage: "clock.badge.exclamationmark")
                    Text("Your \(main.plan.name) reading (\(main.title)) will be waiting for you. **\(goal)+ minutes keeps you on \(main.plan.name). That’s the goal.**")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Use \(goal) minutes") { minutes = Double(goal) }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Label("\(main.plan.name): \(main.title), about \(flow.readingWords.formatted()) words. Under \(goal) minutes switches today to Verse a Day.",
                      systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let main = flow.mainReading, flow.requiredReadingMinutes > 1 {
            Text("Today’s reading (\(main.title)) is about \(flow.readingWords.formatted()) words, roughly \(flow.requiredReadingMinutes) minutes, so today’s session is at least \(flow.minutesRange.lowerBound) minutes.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryInk.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func describe(_ p: SessionPlan) -> String {
        var parts: [String] = []
        for step in p.steps {
            switch step {
            case .scripture: parts.append("Read \(p.readingMinutes) min")
            case .reflection: parts.append("Reflect")
            case .memory: parts.append("Memory verse")
            case .journal: parts.append("Journal")
            case .rewire: parts.append(p.rewireCount > 1 ? "\(p.rewireCount) Rewire exercises" : "Rewire")
            case .welcome, .unlock: break
            }
        }
        return parts.joined(separator: "  ·  ")
    }

    private func breathingButtons(_ settings: AnchorSettings) -> some View {
            TimelineView(.periodic(from: started, by: 1)) { ctx in
                let elapsed = ctx.date.timeIntervalSince(started)
                let canSkip = elapsed >= Double(settings.breathingSkippableAfterSeconds)
                let finished = elapsed >= Double(settings.breathingSeconds)
                HStack {
                    Spacer()
                    if finished {
                        Button("Begin") { begin() }
                            .buttonStyle(PrimaryButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    } else if canSkip {
                        Button("Continue") { begin() }.buttonStyle(QuietButtonStyle())
                    } else {
                        Text(" ").font(.callout)
                    }
                    Spacer()
                }
            }
    }
}

/// Box breathing (4-4-4-4) guide: a circle that grows, holds, shrinks, holds.
struct BreathingView: View {
    let totalSeconds: Double
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { ctx in
            let elapsed = ctx.date.timeIntervalSince(start)
            let done = elapsed >= totalSeconds
            let phase = BoxBreathing.phase(at: elapsed)
            let scale = done ? 0.5 : BoxBreathing.scale(at: elapsed)
            let eased = 0.5 - cos(scale * .pi) / 2

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.08))
                        .frame(width: 240, height: 240)
                    Circle()
                        .fill(Theme.accent.opacity(0.22))
                        .frame(width: 90 + 150 * eased, height: 90 + 150 * eased)
                    Circle()
                        .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
                        .frame(width: 240, height: 240)
                }
                Text(done ? "Well done." : phase.phase.rawValue.trimmingCharacters(in: .whitespaces))
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.secondaryInk)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: phase.phase.rawValue)
                Text(done ? " " : "\(Int(max(0, totalSeconds - elapsed)))s")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(Theme.secondaryInk.opacity(0.7))
            }
        }
        .accessibilityLabel("Box breathing: four seconds in, hold four, four out, hold four.")
    }
}
