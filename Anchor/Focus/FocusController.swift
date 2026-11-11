import AnchorCore
import AppKit
import SwiftUI

/// Focus hours: while they're in effect, apps on the user's list are hidden and
/// a calm "paused" screen is shown instead. This uses only public AppKit APIs —
/// Apple's Screen Time frameworks (FamilyControls / ManagedSettings) are not
/// available to native macOS apps. There is always a logged way through.
@MainActor
@Observable
final class FocusController {
    /// The app currently being held behind the shield.
    private(set) var pausedApp: BlockedApp?
    /// Temporary "allow for a few minutes" grants, by bundle ID.
    private(set) var allowances: [String: Date] = [:]

    @ObservationIgnored private unowned var model: AppModel
    @ObservationIgnored private var window: GateWindow?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var token: NSObjectProtocol?
    @ObservationIgnored private var pausedPID: pid_t?

    private let ownBundleID = Bundle.main.bundleIdentifier
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init(model: AppModel) {
        self.model = model
    }

    var isActiveNow: Bool { FocusPolicy.isActive(model.settings.focus, now: .now) }

    func start() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.check(app) }
        }
        // Backstop for apps that open windows without activating, and for the
        // moment focus hours begin while a listed app is already in front.
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(NSWorkspace.shared.frontmostApplication) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check(_ app: NSRunningApplication?) {
        // The morning gate already covers everything.
        if model.gate.isActive {
            closeShield()
            return
        }
        guard let app, app.processIdentifier != ownPID else { return }

        let now = Date()
        allowances = allowances.filter { $0.value > now }
        if FocusPolicy.shouldPause(bundleID: app.bundleIdentifier, schedule: model.settings.focus, now: now,
                                   ownBundleID: ownBundleID, allowances: allowances) {
            pause(app)
        } else if pausedApp != nil {
            // The user moved on to something allowed.
            closeShield()
        }
    }

    private func pause(_ app: NSRunningApplication) {
        let id = app.bundleIdentifier ?? ""
        let name = model.settings.focus.blockedApps.first { $0.bundleID == id }?.name ?? app.localizedName ?? "This app"
        pausedApp = BlockedApp(bundleID: id, name: name)
        pausedPID = app.processIdentifier
        app.hide()
        showShield()
    }

    private func showShield() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        if window == nil || window?.screen != screen {
            window?.orderOut(nil)
            let w = GateWindow(screen: screen)
            w.appearance = Theme.nsAppearance(model.settings.appearance)
            w.backgroundColor = NSColor(Theme.background)
            w.contentView = NSHostingView(rootView: FocusShieldView(controller: self)
                .environment(model)
                .preferredColorScheme(Theme.colorScheme(model.settings.appearance)))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func closeShield() {
        window?.orderOut(nil)
        pausedApp = nil
        pausedPID = nil
    }

    // MARK: Shield actions

    /// Keep the app hidden and get out of the way.
    func backToWork() {
        if let pid = pausedPID { NSRunningApplication(processIdentifier: pid)?.hide() }
        closeShield()
        // Hand focus to Finder so the paused app doesn't come straight back.
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
    }

    /// Let the paused app through for the configured number of minutes. Logged.
    func allowBriefly() {
        guard let app = pausedApp else { return }
        let minutes = max(1, model.settings.focus.allowanceMinutes)
        allowances[app.bundleID] = Date().addingTimeInterval(Double(minutes) * 60)
        model.store.logUnlock(kind: "focusOverride", reason: "\(app.name) allowed for \(minutes) min")
        model.touch()
        let pid = pausedPID
        closeShield()
        if let pid, let running = NSRunningApplication(processIdentifier: pid) {
            running.unhide()
            running.activate()
        }
    }
}

struct FocusShieldView: View {
    let controller: FocusController
    @Environment(AppModel.self) private var model
    @State private var pressStart: Date?
    private let holdSeconds: Double = 5

    var body: some View {
        let focus = model.settings.focus
        let until = FocusPolicy.endOfWindow(focus, now: .now)
        let app = controller.pausedApp

        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 26) {
                appIcon(app?.bundleID)
                    .frame(width: 72, height: 72)
                    .opacity(0.85)
                VStack(spacing: 8) {
                    Text("\(app?.name ?? "This app") is paused")
                        .font(Theme.display(36))
                    if let until {
                        Text("Focus hours until \(until.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                VStack(spacing: 6) {
                    Text("“Whatever you do, work heartily, as for the Lord, and not for men.”")
                        .font(.system(size: 18, design: .serif))
                        .multilineTextAlignment(.center)
                    Text("Colossians 3:23").font(.caption).foregroundStyle(Theme.secondaryInk)
                }
                .frame(maxWidth: 520)
                .padding(.top, 8)

                Button("Back to what matters") { controller.backToWork() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 10)

                holdToAllow(minutes: focus.allowanceMinutes)
            }
            .foregroundStyle(Theme.ink)
            .padding(40)
        }
    }

    @ViewBuilder private func appIcon(_ bundleID: String?) -> some View {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: "pause.circle").resizable().foregroundStyle(Theme.accent)
        }
    }

    private func holdToAllow(minutes: Int) -> some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: pressStart == nil)) { ctx in
            let elapsed = pressStart.map { ctx.date.timeIntervalSince($0) } ?? 0
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(Theme.hairline, lineWidth: 2)
                    Circle().trim(from: 0, to: min(1, elapsed / holdSeconds))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 16, height: 16)
                Text(pressStart == nil ? "Hold to allow for \(minutes) minutes" : "Keep holding…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryInk)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .onLongPressGesture(minimumDuration: holdSeconds, maximumDistance: 40) {
            pressStart = nil
            controller.allowBriefly()
        } onPressingChanged: { pressing in
            pressStart = pressing ? .now : nil
        }
        .help("Allowances are recorded in the unlock log.")
    }
}
