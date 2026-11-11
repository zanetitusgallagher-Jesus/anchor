import AnchorCore
import AppKit
import Combine
import SwiftUI

/// Gate step: today's reading must stay on screen for the minimum time
/// (counted only while Anchor is frontmost) before Continue unlocks.
struct ScriptureStep: View {
    let flow: DailyFlow
    @Environment(AppModel.self) private var model
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let remaining = Int(GateFlow.readingSecondsRemaining(elapsed: flow.readingSeconds, settings: model.settings).rounded(.up))
        let required = flow.isRequired(.scripture)

        VStack(alignment: .leading, spacing: 20) {
            if let reading = flow.reading {
                ScriptureReaderView(chapters: reading.chapters,
                                    heading: reading.title,
                                    subheading: "\(reading.plan.name) · Day \(reading.dayIndex + 1) of \(reading.plan.days.count)")
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Plan complete").font(Theme.display(26))
                        Text("You’ve finished your reading plan. Choose a new one in Settings → Scripture. For today, sit with a psalm.")
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                ScriptureReaderView(chapters: [ChapterRef(bookID: "PSA", chapter: (flow.today.day % 150) + 1)],
                                    heading: "Psalm \((flow.today.day % 150) + 1)", subheading: nil)
            }

            StepFooter(flow: flow,
                       canContinue: !required || remaining == 0,
                       hint: remaining > 0 && required ? "Continue in \(remaining.clockString)" : nil,
                       onContinue: { flow.finishScripture() })
        }
        .onReceive(tick) { _ in
            if NSApp.isActive { flow.recordReadingTick(1) }
        }
    }
}

/// Renders chapters from a bundled translation (or API.Bible) with
/// adjustable type and per-verse "memorize" stars.
struct ScriptureReaderView: View {
    let chapters: [ChapterRef]
    let heading: String
    let subheading: String?

    @Environment(AppModel.self) private var model
    @State private var apiPassages: [ChapterRef: APIBibleClient.Passage] = [:]
    @State private var apiError: String?
    @State private var starred: Set<VerseRef> = []

    var body: some View {
        let settings = model.settings
        let usingAPI = settings.translationID == "API" && settings.apiBibleID != nil

        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heading).font(Theme.display(34))
                    if let subheading {
                        Text(subheading).font(.callout).foregroundStyle(Theme.secondaryInk)
                    }
                }
                Spacer()
                controls
            }

            ForEach(chapters, id: \.self) { chapter in
                VStack(alignment: .leading, spacing: 12) {
                    if chapters.count > 1 {
                        Text(chapter.description)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryInk)
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .padding(.top, 10)
                    }
                    if usingAPI {
                        apiChapter(chapter)
                    } else {
                        localChapter(chapter)
                    }
                }
            }
        }
        .task(id: "\(settings.translationID)|\(settings.apiBibleID ?? "")") {
            starred = Set(model.store.allVerses().map { VerseRef(bookID: $0.bookID, chapter: $0.chapter, verse: $0.verse) })
            guard usingAPI, let id = settings.apiBibleID else { return }
            await loadAPI(bibleID: id)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Translation", selection: Binding(get: { model.settings.translationID },
                                                     set: { model.settings.translationID = $0 })) {
                ForEach(BibleStore.bundled, id: \.id) { Text($0.id).tag($0.id) }
                if let name = model.settings.apiBibleName, model.settings.apiBibleID != nil {
                    Text(name).tag("API")
                }
            }
            .labelsHidden()
            .frame(width: 110)
            Button { adjustFont(-2) } label: { Image(systemName: "textformat.size.smaller") }
                .help("Smaller text")
            Button { adjustFont(2) } label: { Image(systemName: "textformat.size.larger") }
                .help("Larger text")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.secondaryInk)
    }

    private func adjustFont(_ delta: Double) {
        model.settings.scriptureFontSize = min(40, max(14, model.settings.scriptureFontSize + delta))
    }

    @ViewBuilder private func localChapter(_ chapter: ChapterRef) -> some View {
        let settings = model.settings
        let verses = model.localBible?.verses(chapter) ?? []
        VStack(alignment: .leading, spacing: settings.scriptureFontSize * 0.45) {
            ForEach(verses) { v in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(v.ref.verse)")
                        .font(.system(size: settings.scriptureFontSize * 0.55, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: settings.scriptureFontSize * 1.1, alignment: .trailing)
                    Text(v.text)
                        .font(Theme.scripture(settings))
                        .lineSpacing(settings.scriptureFontSize * 0.35)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { toggle(v) } label: {
                        Image(systemName: starred.contains(v.ref) ? "star.fill" : "star")
                            .foregroundStyle(starred.contains(v.ref) ? Theme.accent : Theme.hairline)
                    }
                    .buttonStyle(.borderless)
                    .help(starred.contains(v.ref) ? "Remove from memory verses" : "Memorize this verse")
                }
            }
            Text(model.localBible?.name ?? "").font(.caption2).foregroundStyle(Theme.secondaryInk.opacity(0.7))
                .padding(.top, 6)
        }
    }

    @ViewBuilder private func apiChapter(_ chapter: ChapterRef) -> some View {
        if let p = apiPassages[chapter] {
            VStack(alignment: .leading, spacing: 10) {
                Text(p.content.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(Theme.scripture(model.settings))
                    .lineSpacing(model.settings.scriptureFontSize * 0.35)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let c = p.copyright {
                    Text(c).font(.caption2).foregroundStyle(Theme.secondaryInk)
                }
                Text("To memorize a verse from this chapter, switch to WEB or KJV and tap its star.")
                    .font(.caption2).foregroundStyle(Theme.secondaryInk.opacity(0.7))
            }
        } else if let apiError {
            VStack(alignment: .leading, spacing: 8) {
                Text(apiError).font(.callout).foregroundStyle(.red)
                Text("Showing the World English Bible instead.").font(.caption).foregroundStyle(Theme.secondaryInk)
                localChapter(chapter)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func loadAPI(bibleID: String) async {
        apiError = nil
        let client = APIBibleClient()
        for ch in chapters where apiPassages[ch] == nil {
            do { apiPassages[ch] = try await client.chapter(ch, bibleID: bibleID) }
            catch { apiError = error.localizedDescription; return }
        }
    }

    private func toggle(_ v: Verse) {
        model.store.toggleMemorize(v, translationID: model.localTranslationID)
        if starred.contains(v.ref) { starred.remove(v.ref) } else { starred.insert(v.ref) }
        model.touch()
    }
}
