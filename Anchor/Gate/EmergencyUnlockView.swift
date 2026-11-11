import AnchorCore
import SwiftUI

/// The required escape hatch: hold for 30 seconds, then type the phrase.
/// Every use is logged and shown on the dashboard.
struct EmergencyUnlockView: View {
    let phrase: String
    let onCancel: () -> Void
    let onUnlock: (String?) -> Void

    @State private var pressStart: Date?
    @State private var held = false
    @State private var typed = ""
    @State private var reason = ""
    @FocusState private var phraseFocused: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                Text("Emergency unlock").font(Theme.display(26))
                Text("Anchor will never keep you out of your own Mac. To unlock for the rest of today, hold the button for \(Int(EmergencyUnlock.holdSeconds)) seconds, then type the phrase below. Each unlock is recorded in your log.")
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if !held {
                    holdButton
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Type: “\(phrase)”").font(.callout.weight(.medium))
                        TextField("", text: $typed, prompt: Text(phrase))
                            .textFieldStyle(.roundedBorder)
                            .focused($phraseFocused)
                            .onAppear { phraseFocused = true }
                        TextField("Reason (optional)", text: $reason)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack {
                    Button("Never mind") { onCancel() }.buttonStyle(QuietButtonStyle())
                    Spacer()
                    if held {
                        Button("Unlock for today") { onUnlock(reason.isEmpty ? nil : reason) }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!EmergencyUnlock.phraseMatches(typed, expected: phrase))
                    }
                }
            }
            .frame(width: 460)
        }
        .shadow(color: .black.opacity(0.15), radius: 30, y: 10)
    }

    private var holdButton: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: pressStart == nil)) { ctx in
            let elapsed = pressStart.map { ctx.date.timeIntervalSince($0) } ?? 0
            let progress = min(1, elapsed / EmergencyUnlock.holdSeconds)
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.hairline, lineWidth: 5)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(pressStart == nil ? "\(Int(EmergencyUnlock.holdSeconds))" : "\(max(0, Int(EmergencyUnlock.holdSeconds - elapsed.rounded(.down))))")
                        .font(.system(size: 15, weight: .medium)).monospacedDigit()
                }
                .frame(width: 56, height: 56)
                Text(pressStart == nil ? "Press and hold" : "Keep holding…")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
            }
            .padding(14)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .onLongPressGesture(minimumDuration: EmergencyUnlock.holdSeconds, maximumDistance: 60) {
            held = true
            pressStart = nil
        } onPressingChanged: { pressing in
            pressStart = pressing ? .now : nil
        }
        .accessibilityLabel("Press and hold for 30 seconds to begin an emergency unlock")
    }
}
