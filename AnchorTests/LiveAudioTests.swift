import AnchorCore
import AVFoundation
import XCTest
@testable import Anchor

/// Live checks against eBible.org over HTTPS: every chapter of the Bible must
/// resolve to a real recording. Runs in CI, so a broken source fails the build.
@MainActor
final class LiveAudioTests: XCTestCase {
    private func fetch(_ url: URL, range: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url, timeoutInterval: 30)
        if let range { req.setValue(range, forHTTPHeaderField: "Range") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            return (data, resp as! HTTPURLResponse)
        } catch let e as URLError where e.code == .notConnectedToInternet {
            throw XCTSkip("No internet connection")
        }
    }

    func testEveryChapterOfTheBibleHasARecording() async throws {
        var problems: [String] = []
        var total = 0
        for book in BookCatalog.all {
            let folder = try XCTUnwrap(WEBAudio.folderURL(bookID: book.id))
            XCTAssertEqual(folder.scheme, "https")
            let (data, resp) = try await fetch(folder)
            guard resp.statusCode == 200 else { problems.append("\(book.name): HTTP \(resp.statusCode)"); continue }
            let map = WEBAudio.chapterFiles(hrefs: WEBAudio.mp3Links(inListing: String(decoding: data, as: UTF8.self)),
                                            chapterCount: book.chapters)
            if map.count != book.chapters {
                let missing = (1...book.chapters).filter { map[$0] == nil }
                problems.append("\(book.name): missing chapters \(missing)")
            }
            total += map.count
        }
        XCTAssertEqual(problems, [])
        XCTAssertEqual(total, 1189, "Every chapter resolves to a recording")
    }

    func testSampleRecordingsAreRealMP3Audio() async throws {
        let resolver = WEBAudioResolver()
        let samples = [("GEN", 1), ("PSA", 23), ("PSA", 71), ("PSA", 119), ("PRO", 31), ("ISA", 53),
                       ("JHN", 3), ("ROM", 8), ("PHM", 1), ("3JN", 1), ("REV", 22)]
        for (book, ch) in samples {
            let url = try await resolver.url(for: ChapterRef(bookID: book, chapter: ch))
            XCTAssertEqual(url.scheme, "https", url.absoluteString)
            let (data, resp) = try await fetch(url, range: "bytes=0-4095")
            XCTAssertTrue([200, 206].contains(resp.statusCode), "\(book) \(ch): HTTP \(resp.statusCode)")
            XCTAssertEqual(resp.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("audio/mpeg"), true,
                           "\(book) \(ch): \(resp.value(forHTTPHeaderField: "Content-Type") ?? "no type")")
            let bytes = [UInt8](data.prefix(3))
            let isMP3 = bytes.starts(with: Array("ID3".utf8)) || (bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0)
            XCTAssertTrue(isMP3, "\(book) \(ch) starts with \(bytes)")
        }
    }

    func testAVFoundationCanOpenARecording() async throws {
        let url = try await WEBAudioResolver().url(for: ChapterRef(bookID: "JHN", chapter: 3))
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 60, "John 3 should be several minutes long")
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
    }

    private func lengths(_ ref: ChapterRef, _ web: Bible) -> [Int] {
        web.book(ref.bookID)!.chapters[ref.chapter - 1].map(\.count)
    }

    /// RMS of the audio in a short window, relative to the chapter's median loudness.
    private func relativeLoudness(_ file: URL, at t: Double) throws -> Float {
        let audio = try AVAudioFile(forReading: file)
        let rate = audio.processingFormat.sampleRate
        func rms(from: Double, seconds: Double) throws -> Float {
            let frames = AVAudioFrameCount(seconds * rate)
            let buf = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: frames)!
            audio.framePosition = AVAudioFramePosition(max(0, from) * rate)
            try audio.read(into: buf, frameCount: frames)
            let p = buf.floatChannelData![0]
            var sum: Float = 0
            for i in 0..<Int(buf.frameLength) { sum += p[i] * p[i] }
            return (sum / Float(max(1, buf.frameLength))).squareRoot()
        }
        let here = try rms(from: t - 0.1, seconds: 0.2)
        let typical = try rms(from: t - 8, seconds: 16)
        return here / max(typical, 1e-6)
    }

    func testCutsAPassageAtTheNarratorsPauses() async throws {
        let web = try XCTUnwrap(BibleStore().bible("WEB"))
        let library = NarrationLibrary()
        let ref = ChapterRef(bookID: "JHN", chapter: 3, verseStart: 16, verseEnd: 21)
        let file = try await library.file(for: ref)
        let seg = try NarrationSegment.cut(ref, file: file, verseLengths: lengths(ref, web))

        XCTAssertGreaterThan(seg.duration, 120, "John 3 is several minutes long")
        XCTAssertGreaterThan(seg.start, seg.duration * 0.4, "3:16 is past the middle of the chapter")
        XCTAssertLessThan(seg.end, seg.duration * 0.95)
        // Six verses of 36: roughly a sixth of the chapter, allowing for pace.
        let share = (seg.end - seg.start) / seg.duration
        XCTAssertTrue((0.08...0.35).contains(share), "share \(share)")
        // Both cuts sit in pauses: much quieter than the speech around them.
        XCTAssertLessThan(try relativeLoudness(file, at: seg.start), 0.5, "start at \(seg.start)s is in a pause")
        XCTAssertLessThan(try relativeLoudness(file, at: seg.end), 0.5, "end at \(seg.end)s is in a pause")

        // Cached: the second request doesn't download again.
        let again = try await library.file(for: ref)
        XCTAssertEqual(again, file)
    }

    func testEveryPassageOfAShuffledDayCanBeCut() async throws {
        let web = try XCTUnwrap(BibleStore().bible("WEB"))
        let kjv = try XCTUnwrap(BibleStore().bible("KJV"))
        let plan = ReadingPlanGenerator.shuffledWholeBible(verseCounts: ReadingPlanGenerator.verseCounts(of: kjv), seed: 2026)
        let library = NarrationLibrary()
        for ref in plan.days[0] {
            let file = try await library.file(for: ref)
            let seg = try NarrationSegment.cut(ref, file: file, verseLengths: lengths(ref, web))
            XCTAssertLessThan(seg.start, seg.end, "\(ref)")
            XCTAssertGreaterThan(seg.end - seg.start, 5, "\(ref) is at least a few seconds")
            if !ref.isWholeChapter {
                XCTAssertLessThan(seg.end - seg.start, seg.duration, "\(ref) is shorter than its chapter")
            }
        }
    }

    func testBuiltInVoiceIsAvailable() {
        XCTAssertNotNil(ListenController.bestVoice())
        XCTAssertFalse(AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }.isEmpty)
    }
}
