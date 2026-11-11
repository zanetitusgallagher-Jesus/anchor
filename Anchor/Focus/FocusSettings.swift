import AnchorCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Focus: which apps to pause, and when.
struct FocusSettings: View {
    @Environment(AppModel.self) private var model
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    var body: some View {
        let focus = model.settings.focus
        Form {
            Toggle("Pause chosen apps during focus hours", isOn: binding(\.enabled))
            Text("When you open a paused app during these hours, Anchor hides it and shows a short reminder. You can hold a button to allow it for \(focus.allowanceMinutes) minutes, and that’s logged.")
                .font(.caption).foregroundStyle(.secondary)

            Section("Hours") {
                DatePicker("From", selection: timeBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: timeBinding(\.endMinutes), displayedComponents: .hourAndMinute)
                if focus.endMinutes < focus.startMinutes {
                    Text("Runs past midnight into the next morning.").font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Days") {
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { d in
                            let on = focus.weekdays.contains(d)
                            Button(weekdaySymbols[d - 1]) {
                                if on { model.settings.focus.weekdays.remove(d) } else { model.settings.focus.weekdays.insert(d) }
                            }
                            .buttonStyle(.bordered)
                            .tint(on ? Theme.accent : nil)
                        }
                    }
                }
                Stepper("Allow briefly: \(focus.allowanceMinutes) min", value: binding(\.allowanceMinutes), in: 1...30)
            }

            Section("Paused apps") {
                if focus.blockedApps.isEmpty {
                    Text("No apps yet.").foregroundStyle(.secondary)
                }
                ForEach(focus.blockedApps) { app in
                    HStack {
                        icon(app.bundleID).frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                        Button {
                            model.settings.focus.blockedApps.removeAll { $0.bundleID == app.bundleID }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
                HStack {
                    Menu("Add a running app") {
                        ForEach(runningCandidates(), id: \.bundleID) { app in
                            Button(app.name) { add(app) }
                        }
                    }
                    .fixedSize()
                    Button("Choose from Applications…", action: chooseApps)
                }
                Text("Finder, System Settings, Terminal and Activity Monitor are never paused, so your Mac always stays usable.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("About this feature") {
                Text("Apple’s Screen Time frameworks (Family Controls) aren’t available to Mac apps, so Anchor pauses apps itself. It can’t block websites, and it can’t stop an app that’s already doing something in the background — it keeps the app out of sight while you focus.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ kp: WritableKeyPath<FocusSchedule, T>) -> Binding<T> {
        Binding(get: { model.settings.focus[keyPath: kp] }, set: { model.settings.focus[keyPath: kp] = $0 })
    }

    /// Minutes-after-midnight <-> Date for DatePicker.
    private func timeBinding(_ kp: WritableKeyPath<FocusSchedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = model.settings.focus[keyPath: kp]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                model.settings.focus[keyPath: kp] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    @ViewBuilder private func icon(_ bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: "app")
        }
    }

    private func add(_ app: BlockedApp) {
        guard !FocusPolicy.neverBlock.contains(app.bundleID),
              !model.settings.focus.blockedApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        model.settings.focus.blockedApps.append(app)
        model.settings.focus.blockedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func runningCandidates() -> [BlockedApp] {
        let own = Bundle.main.bundleIdentifier
        let listed = Set(model.settings.focus.blockedApps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> BlockedApp? in
                guard let id = app.bundleIdentifier, id != own, !listed.contains(id),
                      !FocusPolicy.neverBlock.contains(id) else { return nil }
                return BlockedApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Pause during focus hours"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            add(BlockedApp(bundleID: id, name: name))
        }
    }
}
