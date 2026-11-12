import AnchorCore
import AppKit
import ServiceManagement
import SwiftUI

@main
struct AnchorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Anchor", systemImage: "book.closed") {
            MenuBarContent()
                .environment(delegate.model)
                .modelContainer(delegate.model.container)
        }
        .menuBarExtraStyle(.window)

        Window("Anchor", id: "dashboard") {
            DashboardView()
                .environment(delegate.model)
                .modelContainer(delegate.model.container)
        }
        .defaultSize(width: 1000, height: 720)

        Settings {
            SettingsView()
                .environment(delegate.model)
                .modelContainer(delegate.model.container)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var model = AppModel(container: AnchorSchema.makeContainer())

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Don't lock the screen while hosting unit tests.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        // Safe launch: holding Shift while Anchor starts skips today's gate (logged).
        if NSEvent.modifierFlags.contains(.shift) {
            model.gate.safeLaunchDay = DayKey(.now)
            model.store.logUnlock(kind: "safeLaunch", reason: "Shift held at launch")
        }

        // Keep the login item registered. Re-registering on every launch matters after
        // an update: replacing the app can leave macOS's login record pointing at the
        // old copy, and then Anchor silently stops opening at login.
        model.settingsStore.hasCompletedOnboarding = true
        if model.settings.launchAtLogin {
            do {
                try SMAppService.mainApp.register()
                model.gate.log("login item registered (status: \(Self.describe(SMAppService.mainApp.status)))")
            } catch {
                model.gate.log("login item: \(error.localizedDescription) (status: \(Self.describe(SMAppService.mainApp.status)))")
            }
        }

        model.gate.start()
        model.focus.start()
    }

    static func describe(_ s: SMAppService.Status) -> String {
        switch s {
        case .enabled: "enabled"
        case .requiresApproval: "needs approval in System Settings → General → Login Items"
        case .notRegistered: "not registered"
        case .notFound: "not found"
        @unknown default: "unknown"
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Quitting is blocked from the UI while the gate is enforced (there is no
        // menu), but logout, restart and shutdown must always work.
        .terminateNow
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = model.revision
        let summary = model.store.summary(settings: model.settings)
        let doneToday = model.store.completedDays().contains(DayKey(.now))
        let reading = model.todaysReading()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Anchor").font(Theme.display(20))
                Spacer()
                Label("\(summary.currentStreak)", systemImage: "flame").foregroundStyle(Theme.accent)
            }
            if doneToday {
                Label("Today’s session is complete", systemImage: "checkmark.circle").foregroundStyle(Theme.secondaryInk)
            } else {
                Text("Gate: \(GateController.describe(model.gate.currentDecision()).replacingOccurrences(of: "gate shown", with: "will show"))")
                    .font(.caption).foregroundStyle(Theme.secondaryInk)
                if let reading { Text("Today: \(DailyFlow.TodayReading.describe(reading.chapters))").font(.callout) }
                Button("Start today’s session") { model.gate.present(.voluntary) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Divider()
            Button("Dashboard") {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }
            SettingsLink { Text("Settings…") }
            Button("Quit Anchor") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(16)
        .frame(width: 280)
        .foregroundStyle(Theme.ink)
    }
}
