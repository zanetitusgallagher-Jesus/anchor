import AnchorCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Search the journal by text, tag, book and date, and export it.
struct JournalPanel: View {
    struct Row: Identifiable {
        let entry: JournalEntry
        let snap: JournalSnapshot
        var id: UUID { entry.id }
    }

    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var tag: String?
    @State private var bookID: String?
    @State private var useDates = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var to = Date.now
    @State private var selected: UUID?
    @State private var composing = false
    @State private var editing: JournalEntry?
    @State private var exportMessage: String?

    var body: some View {
        let _ = model.revision
        let store = model.store
        let entries = store.journalEntries()
        let pairs = entries.compactMap { e in store.snapshot(e).map { Row(entry: e, snap: $0) } }
        let allTags = Array(Set(pairs.flatMap { $0.snap.tags })).sorted()
        let query = JournalSearch.Query(text: text, tag: tag, bookID: bookID,
                                        from: useDates ? Calendar.current.startOfDay(for: from) : nil,
                                        to: useDates ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to)) : nil)
        let results = pairs.filter { JournalSearch.matches($0.snap, query) }

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelTitle(title: "Journal", subtitle: "Encrypted on this Mac. \(entries.count) entr\(entries.count == 1 ? "y" : "ies").")
                Spacer()
                Menu("Export") {
                    Button("Markdown…") { export(results.map(\.snap), pdf: false) }
                    Button("PDF…") { export(results.map(\.snap), pdf: true) }
                }
                .fixedSize()
                Button("New entry") { composing = true }.buttonStyle(PrimaryButtonStyle())
            }

            HStack(spacing: 10) {
                TextField("Search", text: $text).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Picker("Tag", selection: $tag) {
                    Text("Any tag").tag(String?.none)
                    ForEach(allTags, id: \.self) { Text("#\($0)").tag(String?.some($0)) }
                }
                .frame(width: 150)
                Picker("Book", selection: $bookID) {
                    Text("Any book").tag(String?.none)
                    ForEach(BookCatalog.all, id: \.id) { Text($0.name).tag(String?.some($0.id)) }
                }
                .frame(width: 170)
                Toggle("Dates", isOn: $useDates)
            }
            .labelsHidden()
            if useDates {
                HStack {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, displayedComponents: .date)
                }
                .frame(maxWidth: 420)
            }
            if let exportMessage { Text(exportMessage).font(.caption).foregroundStyle(Theme.secondaryInk) }

            if results.isEmpty {
                Text(entries.isEmpty ? "Your entries will appear here." : "No entries match.")
                    .foregroundStyle(Theme.secondaryInk).padding(.top, 20)
            }
            ForEach(results) { row in
                let entry = row.entry
                let snap = row.snap
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(snap.date.formatted(date: .complete, time: .shortened)).font(.caption).foregroundStyle(Theme.secondaryInk)
                            Text(snap.template.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                            if let m = snap.mood { Text("Mood \(m)/5").font(.caption).foregroundStyle(Theme.secondaryInk) }
                            Spacer()
                            Button("Edit") { editing = entry }.buttonStyle(.borderless)
                            Button(role: .destructive) {
                                model.container.mainContext.delete(entry)
                                model.store.save()
                                model.touch()
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                        }
                        if let p = snap.passage { Text(p).font(.system(size: 13, weight: .medium)) }
                        Text(preview(snap))
                            .font(.system(size: 15, design: .serif))
                            .lineLimit(selected == entry.id ? nil : 4)
                            .fixedSize(horizontal: false, vertical: true)
                            .onTapGesture { selected = selected == entry.id ? nil : entry.id }
                        if !snap.tags.isEmpty {
                            Text(snap.tags.map { "#\($0)" }.joined(separator: "  ")).font(.caption).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $composing) {
            editorSheet(nil) { composing = false }
        }
        .sheet(item: $editing) { e in
            editorSheet(e) { editing = nil }
        }
    }

    private func editorSheet(_ e: JournalEntry?, close: @escaping () -> Void) -> some View {
        let snap = e.flatMap { model.store.snapshot($0) }
        return ScrollView {
            VStack(alignment: .leading) {
                JournalEditorView(passage: snap?.passage, existing: e) { _ in close() }
                Button("Cancel", action: close).buttonStyle(QuietButtonStyle())
            }
            .padding(24)
        }
        .frame(width: 720, height: 640)
        .background(Theme.background)
    }

    private func preview(_ s: JournalSnapshot) -> String {
        let fieldText = s.template.fields.compactMap { f -> String? in
            guard let v = s.body.fields[f], !v.isEmpty else { return nil }
            return s.template == .gratitude ? "• \(v)" : "\(f.title): \(v)"
        }
        return (fieldText + [s.body.text]).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func export(_ snaps: [JournalSnapshot], pdf: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [pdf ? .pdf : UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Anchor Journal \(DayKey(.now)).\(pdf ? "pdf" : "md")"
        panel.message = "Exports are not encrypted. Keep them somewhere safe."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = JournalExporter.markdown(snaps)
        do {
            if pdf {
                try JournalPDF.write(markdown: md, to: url)
            } else {
                try md.write(to: url, atomically: true, encoding: .utf8)
            }
            exportMessage = "Exported \(snaps.count) entries to \(url.lastPathComponent)."
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

/// Renders the Markdown export as a paginated, serif PDF.
enum JournalPDF {
    @MainActor
    static func write(markdown: String, to url: URL) throws {
        let body = NSFont(name: "New York", size: 12) ?? .systemFont(ofSize: 12)
        func serif(_ size: CGFloat, bold: Bool = false) -> NSFont {
            let base = NSFont(name: "New York", size: size) ?? .systemFont(ofSize: size)
            return bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
        }
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 6
        para.lineSpacing = 2

        let out = NSMutableAttributedString()
        for line in markdown.components(separatedBy: "\n") {
            var text = line
            var font = body
            var color = NSColor.black
            if line.hasPrefix("# ") { text = String(line.dropFirst(2)); font = serif(24, bold: true) }
            else if line.hasPrefix("## ") { text = String(line.dropFirst(3)); font = serif(16, bold: true) }
            else if line.hasPrefix("### ") { text = String(line.dropFirst(4)); font = serif(13, bold: true); color = .darkGray }
            else if line == "---" { text = ""; }
            text = text.replacingOccurrences(of: "**", with: "")
            out.append(NSAttributedString(string: text + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para]))
        }

        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 64; info.rightMargin = 64
        info.jobDisposition = .save
        info.dictionary().setObject(url, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue as NSString)
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        tv.textStorage?.setAttributedString(out)
        tv.isVerticallyResizable = true
        tv.sizeToFit()

        let op = NSPrintOperation(view: tv, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        if !op.run() { throw CocoaError(.fileWriteUnknown) }
    }
}
