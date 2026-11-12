import AnchorCore
import SwiftUI

/// Play / pause / stop for today's reading, with the source and speed.
struct ListenBar: View {
    let chapters: [ChapterRef]
    @Environment(AppModel.self) private var model

    var body: some View {
        let listen = model.listen
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    switch listen.state {
                    case .idle: listen.play(chapters) { [model] in model.localBible }
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

                Picker("Voice", selection: Binding(get: { listen.source }, set: { listen.source = $0 })) {
                    ForEach(ListenController.Source.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
                .disabled(listen.isActive)

                Picker("Speed", selection: Binding(get: { listen.rate }, set: { listen.rate = $0 })) {
                    Text("0.8×").tag(Float(0.8))
                    Text("1×").tag(Float(1.0))
                    Text("1.25×").tag(Float(1.25))
                    Text("1.5×").tag(Float(1.5))
                }
                .labelsHidden()
                .frame(width: 80)

                if listen.state == .loading { ProgressView().controlSize(.small) }
                if let now = listen.nowPlaying {
                    Text(now).font(.callout).foregroundStyle(Theme.secondaryInk).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let notice = listen.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(listen.source == .narrator
                     ? "Human narration of the World English Bible from eBible.org (public domain), streamed over HTTPS. Passages that are part of a chapter play the whole chapter."
                     : "Your Mac’s built-in voice reads the exact verses, offline. For a more natural voice, add a Premium or Enhanced English voice in System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.")
                    .font(.caption2).foregroundStyle(Theme.secondaryInk.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
        .onAppear { listen.prepare(chapters) }
        .onDisappear { listen.stop() }
    }

    private func primaryTitle(_ s: ListenController.State) -> String {
        switch s {
        case .idle: "Listen"
        case .loading: "Cancel"
        case .playing: "Pause"
        case .paused: "Resume"
        }
    }

    private func primaryIcon(_ s: ListenController.State) -> String {
        switch s {
        case .idle: "play.fill"
        case .loading: "xmark"
        case .playing: "pause.fill"
        case .paused: "play.fill"
        }
    }
}
