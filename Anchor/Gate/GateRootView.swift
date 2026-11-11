import AnchorCore
import SwiftUI

/// Everything shown on the primary display while the gate is up.
struct GateRootView: View {
    @Bindable var flow: DailyFlow
    let controller: GateController
    @Environment(AppModel.self) private var model
    @State private var showEmergency = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    step
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 32)
                        .id(flow.current)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .scrollIndicators(.never)
            }
            .animation(.easeInOut(duration: 0.45), value: flow.current)

            if showEmergency {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { showEmergency = false }
                EmergencyUnlockView(phrase: model.settings.unlockPhrase,
                                    onCancel: { showEmergency = false },
                                    onUnlock: { reason in controller.emergencyUnlock(reason: reason) })
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .foregroundStyle(Theme.ink)
        .animation(.easeOut(duration: 0.2), value: showEmergency)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("Anchor")
                .font(Theme.display(17))
                .foregroundStyle(Theme.secondaryInk)
            Spacer()
            StepDots(steps: flow.steps, index: flow.steps.firstIndex(of: flow.current) ?? 0)
            Spacer()
            if controller.mode == .voluntary {
                Button("Close") { controller.close() }.buttonStyle(QuietButtonStyle())
            } else {
                Button("Emergency unlock") { showEmergency = true }.buttonStyle(QuietButtonStyle())
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var step: some View {
        switch flow.current {
        case .welcome: WelcomeStep(flow: flow)
        case .scripture: ScriptureStep(flow: flow)
        case .reflection: ReflectionStep(flow: flow)
        case .memory: MemoryStep(flow: flow)
        case .journal: JournalStep(flow: flow)
        case .rewire: RewireStep(flow: flow)
        case .unlock: UnlockStep(flow: flow)
        }
    }
}

struct StepDots: View {
    let steps: [GateStep]
    let index: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                Capsule()
                    .fill(i <= index ? Theme.accent : Theme.hairline)
                    .frame(width: i == index ? 22 : 8, height: 8)
                    .help(s.title)
            }
        }
        .animation(.easeInOut, value: index)
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(steps.count)")
    }
}

/// Shown on secondary displays.
struct GateCoverView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.system(size: 30, weight: .light))
                Text("Be still.")
                    .font(Theme.display(28))
            }
            .foregroundStyle(Theme.secondaryInk)
        }
    }
}

/// Bottom row used by most steps: optional Skip on the left, Continue on the right.
struct StepFooter: View {
    let flow: DailyFlow
    var continueTitle = "Continue"
    var canContinue = true
    var hint: String?
    var onContinue: (() -> Void)?

    var body: some View {
        HStack {
            if !flow.isRequired(flow.current) && flow.current != .welcome && flow.current != .unlock {
                Button("Skip for today") { flow.skip() }.buttonStyle(QuietButtonStyle())
            }
            Spacer()
            if let hint {
                Text(hint).font(.callout).foregroundStyle(Theme.secondaryInk).monospacedDigit()
            }
            Button(continueTitle) {
                if let onContinue { onContinue() } else { flow.advance() }
            }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 12)
    }
}
