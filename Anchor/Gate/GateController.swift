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
            observe(ws, name) { [weak self] _ in self?.evaluate() }
        }
        observe(nc, NSApplication.didResignActiveNotification) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                self?.reassert()
            }
        }
        observe(nc, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in self?.rebuildWindows() }
        observe(nc, .NSCalendarDayChanged) { [weak self] _ in self?.evaluate() }

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        evaluate()
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
            if mode == .enforced {
                if !NSApp.isActive { reassert() }
                if let shownAt, GatePolicy.failsafeExpired(gateShownAt: shownAt, now: now, settings: model.settings) {
                    model.store.logUnlock(kind: "failsafe", reason: "Gate open for \(model.settings.failsafeMinutes) minutes")
                    dismiss()
                }
            }
        } else if now.timeIntervalSince(lastEvaluation) >= 60 {
            evaluate()
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

    func evaluate() {
        let now = Date()
        lastEvaluation = now
        guard !isActive else { return }
        let decision = currentDecision(now: now)
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
        isActive = false
        flow = nil
        shownAt = nil
        NSApp.presentationOptions = []
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}
