import AnchorCore
import SwiftUI

/// Play / pause / stop for today's reading, read by a human narrator.
struct ListenBar: View {
    let chapters: [ChapterRef]
    @Environment(AppModel.self) private var model

    var body: some View {
        let listen = model.listen
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    switch listen.state {
                    case .idle, .failed:
                        listen.play(chapters,
                                    bible: { [model] in model.localBible },
                                    narrationText: { [model] in model.bibles.bible("WEB") })
                    case .loading: listen.stop()
                    case .playing, .paused: listen.togglePause()
                    }
                } label: {
                    Label(primaryTitle(listen.state), systemImage: primaryIcon(listen.state))
                        .frame(minWidth: 84)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut("l", modifiers: [.command])
                .help("Listen (⌘L)")

                if listen.isActive {
                    Button { listen.stop() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(.bordered)
                        .help("Stop")
                }

                Picker("Speed", selection: Binding(get: { listen.rate }, set: { listen.rate = $0 })) {
                    Text("0.8×").tag(Float(0.8))
                    Text("1×").tag(Float(1.0))
                    Text("1.25×").tag(Float(1.25))
                    Text("1.5×").tag(Float(1.5))
                }
                .labelsHidden()
                .frame(width: 80)

                if listen.state == .loading {
                    ProgressView().controlSize(.small)
                    Text("Preparing narration…").font(.callout).foregroundStyle(Theme.secondaryInk)
                } else if let now = listen.nowPlaying {
                    Text(now).font(.callout).foregroundStyle(Theme.secondaryInk).lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if case .failed(let message) = listen.state {
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Try again") { listen.retry() }
                        Button("Read it with the Mac’s voice instead") { listen.useMacVoice() }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .font(.caption)
                }
            } else {
                Text("Narrated World English Bible from eBible.org (public domain), streamed over HTTPS. Each passage is cut from its chapter recording, so you hear today’s verses."
                     + (model.localTranslationID == "WEB" ? "" : " The narration reads the World English Bible."))
                    .font(.caption2).foregroundStyle(Theme.secondaryInk.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
        .onDisappear { listen.stop() }
    }

    private func primaryTitle(_ s: ListenController.State) -> String {
        switch s {
        case .idle, .failed: "Listen"
        case .loading: "Cancel"
        case .playing: "Pause"
        case .paused: "Resume"
        }
    }

    private func primaryIcon(_ s: ListenController.State) -> String {
        switch s {
        case .idle, .failed: "play.fill"
        case .loading: "xmark"
        case .playing: "pause.fill"
        case .paused: "play.fill"
        }
    }
}
