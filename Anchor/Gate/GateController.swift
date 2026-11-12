import AnchorCore
import AppKit
import SwiftUI

/// Owns the full-screen gate: decides when it should appear, keeps it in front
/// until today's session is complete, and always leaves the user a way out
/// (emergency unlock, Shift at launch, failsafe timeout).
@MainActor
@Observable
final class GateController {
    enum Mode { case enforced, voluntary }

    private(set) var isActive = false
    private(set) var mode: Mode = .enforced
    private(set) var flow: DailyFlow?
    private(set) var shownAt: Date?
    /// Set when the user held Shift at launch: no gate until tomorrow.
    var safeLaunchDay: DayKey?

    @ObservationIgnored private unowned var model: AppModel
    @ObservationIgnored private var windows: [GateWindow] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var lastEvaluation = Date.distantPast
    @ObservationIgnored private var lastRepair = Date.distantPast
    /// The most recent decision, for the menu bar and dashboard.
    private(set) var lastDecision: GateDecision?

    // MARK: Diagnostics log (last 40 entries, kept across launches)

    private static let logKey = "anchor.gateLog"

    var logEntries: [String] { UserDefaults.standard.stringArray(forKey: Self.logKey) ?? [] }

    func log(_ message: String) {
        let stamp = Date.now.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
        var entries = logEntries
        entries.insert("\(stamp) — \(message)", at: 0)
        UserDefaults.standard.set(Array(entries.prefix(40)), forKey: Self.logKey)
    }

    static func describe(_ d: GateDecision) -> String {
        switch d {
        case .show: "gate shown"
        case .hidden(.disabled): "no gate: turned off in Settings"
        case .hidden(.notScheduledToday): "no gate: today isn't a scheduled day"
        case .hidden(.completedToday): "no gate: today's session is done"
        case .hidden(.emergencyUnlockedToday): "no gate: emergency-unlocked today"
        case .hidden(.outsideGraceWindow): "no gate: past today's cutoff time"
        case .hidden(.safeLaunch): "no gate: Shift held at launch"
        }
    }

    static let lockdownOptions: NSApplication.PresentationOptions = [
        .hideDock, .hideMenuBar, .disableProcessSwitching, .disableForceQuit, .disableHideApplication,
    ]

    init(model: AppModel) {
        self.model = model
    }

    // MARK: Lifecycle

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        observe(ws, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.reassert() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(ws, name) { [weak self] _ in self?.evaluate(trigger: "wake / session") }
        }
        observe(nc, NSApplication.didResignActiveNotification) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                self?.reassert()
            }
        }
        observe(nc, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in self?.rebuildWindows() }
        observe(nc, .NSCalendarDayChanged) { [weak self] _ in self?.evaluate(trigger: "new day") }
        // Unlocking the screen (password / Touch ID) — no wake notification is sent for this.
        let dnc = DistributedNotificationCenter.default()
        let unlock = dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate(trigger: "screen unlocked")
                self?.reassert()
            }
        }
        observers.append((dnc, unlock))

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        evaluate(trigger: "launch")
        // At login macOS can start Anchor before the displays and window server are
        // fully ready. Check again a few times so the gate can't be missed.
        for delay in [2.0, 6.0, 15.0, 45.0] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.evaluate(trigger: "launch +\(Int(delay))s")
            }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping @MainActor (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { block(note) }
        }
        observers.append((center, token))
    }

    private func tick() {
        let now = Date()
        if isActive {
            // Repair the gate if its windows are missing (e.g. created before the
            // displays were ready at login) or have been hidden.
            let screens = NSScreen.screens.count
            if screens > 0, now.timeIntervalSince(lastRepair) >= 5,
               windows.count != screens || windows.allSatisfy({ !$0.isVisible }) {
                lastRepair = now
                log("repairing gate windows (\(windows.count) for \(screens) screen(s))")
                rebuildWindows()
                reassert()
            }
            if mode == .enforced {
                if !NSApp.isActive { reassert() }
                if let shownAt, GatePolicy.failsafeExpired(gateShownAt: shownAt, now: now, settings: model.settings) {
                    model.store.logUnlock(kind: "failsafe", reason: "Gate open for \(model.settings.failsafeMinutes) minutes")
                    dismiss()
                }
            }
        } else if now.timeIntervalSince(lastEvaluation) >= 30 {
            evaluate(trigger: nil)
        }
    }

    // MARK: Decision

    func currentDecision(now: Date = .now) -> GateDecision {
        let store = model.store
        let today = DayKey(now)
        let ctx = GateContext(now: now,
                              completedDays: store.completedDays(),
                              emergencyUnlockedDays: store.unlockedDays(),
                              firstCheckToday: model.settingsStore.firstCheck(today: today),
                              safeLaunch: safeLaunchDay == today)
        return GatePolicy.evaluate(ctx, settings: model.settings)
    }

    /// - Parameter trigger: why this check ran; logged unless nil (the periodic check
    ///   is only logged when it changes something).
    func evaluate(trigger: String? = "check") {
        let now = Date()
        lastEvaluation = now
        guard !isActive else { return }
        let decision = currentDecision(now: now)
        lastDecision = decision
        if let trigger { log("\(trigger): \(Self.describe(decision))") }
        else if decision.shouldShow { log("periodic check: \(Self.describe(decision))") }
        // Remember the first check of the day only while the gate could still apply,
        // so the grace window is judged from the moment the Mac was first used.
        if decision.shouldShow { model.settingsStore.recordCheck(now) }
        if decision.shouldShow { present(.enforced) }
    }

    // MARK: Presenting

    func present(_ mode: Mode) {
        if isActive {
            if mode == .enforced { self.mode = .enforced }
            reassert()
            return
        }
        self.mode = mode
        log(mode == .enforced ? "presenting gate on \(NSScreen.screens.count) screen(s)" : "session started from the menu bar")
        flow = DailyFlow(model: model, controller: self)
        shownAt = .now
        isActive = true
        _ = model.store.session(for: DayKey(.now))
        rebuildWindows()
        reassert()
    }

    private func rebuildWindows() {
        guard isActive, let flow else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let appearance = Theme.nsAppearance(model.settings.appearance)
        let screens = NSScreen.screens
        let primary = NSScreen.main ?? screens.first
        for screen in screens {
            let w = GateWindow(screen: screen)
            w.appearance = appearance
            w.backgroundColor = NSColor(Theme.background)
            let root: AnyView
            if screen == primary {
                root = AnyView(GateRootView(flow: flow, controller: self))
            } else {
                root = AnyView(GateCoverView())
            }
            w.contentView = NSHostingView(rootView: root
                .environment(model)
                .modelContainer(model.container)
                .preferredColorScheme(Theme.colorScheme(model.settings.appearance)))
            windows.append(w)
            w.orderFrontRegardless()
        }
        windows.first { $0.screen == primary }?.makeKeyAndOrderFront(nil)
    }

    /// Brings the gate back to the front after an app switch, wake or display change.
    func reassert() {
        guard isActive else { return }
        if mode == .enforced {
            NSApp.activate(ignoringOtherApps: true)
            // Some options are only accepted while the app is active.
            if NSApp.isActive { NSApp.presentationOptions = Self.lockdownOptions }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        if windows.isEmpty || windows.count != NSScreen.screens.count {
            rebuildWindows()
        } else {
            windows.forEach { $0.orderFrontRegardless() }
            windows.first?.makeKey()
        }
    }

    // MARK: Leaving

    /// The day's session is finished.
    func complete() {
        let store = model.store
        if let s = store.session(for: DayKey(.now)) {
            s.completedAt = .now
            store.save()
        }
        model.touch()
        dismiss()
    }

    func emergencyUnlock(reason: String?) {
        model.store.logUnlock(kind: "emergency", reason: reason)
        model.touch()
        dismiss()
    }

    /// Closing a session the user opened voluntarily.
    func close() {
        guard mode == .voluntary else { return }
        dismiss()
    }

    private func dismiss() {
        model.listen.stop()
        isActive = false
        flow = nil
        shownAt = nil
        NSApp.presentationOptions = []
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}
