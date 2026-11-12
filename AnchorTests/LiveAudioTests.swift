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

    func testBuiltInVoiceIsAvailable() {
        XCTAssertNotNil(ListenController.bestVoice())
        XCTAssertFalse(AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }.isEmpty)
    }
}
