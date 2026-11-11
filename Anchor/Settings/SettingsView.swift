import AnchorCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GateSettings().tabItem { Label("Gate", systemImage: "lock") }
            FlowSettings().tabItem { Label("Daily flow", systemImage: "list.number") }
            ScriptureSettings().tabItem { Label("Scripture", systemImage: "book") }
            AISettings().tabItem { Label("AI", systemImage: "sparkles") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 560)
        .padding(20)
        .preferredColorScheme(Theme.colorScheme(model.settings.appearance))
    }
}

/// Binding helper: `bind(\.gateEnabled)`.
@MainActor
private func bind<T>(_ model: AppModel, _ kp: WritableKeyPath<AnchorSettings, T>) -> Binding<T> {
    Binding(get: { model.settings[keyPath: kp] }, set: { model.settings[keyPath: kp] = $0 })
}

struct GateSettings: View {
    @Environment(AppModel.self) private var model
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    var body: some View {
        Form {
            Toggle("Show the gate each morning", isOn: bind(model, \.gateEnabled))
            LabeledContent("Days") {
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { d in
                        let on = model.settings.activeWeekdays.contains(d)
                        Button(weekdaySymbols[d - 1]) {
                            if on { model.settings.activeWeekdays.remove(d) } else { model.settings.activeWeekdays.insert(d) }
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? Theme.accent : nil)
                    }
                }
            }
            Picker("Only before", selection: bind(model, \.graceCutoffHour)) {
                ForEach(5...23, id: \.self) { h in
                    Text(DateComponents(calendar: .current, hour: h).date.map { $0.formatted(date: .omitted, time: .shortened) } ?? "\(h):00").tag(h)
                }
                Text("Any time of day").tag(24)
            }
            Text("If you first use your Mac after this time, the gate won’t appear that day. You can still start the session from the menu bar.")
                .font(.caption).foregroundStyle(.secondary)

            Section("Safety") {
                TextField("Emergency unlock phrase", text: bind(model, \.unlockPhrase))
                Stepper("Failsafe: release after \(model.settings.failsafeMinutes) min", value: bind(model, \.failsafeMinutes), in: 30...240, step: 15)
                Text("The gate can always be opened with Emergency unlock (hold 30 seconds, then type the phrase), or skipped for the day by holding Shift while Anchor launches. Every use is logged.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Open Anchor at login", isOn: Binding(
                    get: { loginStatus == .enabled },
                    set: { setLogin($0) }))
                if loginStatus == .requiresApproval {
                    Text("Approve Anchor in System Settings → General → Login Items.").font(.caption)
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }

    private func setLogin(_ on: Bool) {
        loginError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            model.settings.launchAtLogin = on
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
    }
}

struct FlowSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Steps") {
                ForEach(GateStep.configurable) { step in
                    HStack {
                        Text(step.title)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { state(step) },
                            set: { setState(step, $0) })) {
                            Text("Required").tag(0)
                            Text("Optional").tag(1)
                            Text("Off").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                }
                Text("Memory review only appears on days a verse is due.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Timing") {
                Stepper("Minimum reading time: \(model.settings.minimumReadingMinutes) min", value: bind(model, \.minimumReadingMinutes), in: 1...30)
                Stepper("Breathing: \(model.settings.breathingSeconds) s", value: bind(model, \.breathingSeconds), in: 15...180, step: 15)
            }
            Section("Rewire") {
                ForEach(RewireExercise.allCases) { ex in
                    Toggle(ex.title, isOn: Binding(
                        get: { model.settings.enabledRewire.contains(ex) },
                        set: { on in
                            if on { model.settings.enabledRewire.insert(ex) } else { model.settings.enabledRewire.remove(ex) }
                        }))
                }
                Picker("Exercises per day", selection: bind(model, \.rewirePerDay)) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                }
                .pickerStyle(.segmented)
                Text("The whole session is designed to stay under 15 minutes.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Theme", selection: bind(model, \.appearance)) {
                    Text("Match system").tag(AppearancePreference.system)
                    Text("Parchment").tag(AppearancePreference.light)
                    Text("Dark").tag(AppearancePreference.dark)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func state(_ s: GateStep) -> Int {
        model.settings.disabledSteps.contains(s) ? 2 : model.settings.optionalSteps.contains(s) ? 1 : 0
    }

    private func setState(_ s: GateStep, _ v: Int) {
        model.settings.disabledSteps.remove(s)
        model.settings.optionalSteps.remove(s)
        if v == 1 { model.settings.optionalSteps.insert(s) }
        if v == 2 { model.settings.disabledSteps.insert(s) }
    }
}

struct ScriptureSettings: View {
    @Environment(AppModel.self) private var model
    @State private var apiKey = Keychain.string(.apiBibleKey) ?? ""
    @State private var bibles: [APIBibleClient.BibleSummary] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        Form {
            Picker("Reading plan", selection: bind(model, \.planID)) {
                ForEach(model.plans.seedPlans) { Text($0.name).tag($0.id) }
                ForEach(model.customPlans()) { Text($0.name).tag($0.planID) }
            }
            Text("Create custom plans from the dashboard’s Reading plan page.").font(.caption).foregroundStyle(.secondary)

            Picker("Translation", selection: bind(model, \.translationID)) {
                ForEach(BibleStore.bundled, id: \.id) { Text("\($0.id) — \($0.name)").tag($0.id) }
                if model.settings.apiBibleID != nil { Text(model.settings.apiBibleName ?? "API.Bible").tag("API") }
            }
            Picker("Typeface", selection: bind(model, \.scriptureFont)) {
                ForEach(ScriptureFont.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Slider(value: bind(model, \.scriptureFontSize), in: 14...40, step: 1) {
                Text("Text size")
            }
            Text("The quick brown fox — “Be still, and know that I am God.”")
                .font(Theme.scripture(model.settings))

            Section("API.Bible (optional)") {
                Text("Use your own free API.Bible key to read licensed translations such as NIV or NLT. Which ones appear depends on your key. Your key is stored in the Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("API key", text: $apiKey)
                HStack {
                    Button("Save key & load translations") { Task { await load() } }
                        .disabled(apiKey.isEmpty || loading)
                    if loading { ProgressView().controlSize(.small) }
                }
                if !bibles.isEmpty {
                    Picker("API translation", selection: Binding(
                        get: { model.settings.apiBibleID ?? "" },
                        set: { id in
                            model.settings.apiBibleID = id.isEmpty ? nil : id
                            model.settings.apiBibleName = bibles.first { $0.id == id }?.abbreviationLocal ?? bibles.first { $0.id == id }?.name
                            if !id.isEmpty { model.settings.translationID = "API" }
                        })) {
                        Text("None").tag("")
                        ForEach(bibles) { Text($0.label).tag($0.id) }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }

    private func load() async {
        Keychain.setString(apiKey, for: .apiBibleKey)
        loading = true
        error = nil
        defer { loading = false }
        do { bibles = try await APIBibleClient(key: apiKey).bibles() }
        catch { self.error = error.localizedDescription }
    }
}

struct AISettings: View {
    @Environment(AppModel.self) private var model
    @State private var key = Keychain.string(.claudeKey) ?? ""
    @State private var saved = false

    var body: some View {
        Form {
            Toggle("AI reflection questions", isOn: bind(model, \.aiReflectionEnabled))
            Text("Off by default. When on, the Reflection step can ask Claude for 2–3 questions about today’s passage and give gentle feedback on your answers. It only runs when you press “Ask”.")
                .font(.caption).foregroundStyle(.secondary)
            Section("What gets sent") {
                Label("Today’s passage reference and text", systemImage: "book")
                Label("If you ask for feedback: the questions and your answers", systemImage: "text.bubble")
                Label("Never: your journal, prayers, memory verses, reflections or anything else", systemImage: "lock")
                Text("Requests go directly from your Mac to api.anthropic.com with your own key, and are subject to Anthropic’s terms and privacy policy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Anthropic API key") {
                SecureField("sk-ant-…", text: $key)
                HStack {
                    Button("Save to Keychain") {
                        Keychain.setString(key, for: .claudeKey)
                        saved = true
                    }
                    Button("Remove") {
                        Keychain.setString(nil, for: .claudeKey)
                        key = ""
                    }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.secondary) }
                }
                TextField("Model", text: bind(model, \.aiModel))
            }
        }
        .formStyle(.grouped)
    }
}

struct PrivacySettings: View {
    var body: some View {
        Form {
            Label("Everything stays on this Mac. Anchor has no analytics and no account.", systemImage: "internaldrive")
            Label("Journal entries, prayers, reflections and Rewire answers are encrypted with AES-256-GCM. The key lives only in your Keychain.", systemImage: "lock.shield")
            Label("Network is used only for the optional API.Bible and AI features, and only with your own keys.", systemImage: "network")
            Text("Exports (Markdown/PDF) are not encrypted.").font(.caption).foregroundStyle(.secondary)
            Section("Scripture") {
                Text("King James Version (1769) and World English Bible are in the public domain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
