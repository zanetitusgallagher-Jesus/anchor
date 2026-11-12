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

/// Downloads chapter recordings over HTTPS once and keeps them in Caches, so
/// passages can be cut exactly and replayed without the network.
@MainActor
final class NarrationLibrary {
    let resolver = WEBAudioResolver()
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 180
        return URLSession(configuration: c)
    }()
    private var inFlight: [String: Task<URL, Error>] = [:]

    private var directory: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Narration", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    enum DownloadError: LocalizedError {
        case http(Int), notAudio(String)
        var errorDescription: String? {
            switch self {
            case .http(let c): "eBible.org returned HTTP \(c)."
            case .notAudio(let t): "eBible.org sent \(t) instead of audio."
            }
        }
    }

    /// The local file for a chapter's recording, downloading it if needed.
    func file(for chapter: ChapterRef) async throws -> URL {
        let key = "\(chapter.bookID)-\(chapter.chapter)"
        let dest = directory.appendingPathComponent("\(key).mp3")
        if let size = try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 20_000 { return dest }
        if let t = inFlight[key] { return try await t.value }
        let t = Task { () throws -> URL in
            let remote = try await resolver.url(for: ChapterRef(bookID: chapter.bookID, chapter: chapter.chapter))
            let (tmp, resp) = try await session.download(from: remote)
            let http = resp as? HTTPURLResponse
            guard let code = http?.statusCode, (200..<300).contains(code) else { throw DownloadError.http(http?.statusCode ?? 0) }
            let type = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard type.lowercased().contains("audio") || type.lowercased().contains("mpeg") else {
                resolver.invalidate(bookID: chapter.bookID)
                throw DownloadError.notAudio(type.isEmpty ? "an unknown file" : type)
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        }
        inFlight[key] = t
        defer { inFlight[key] = nil }
        return try await t.value
    }

    /// Start downloading in the background (used for the next passage).
    func prefetch(_ chapter: ChapterRef) {
        Task { _ = try? await file(for: chapter) }
    }
}

/// A passage cut from a chapter recording.
struct NarrationSegment: Sendable {
    let ref: ChapterRef
    let file: URL
    let start: Double
    let end: Double
    let duration: Double
    let verseLengths: [Int]

    /// Cuts `ref` out of the chapter recording at `file`, snapping both cuts to
    /// the narrator's pauses (see NarrationTiming).
    static func cut(_ ref: ChapterRef, file: URL, verseLengths: [Int]) throws -> NarrationSegment {
        let audio = try AVAudioFile(forReading: file)
        let rate = audio.processingFormat.sampleRate
        let duration = Double(audio.length) / rate
        if ref.isWholeChapter {
            return NarrationSegment(ref: ref, file: file, start: 0, end: duration, duration: duration, verseLengths: verseLengths)
        }
        let est = NarrationTiming.estimate(verseLengths: verseLengths, start: ref.verseStart, end: ref.verseEnd, duration: duration)
        var start = est.start
        var end = est.end
        if start > 1 {
            let (levels, offset) = try loudness(audio, around: start, duration: duration)
            start = NarrationTiming.snapToPause(levels: levels, step: 0.05, offset: offset, target: start, lean: .earlier)
        } else {
            start = 0
        }
        if end < duration - 1 {
            let (levels, offset) = try loudness(audio, around: end, duration: duration)
            end = NarrationTiming.snapToPause(levels: levels, step: 0.05, offset: offset, target: end, lean: .later)
        } else {
            end = duration
        }
        return NarrationSegment(ref: ref, file: file, start: max(0, start), end: min(duration, max(start + 1, end)),
                                duration: duration, verseLengths: verseLengths)
    }

    /// RMS loudness in 50 ms windows for ±8 s around `center`.
    private static func loudness(_ audio: AVAudioFile, around center: Double, duration: Double) throws -> ([Float], Double) {
        let rate = audio.processingFormat.sampleRate
        let from = max(0, center - 8)
        let to = min(duration, center + 8)
        let frames = AVAudioFrameCount((to - from) * rate)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: frames) else { return ([], from) }
        audio.framePosition = AVAudioFramePosition(from * rate)
        try audio.read(into: buffer, frameCount: frames)
        guard let samples = buffer.floatChannelData?[0] else { return ([], from) }
        let window = max(1, Int(rate * 0.05))
        var levels: [Float] = []
        var i = 0
        let n = Int(buffer.frameLength)
        while i + window <= n {
            var sum: Float = 0
            for j in i..<(i + window) { sum += samples[j] * samples[j] }
            levels.append((sum / Float(window)).squareRoot())
            i += window
        }
        return (levels, from)
    }
}

/// Plays today's reading with the human narration of the World English Bible
/// from eBible.org. Each passage is cut out of its chapter recording, so you
/// hear exactly today's verses. The Mac's built-in voice is only used if you
/// choose it after narration fails.
@MainActor
@Observable
final class ListenController: NSObject {
    enum State: Equatable { case idle, loading, playing, paused, failed(String) }

    private(set) var state: State = .idle
    private(set) var nowPlaying: String?
    /// The verse being read, for highlighting in the reader.
    private(set) var currentVerse: VerseRef?
    var rate: Float = 1.0 {
        didSet { if state == .playing { player?.rate = rate } }
    }

    @ObservationIgnored private var queue: [ChapterRef] = []
    @ObservationIgnored private var position = 0
    @ObservationIgnored private var bible: (@MainActor () -> Bible?)?
    @ObservationIgnored private var narrationText: (@MainActor () -> Bible?)?
    @ObservationIgnored let library = NarrationLibrary()
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var observers: [Any] = []
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var usingMacVoice = false
    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored private var utteranceVerses: [ObjectIdentifier: VerseRef] = [:]

    override init() {
        super.init()
        synth.delegate = self
    }

    var isActive: Bool {
        switch state {
        case .idle, .failed: false
        default: true
        }
    }

    /// - Parameters:
    ///   - bible: the translation shown on screen (for the Mac-voice fallback).
    ///   - narrationText: the World English Bible, which the narrator reads (used to time the cuts).
    func play(_ chapters: [ChapterRef], bible: @escaping @MainActor () -> Bible?, narrationText: @escaping @MainActor () -> Bible?) {
        stop()
        generation += 1
        queue = chapters
        position = 0
        self.bible = bible
        self.narrationText = narrationText
        usingMacVoice = false
        playCurrent()
    }

    /// After a failure: try the narration again from the passage that failed.
    func retry() {
        guard position < queue.count else { return }
        generation += 1
        usingMacVoice = false
        playCurrent()
    }

    /// After a failure, if the user asks: read the rest with the Mac's voice.
    func useMacVoice() {
        guard position < queue.count else { return }
        generation += 1
        usingMacVoice = true
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
        teardownPlayer()
        if synth.isSpeaking || synth.isPaused { synth.stopSpeaking(at: .immediate) }
        utteranceVerses = [:]
        state = .idle
        nowPlaying = nil
        currentVerse = nil
    }

    private func playCurrent() {
        guard position < queue.count else { finish(); return }
        let ref = queue[position]
        if usingMacVoice { speak(ref) } else { narrate(ref) }
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

    // MARK: Narration

    private func verseLengths(_ ref: ChapterRef) -> [Int] {
        guard let book = narrationText?()?.book(ref.bookID), book.chapters.indices.contains(ref.chapter - 1) else { return [] }
        return book.chapters[ref.chapter - 1].map(\.count)
    }

    private func narrate(_ ref: ChapterRef) {
        teardownPlayer()
        state = .loading
        nowPlaying = ref.description
        currentVerse = nil
        let gen = generation
        let lengths = verseLengths(ref)
        if position + 1 < queue.count { library.prefetch(queue[position + 1]) }
        Task { [weak self] in
            guard let self else { return }
            do {
                let file = try await library.file(for: ref)
                let segment = try await Task.detached(priority: .userInitiated) {
                    try NarrationSegment.cut(ref, file: file, verseLengths: lengths)
                }.value
                guard gen == generation else { return }
                start(segment, gen: gen)
            } catch {
                guard gen == generation else { return }
                teardownPlayer()
                state = .failed("Couldn’t load the narration for \(ref): \(error.localizedDescription)")
            }
        }
    }

    private func start(_ seg: NarrationSegment, gen: Int) {
        let asset = AVURLAsset(url: seg.file, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        let p = AVPlayer(playerItem: item)
        player = p

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                if status == .failed {
                    self.teardownPlayer()
                    self.state = .failed("The recording for \(seg.ref) couldn’t be played: \(message ?? "unknown error").")
                }
            }
        }

        let startTime = CMTime(seconds: seg.start, preferredTimescale: 600)
        p.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.player?.rate = self.rate
                self.state = .playing
            }
        }

        // Stop at the end of the passage, then move on.
        if seg.end < seg.duration - 0.3 {
            let token = p.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: seg.end, preferredTimescale: 600))], queue: .main) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, gen == self.generation else { return }
                    self.teardownPlayer()
                    self.next()
                }
            }
            observers.append(token)
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, gen == self.generation else { return }
                self.teardownPlayer()
                self.next()
            }
        }
        // Follow along: highlight the verse being read.
        let tick = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.3, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, gen == self.generation else { return }
                if let i = NarrationTiming.verseIndex(at: time.seconds, duration: seg.duration, verseLengths: seg.verseLengths) {
                    let lo = seg.ref.verseStart ?? 1
                    let hi = seg.ref.verseEnd ?? Int.max
                    self.currentVerse = (lo...hi).contains(i) ? VerseRef(bookID: seg.ref.bookID, chapter: seg.ref.chapter, verse: i) : nil
                }
            }
        }
        observers.append(tick)
    }

    private func teardownPlayer() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let p = player { observers.forEach { p.removeTimeObserver($0) } }
        observers = []
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
        player?.pause()
        player = nil
    }

    // MARK: Mac voice (only when chosen after a failure)

    private func speak(_ ref: ChapterRef) {
        let verses = bible?()?.verses(ref) ?? []
        guard !verses.isEmpty else { next(); return }
        nowPlaying = ref.description
        state = .playing
        let voice = Self.bestVoice()
        for v in verses {
            let u = AVSpeechUtterance(string: v.text)
            u.voice = voice
            u.rate = AVSpeechUtteranceDefaultSpeechRate * min(1.4, max(0.6, rate * 0.95))
            u.postUtteranceDelay = 0.15
            utteranceVerses[ObjectIdentifier(u)] = v.ref
            synth.speak(u)
        }
        let end = AVSpeechUtterance(string: " ")
        utteranceVerses[ObjectIdentifier(end)] = VerseRef(bookID: "", chapter: -1, verse: -1)
        synth.speak(end)
    }

    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return english.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
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
