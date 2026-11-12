import AnchorCore
import AVFoundation
import Foundation
import Observation

/// Resolves chapter MP3 URLs from eBible.org's folder listings (cached), so a
/// renamed or oddly named file never breaks playback.
@MainActor
final class WEBAudioResolver {
    enum ResolveError: LocalizedError {
        case noFolder, http(Int), noFile
        var errorDescription: String? {
            switch self {
            case .noFolder: "No narration for this book."
            case .http(let c): "eBible.org returned HTTP \(c)."
            case .noFile: "Couldn’t find this chapter’s recording."
            }
        }
    }

    private var cache: [String: [Int: String]] = [:]
    private let defaults = UserDefaults.standard
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    func url(for ref: ChapterRef) async throws -> URL {
        guard let folder = WEBAudio.folderURL(bookID: ref.bookID),
              let count = BookCatalog.entry(ref.bookID)?.chapters else { throw ResolveError.noFolder }
        let map = try await files(bookID: ref.bookID, folder: folder, chapterCount: count)
        guard let href = map[ref.chapter], let url = URL(string: href, relativeTo: folder)?.absoluteURL else {
            throw ResolveError.noFile
        }
        return url
    }

    private func files(bookID: String, folder: URL, chapterCount: Int) async throws -> [Int: String] {
        if let m = cache[bookID], m.count == chapterCount { return m }
        let key = "anchor.webaudio.\(bookID)"
        if let saved = defaults.dictionary(forKey: key) as? [String: String] {
            let m = Dictionary(uniqueKeysWithValues: saved.compactMap { k, v in Int(k).map { ($0, v) } })
            if m.count == chapterCount { cache[bookID] = m; return m }
        }
        let (data, resp) = try await session.data(from: folder)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ResolveError.http(code) }
        let html = String(decoding: data, as: UTF8.self)
        let m = WEBAudio.chapterFiles(hrefs: WEBAudio.mp3Links(inListing: html), chapterCount: chapterCount)
        guard !m.isEmpty else { throw ResolveError.noFile }
        cache[bookID] = m
        if m.count == chapterCount {
            defaults.set(Dictionary(uniqueKeysWithValues: m.map { (String($0.key), $0.value) }), forKey: key)
        }
        return m
    }

    /// Forget a book's cached listing (after a playback failure, in case files moved).
    func invalidate(bookID: String) {
        cache[bookID] = nil
        defaults.removeObject(forKey: "anchor.webaudio.\(bookID)")
    }
}

/// Plays today's reading aloud. Two sources:
/// - **Narrator**: human-read World English Bible MP3s from eBible.org over HTTPS (whole chapters).
/// - **Built-in voice**: the Mac's own speech voice reading the exact verses, offline.
/// If narration can't load or stops with an error, it switches to the built-in
/// voice for the rest of the passage and says so, so listening always works.
@MainActor
@Observable
final class ListenController: NSObject {
    enum Source: String, CaseIterable, Identifiable {
        case narrator, deviceVoice
        var id: String { rawValue }
        var title: String { self == .narrator ? "Narrator (WEB)" : "Built-in voice" }
    }

    enum State: Equatable { case idle, loading, playing, paused }

    private(set) var state: State = .idle
    private(set) var nowPlaying: String?
    private(set) var notice: String?
    /// The verse being spoken (built-in voice), for highlighting in the reader.
    private(set) var currentVerse: VerseRef?
    var source: Source = .narrator
    var rate: Float = 1.0 {
        didSet {
            player?.rate = state == .playing ? rate : 0
        }
    }

    @ObservationIgnored private var queue: [ChapterRef] = []
    @ObservationIgnored private var position = 0
    @ObservationIgnored private var bible: (@MainActor () -> Bible?)?
    @ObservationIgnored private let resolver = WEBAudioResolver()
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failObserver: NSObjectProtocol?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored private var utteranceVerses: [ObjectIdentifier: VerseRef] = [:]
    @ObservationIgnored private var generation = 0

    override init() {
        super.init()
        synth.delegate = self
    }

    var isActive: Bool { state != .idle }

    /// Picks a sensible default: narrator for whole chapters, built-in voice
    /// when today's passages are parts of chapters.
    func prepare(_ chapters: [ChapterRef]) {
        if state == .idle {
            source = chapters.allSatisfy(\.isWholeChapter) ? .narrator : .deviceVoice
        }
    }

    func play(_ chapters: [ChapterRef], bible: @escaping @MainActor () -> Bible?) {
        stop()
        generation += 1
        queue = chapters
        position = 0
        self.bible = bible
        notice = nil
        playCurrent()
    }

    func togglePause() {
        switch state {
        case .playing:
            if synth.isSpeaking { synth.pauseSpeaking(at: .word) }
            player?.pause()
            state = .paused
        case .paused:
            if synth.isPaused { synth.continueSpeaking() }
            player?.rate = rate
            state = .playing
        default: break
        }
    }

    func stop() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        teardownPlayer()
        if synth.isSpeaking || synth.isPaused { synth.stopSpeaking(at: .immediate) }
        utteranceVerses = [:]
        state = .idle
        nowPlaying = nil
        currentVerse = nil
    }

    // MARK: Queue

    private func playCurrent() {
        guard position < queue.count else { finish(); return }
        let ref = queue[position]
        switch source {
        case .narrator: playNarration(ref)
        case .deviceVoice: speak(ref)
        }
    }

    private func next() {
        position += 1
        playCurrent()
    }

    private func finish() {
        teardownPlayer()
        state = .idle
        nowPlaying = nil
        currentVerse = nil
    }

    // MARK: Narrator (HTTPS MP3)

    private func playNarration(_ ref: ChapterRef) {
        state = .loading
        let whole = ChapterRef(bookID: ref.bookID, chapter: ref.chapter)
        nowPlaying = ref.isWholeChapter ? whole.description : "\(whole.description) (whole chapter)"
        let gen = generation
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await resolver.url(for: whole)
                guard gen == generation else { return }
                startPlayer(url: url, ref: ref, gen: gen)
            } catch {
                guard gen == generation, !Task.isCancelled else { return }
                fallBack(ref, reason: error.localizedDescription)
            }
        }
    }

    private func startPlayer(url: URL, ref: ChapterRef, gen: Int) {
        teardownPlayer()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        player = p
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                switch status {
                case .readyToPlay:
                    if self.state == .loading {
                        self.state = .playing
                        self.player?.rate = self.rate
                    }
                case .failed:
                    self.resolver.invalidate(bookID: ref.bookID)
                    self.fallBack(ref, reason: message ?? "The recording couldn’t be loaded.")
                default: break
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, gen == self.generation else { return }
                self.next()
            }
        }
        failObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
            let err = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            MainActor.assumeIsolated {
                guard let self, gen == self.generation else { return }
                self.fallBack(ref, reason: err ?? "Playback stopped.")
            }
        }
        // Don't wait forever on a dead connection.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, gen == self.generation, self.state == .loading else { return }
            self.fallBack(ref, reason: "The recording took too long to load.")
        }
    }

    private func teardownPlayer() {
        itemObservation?.invalidate()
        itemObservation = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        if let o = failObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
        failObserver = nil
        player?.pause()
        player = nil
    }

    private func fallBack(_ ref: ChapterRef, reason: String) {
        teardownPlayer()
        notice = "Narration isn’t available right now (\(reason)). Using the built-in voice instead."
        source = .deviceVoice
        speak(ref)
    }

    // MARK: Built-in voice (offline)

    private func speak(_ ref: ChapterRef) {
        let verses = bible?()?.verses(ref) ?? []
        guard !verses.isEmpty else { next(); return }
        nowPlaying = ref.description
        state = .playing
        let voice = Self.bestVoice()
        let intro = AVSpeechUtterance(string: spokenReference(ref))
        configure(intro, voice: voice)
        intro.postUtteranceDelay = 0.4
        synth.speak(intro)
        for v in verses {
            let u = AVSpeechUtterance(string: v.text)
            configure(u, voice: voice)
            u.postUtteranceDelay = 0.15
            utteranceVerses[ObjectIdentifier(u)] = v.ref
            synth.speak(u)
        }
        // Marks the end of this passage.
        let end = AVSpeechUtterance(string: " ")
        configure(end, voice: voice)
        utteranceVerses[ObjectIdentifier(end)] = VerseRef(bookID: "", chapter: -1, verse: -1)
        synth.speak(end)
    }

    private func configure(_ u: AVSpeechUtterance, voice: AVSpeechSynthesisVoice?) {
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * min(1.4, max(0.6, rate * 0.95))
    }

    private func spokenReference(_ ref: ChapterRef) -> String {
        let name = BookCatalog.name(ref.bookID)
        if ref.isWholeChapter { return "\(name), chapter \(ref.chapter)." }
        let s = ref.verseStart ?? 1
        if let e = ref.verseEnd { return "\(name) \(ref.chapter), verses \(s) to \(e)." }
        return "\(name) \(ref.chapter), from verse \(s)."
    }

    /// The best installed English voice: premium, then enhanced, then default.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let lang = Locale.preferredLanguages.first ?? "en-US"
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let ranked = english.sorted { a, b in
            if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
            return (a.language == lang ? 0 : 1) < (b.language == lang ? 0 : 1)
        }
        return ranked.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension ListenController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            if let v = self.utteranceVerses[id], v.chapter > 0 { self.currentVerse = v }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let v = self.utteranceVerses.removeValue(forKey: id), v.chapter == -1 else { return }
            self.currentVerse = nil
            self.next()
        }
    }
}
