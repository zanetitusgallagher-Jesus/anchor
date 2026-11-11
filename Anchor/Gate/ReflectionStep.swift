import AnchorCore
import SwiftUI

struct ReflectionStep: View {
    @Bindable var flow: DailyFlow
    @Environment(AppModel.self) private var model

    @State private var aiQuestions: [String] = []
    @State private var aiAnswers: [String] = []
    @State private var aiFeedback: String?
    @State private var aiBusy = false
    @State private var aiError: String?

    private let minimumCharacters = 12

    var body: some View {
        let aiAvailable = model.settings.aiReflectionEnabled && Keychain.string(.claudeKey) != nil

        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reflect").font(.callout).foregroundStyle(Theme.secondaryInk).textCase(.uppercase).tracking(1.2)
                if let r = flow.reading {
                    Text(r.title).font(.callout).foregroundStyle(Theme.secondaryInk)
                }
            }

            Text(flow.prompt.text)
                .font(Theme.display(30))
                .fixedSize(horizontal: false, vertical: true)

            ParchmentEditor(text: $flow.reflectionAnswer, placeholder: "Write a sentence or two…", minHeight: 140)

            if aiAvailable { aiSection }

            StepFooter(flow: flow,
                       canContinue: !flow.isRequired(.reflection) || flow.reflectionAnswer.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumCharacters,
                       onContinue: save)
        }
    }

    @ViewBuilder private var aiSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Questions from Claude", systemImage: "sparkles").font(.headline)
                    Spacer()
                    if aiQuestions.isEmpty {
                        Button(aiBusy ? "Thinking…" : "Ask") { Task { await loadQuestions() } }
                            .disabled(aiBusy)
                    }
                }
                Text("Sends today’s passage text — and, if you ask for feedback, these questions and your answers — to Anthropic using your API key. Nothing else is sent.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)

                ForEach(aiQuestions.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(aiQuestions[i]).font(.system(size: 15, design: .serif))
                        ParchmentEditor(text: binding(i), placeholder: "Your answer", minHeight: 60)
                    }
                }
                if !aiQuestions.isEmpty && aiFeedback == nil {
                    Button(aiBusy ? "Reading your answers…" : "Get gentle feedback") { Task { await loadFeedback() } }
                        .disabled(aiBusy || aiAnswers.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                }
                if let aiFeedback {
                    Text(aiFeedback)
                        .font(.system(size: 15, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                if let aiError {
                    Text(aiError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private func binding(_ i: Int) -> Binding<String> {
        Binding(get: { aiAnswers.indices.contains(i) ? aiAnswers[i] : "" },
                set: { if aiAnswers.indices.contains(i) { aiAnswers[i] = $0 } })
    }

    private var passageText: String {
        guard let r = flow.reading, let bible = model.localBible else { return "" }
        return r.chapters.map { ch in
            "\(ch)\n" + bible.verses(ch).map { "\($0.ref.verse) \($0.text)" }.joined(separator: " ")
        }.joined(separator: "\n\n")
    }

    private var client: ClaudeClient { ClaudeClient(model: model.settings.aiModel) }

    private func loadQuestions() async {
        aiBusy = true
        aiError = nil
        defer { aiBusy = false }
        do {
            aiQuestions = try await client.questions(reference: flow.reading?.title ?? "", passage: passageText)
            aiAnswers = Array(repeating: "", count: aiQuestions.count)
        } catch {
            aiError = error.localizedDescription
        }
    }

    private func loadFeedback() async {
        aiBusy = true
        aiError = nil
        defer { aiBusy = false }
        do {
            aiFeedback = try await client.feedback(reference: flow.reading?.title ?? "", passage: passageText,
                                                   questions: aiQuestions, answers: aiAnswers)
        } catch {
            aiError = error.localizedDescription
        }
    }

    private func save() {
        let record = ReflectionRecord(prompt: flow.prompt.text, answer: flow.reflectionAnswer,
                                      aiQuestions: aiQuestions, aiAnswers: aiAnswers, aiFeedback: aiFeedback)
        let store = model.store
        if let s = store.session(for: flow.today) {
            s.reflectionPrompt = flow.prompt.text
            s.reflectionCipher = try? JournalCrypto.seal(json: record)
            store.save()
        }
        flow.advance()
    }
}
