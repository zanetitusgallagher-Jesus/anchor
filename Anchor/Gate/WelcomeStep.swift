import AnchorCore
import SwiftUI

struct WelcomeStep: View {
    let flow: DailyFlow
    @Environment(AppModel.self) private var model
    @State private var started = Date()

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

            BreathingView(totalSeconds: Double(settings.breathingSeconds))
                .frame(height: 300)

            TimelineView(.periodic(from: started, by: 1)) { ctx in
                let elapsed = ctx.date.timeIntervalSince(started)
                let canSkip = elapsed >= Double(settings.breathingSkippableAfterSeconds)
                let finished = elapsed >= Double(settings.breathingSeconds)
                HStack {
                    Spacer()
                    if finished {
                        Button("Begin") { flow.advance() }
                            .buttonStyle(PrimaryButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    } else if canSkip {
                        Button("Continue") { flow.advance() }.buttonStyle(QuietButtonStyle())
                    } else {
                        Text(" ").font(.callout)
                    }
                    Spacer()
                }
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
