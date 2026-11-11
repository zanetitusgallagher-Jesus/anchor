import AnchorCore
import SwiftUI

struct UnlockStep: View {
    let flow: DailyFlow
    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = model.store.summary(settings: model.settings)
        let streak = streakIncludingToday()
        let minutesToday = Int(flow.readingSeconds / 60)

        VStack(spacing: 30) {
            Text("Go in peace.")
                .font(Theme.display(40))
                .padding(.top, 40)
            Text("Today’s time is kept. The rest of the day is yours.")
                .foregroundStyle(Theme.secondaryInk)

            Card {
                HStack(spacing: 0) {
                    stat("\(streak)", "day streak", "flame")
                    Divider().frame(height: 60)
                    stat("\(summary.totalMinutesInWord)", "minutes in the Word", "book")
                    Divider().frame(height: 60)
                    stat("\(summary.versesMemorized)", "verses memorized", "brain.head.profile")
                }
            }
            .frame(maxWidth: 620)

            if let reading = flow.reading {
                Text("Today: \(reading.title) · \(minutesToday) min")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryInk)
            }

            Button("Begin your day") { flow.controller.complete() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    /// The session isn't marked complete until "Begin your day", so count today here.
    private func streakIncludingToday() -> Int {
        var done = model.store.completedDays()
        done.insert(flow.today)
        let calc = StreakCalculator(scheduledWeekdays: model.settings.activeWeekdays)
        return calc.currentStreak(completed: done, today: flow.today)
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(Theme.accent)
            Text(value).font(Theme.display(34)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
    }
}
