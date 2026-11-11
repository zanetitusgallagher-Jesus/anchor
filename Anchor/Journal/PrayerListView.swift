import AnchorCore
import SwiftUI

/// Open requests with a way to record answers. `compact` is used inside the journal step.
struct PrayerListView: View {
    var compact = false
    @Environment(AppModel.self) private var model
    @State private var newTitle = ""
    @State private var answering: UUID?
    @State private var answerNote = ""

    var body: some View {
        let _ = model.revision
        let store = model.store
        let all = store.prayers()
        let open = all.filter { $0.answeredAt == nil }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Add a prayer request", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if open.isEmpty {
                Text("No open requests.").font(.callout).foregroundStyle(Theme.secondaryInk)
            }
            ForEach(open) { p in
                let payload = store.payload(p)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "circle").foregroundStyle(Theme.accent)
                        Text(payload?.title ?? "—").font(.system(size: 15, design: .serif))
                        Spacer()
                        Text(p.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(Theme.secondaryInk)
                        if answering != p.id {
                            Button("Answered") { answering = p.id; answerNote = "" }.buttonStyle(.borderless)
                        }
                    }
                    if answering == p.id {
                        HStack {
                            TextField("How was it answered? (optional)", text: $answerNote)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                try? store.markAnswered(p, note: answerNote)
                                answering = nil
                                model.touch()
                            }
                            Button("Cancel") { answering = nil }.buttonStyle(.borderless)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if !compact {
                let answered = all.filter { $0.answeredAt != nil }
                if !answered.isEmpty {
                    Text("\(answered.count) answered — see the timeline on the dashboard.")
                        .font(.caption).foregroundStyle(Theme.secondaryInk)
                }
            }
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        try? model.store.addPrayer(title: title, details: "")
        newTitle = ""
        model.touch()
    }
}
