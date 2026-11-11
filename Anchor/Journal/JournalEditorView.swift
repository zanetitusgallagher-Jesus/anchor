import AnchorCore
import SwiftUI

/// Gate step wrapper around the journal editor.
struct JournalStep: View {
    let flow: DailyFlow
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Journal").font(.callout).foregroundStyle(Theme.secondaryInk).textCase(.uppercase).tracking(1.2)
            JournalEditorView(passage: flow.reading?.title, bookID: flow.reading?.chapters.first?.bookID,
                              saveTitle: "Save & continue") { _ in
                saved = true
                flow.advance()
            }
            if !saved {
                StepFooter(flow: flow, canContinue: !flow.isRequired(.journal), hint: flow.isRequired(.journal) ? "Save an entry to continue" : nil)
            }
        }
    }
}

struct JournalEditorView: View {
    var passage: String?
    var bookID: String?
    var existing: JournalEntry?
    var saveTitle = "Save"
    var onSaved: (JournalEntry) -> Void

    @Environment(AppModel.self) private var model
    @State private var template: JournalTemplate = .soap
    @State private var fields: [JournalField: String] = [:]
    @State private var rtf = Data()
    @State private var plain = ""
    @State private var tagsText = ""
    @State private var mood: Int?
    @State private var error: String?
    @State private var loaded = false
    @State private var richController = RichTextController()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Template", selection: $template) {
                ForEach(JournalTemplate.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let passage {
                Label(passage, systemImage: "book").font(.callout).foregroundStyle(Theme.secondaryInk)
            }

            Group {
                switch template {
                case .soap:
                    ForEach(template.fields, id: \.self) { f in fieldEditor(f) }
                case .gratitude:
                    Text("Three specific things you're grateful for today.")
                        .font(.callout).foregroundStyle(Theme.secondaryInk)
                    ForEach(template.fields, id: \.self) { f in
                        HStack(alignment: .top) {
                            Text(f.title).font(Theme.display(18)).frame(width: 22)
                            ParchmentEditor(text: binding(f), placeholder: f.placeholder, minHeight: 44)
                        }
                    }
                case .prayer:
                    PrayerListView(compact: true)
                    fieldEditor(.prayerNotes)
                case .freeWrite:
                    VStack(alignment: .leading, spacing: 6) {
                        RichTextToolbar(controller: richController)
                        RichTextEditor(rtf: $rtf, plainText: $plain, controller: richController)
                            .frame(minHeight: 260)
                            .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
                    }
                }
            }

            HStack(spacing: 18) {
                TextField("Tags, comma separated", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                MoodPicker(mood: $mood)
                Spacer()
                Button(saveTitle, action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(currentBody.isEmpty && template != .prayer)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onAppear(perform: load)
    }

    private var currentBody: JournalBody {
        JournalBody(fields: fields.filter { template.fields.contains($0.key) },
                    text: template == .freeWrite ? plain : "")
    }

    private func binding(_ f: JournalField) -> Binding<String> {
        Binding(get: { fields[f] ?? "" }, set: { fields[f] = $0 })
    }

    @ViewBuilder private func fieldEditor(_ f: JournalField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(f.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondaryInk)
            ParchmentEditor(text: binding(f), placeholder: f.placeholder, minHeight: f == .scripture ? 50 : 80)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let existing, let snap = model.store.snapshot(existing) else { return }
        template = snap.template
        fields = snap.body.fields
        plain = snap.body.text
        rtf = model.store.richText(existing) ?? Data()
        tagsText = snap.tags.joined(separator: ", ")
        mood = snap.mood
    }

    private func save() {
        let payload = JournalPayload(body: currentBody, tags: Tags.parse(tagsText), mood: mood,
                                     passage: passage, bookID: bookID)
        do {
            let entry = try model.store.saveJournal(template: template, payload: payload,
                                                    richText: template == .freeWrite && !rtf.isEmpty ? rtf : nil,
                                                    existing: existing)
            model.touch()
            onSaved(entry)
        } catch {
            self.error = "Couldn’t encrypt and save this entry: \(error.localizedDescription)"
        }
    }
}

struct MoodPicker: View {
    @Binding var mood: Int?
    private let faces = ["cloud.rain", "cloud", "cloud.sun", "sun.max", "sun.max.fill"]

    var body: some View {
        HStack(spacing: 6) {
            Text("Mood").font(.callout).foregroundStyle(Theme.secondaryInk)
            ForEach(1...5, id: \.self) { m in
                Button { mood = mood == m ? nil : m } label: {
                    Image(systemName: faces[m - 1])
                        .foregroundStyle(mood == m ? Theme.accent : Theme.secondaryInk.opacity(0.6))
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                .help("\(m) of 5")
            }
        }
    }
}
