import AnchorCore
import SwiftUI

/// Dashboard → Challenges: the 30-Day Challenge and Bible in a Year.
struct ChallengesPanel: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEnd: Challenge.Kind?

    var body: some View {
        let _ = model.revision
        let active = model.challengeStatuses()

        VStack(alignment: .leading, spacing: 20) {
            PanelTitle(title: "Challenges", subtitle: "Something to aim for, one morning at a time.")

            ForEach(Challenge.Kind.allCases, id: \.self) { kind in
                if let item = active.first(where: { $0.challenge.kind == kind }) {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            ChallengeProgressRow(challenge: item.challenge, status: item.status)
                            MilestoneRow(kind: kind, reached: item.status.milestonesReached)
                            HStack {
                                Text("Started \(item.challenge.startedOn.date().formatted(date: .long, time: .omitted))")
                                    .font(.caption).foregroundStyle(Theme.secondaryInk)
                                Spacer()
                                if item.status.isFinished || item.status.isOver {
                                    Button("Start again") { model.startChallenge(kind) }
                                }
                                Button("End challenge") { confirmEnd = kind }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(Theme.secondaryInk)
                            }
                        }
                    }
                } else {
                    Card {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: kind == .thirtyDay ? "calendar.badge.checkmark" : "book.pages")
                                .font(.system(size: 28)).foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(kind.title).font(Theme.display(24))
                                Text(blurb(kind)).foregroundStyle(Theme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button("Start") { model.startChallenge(kind) }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }
        }
        .confirmationDialog("End this challenge?", isPresented: Binding(
            get: { confirmEnd != nil }, set: { if !$0 { confirmEnd = nil } })) {
            Button("End challenge", role: .destructive) {
                if let k = confirmEnd { model.endChallenge(k) }
                confirmEnd = nil
            }
        } message: {
            Text("Your sessions, readings and journal stay. Only the challenge’s progress tracking ends.")
        }
    }

    private func blurb(_ kind: Challenge.Kind) -> String {
        switch kind {
        case .thirtyDay:
            "Complete your morning session on 30 days, starting today. Badges at 7, 14, 21 and 30 days."
        case .bibleInAYear:
            "Read every verse of the Bible in 365 days, in a shuffled order: each day is a fresh mix of passages from across Scripture. Starting switches your reading plan to a new shuffle; you’ll see whether you’re on pace."
        }
    }
}

/// Title, progress bar and one-line status. Used on the dashboard and unlock card.
struct ChallengeProgressRow: View {
    let challenge: Challenge
    let status: ChallengeStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(challenge.kind.title, systemImage: status.isFinished ? "checkmark.seal.fill" : "flag")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(status.isFinished ? Theme.accent : Theme.ink)
                Spacer()
                Text("\(status.progress) / \(status.length)")
                    .font(.callout.monospacedDigit()).foregroundStyle(Theme.secondaryInk)
            }
            ProgressView(value: status.fraction).tint(Theme.accent)
            Text(ChallengeTracker.summary(challenge, status))
                .font(.caption).foregroundStyle(Theme.secondaryInk)
        }
    }
}

struct MilestoneRow: View {
    let kind: Challenge.Kind
    let reached: [Int]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(kind.milestones, id: \.self) { m in
                let got = reached.contains(m)
                VStack(spacing: 4) {
                    Image(systemName: got ? "rosette" : "circle.dashed")
                        .font(.system(size: 22))
                        .foregroundStyle(got ? Theme.accent : Theme.hairline)
                    Text(label(m)).font(.caption2).foregroundStyle(got ? Theme.ink : Theme.secondaryInk)
                }
                .frame(width: 64)
            }
        }
    }

    private func label(_ m: Int) -> String {
        switch m {
        case 182: "Halfway"
        case 365: "Whole Bible"
        default: "\(m) days"
        }
    }
}
