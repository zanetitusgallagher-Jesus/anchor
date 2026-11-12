import XCTest
@testable import AnchorCore

/// File names below are copied from the real eBible.org listings.
final class AudioBibleTests: XCTestCase {
    func testChapterNumbersFromEveryNamingStyle() {
        let cases: [(String, Int)] = [
            ("01_01_Genesis_Chapter_One.mp3", 1),
            ("01_50_Genesis_Chapter_Fifty.mp3", 50),
            ("01_21_Genesis_Chapter_Twenty_One.mp3", 21),
            ("09_67_First_Samuel_Chapter_Thirty_One.mp3", 31),
            ("01%200314%20Second%20Kings-Chapter%20One.mp3", 1),
            ("01%200338%20Second%20Kings-Chapter%20Twenty%20Five.mp3", 25),
            ("0479%20Psalms-One.mp3", 1),
            ("0499%20Psalms-Twenty%20One.mp3", 21),
            ("0578%20Psalms-One%20Hundred.mp3", 100),
            ("0597%20Psalms-One%20Hundred%20Nineteen.mp3", 119),
            ("0628%20Psalms-One%20Hundred%20Fifty.mp3", 150),
            ("0549%20Psalms-Seventy%20One%20%281%29.mp3", 71),
            ("0629%20Proverbs-Chapter%20001.mp3", 1),
            ("0659%20Proverbs-Chapter%20031.mp3", 31),
            ("0679%20Song%20of%20Solomon-Chapter%20Eight.mp3", 8),
            ("01%200888%20Obadiah-Chapter%20One.mp3", 1),
            ("0999%20John-Chapter%20Three.mp3", 3),
            ("1017%20John-Chapter%20Twenty%20One.mp3", 21),
            ("01%201132%20Philemon-Chapter%20One.mp3", 1),
            ("01%201165%20Third%20John-Chapter%20One.mp3", 1),
            ("01%201188%20Revelations-Chapter%20Twenty%20Two.mp3", 22),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(WEBAudio.chapterNumber(fromFileName: name), expected, name)
        }
    }

    func testPsalmsListingWithDuplicateMapsAll150() {
        var hrefs = (1...150).map { "\(String(format: "%04d", 478 + $0))%20Psalms-\(words($0)).mp3" }
        hrefs.append("0549%20Psalms-Seventy%20One%20%281%29.mp3")
        let map = WEBAudio.chapterFiles(hrefs: hrefs, chapterCount: 150)
        XCTAssertEqual(map.count, 150)
        XCTAssertEqual(map[71], "0549%20Psalms-Seventy%20One.mp3", "Prefers the file without (1)")
        XCTAssertEqual(map[119], "0597%20Psalms-One%20Hundred%20Nineteen.mp3")
    }

    func testFallsBackToSortedOrder() {
        let hrefs = ["a1.mp3", "a2.mp3", "a3.mp3"]
        XCTAssertEqual(WEBAudio.chapterFiles(hrefs: hrefs, chapterCount: 3), [1: "a1.mp3", 2: "a2.mp3", 3: "a3.mp3"])
        XCTAssertTrue(WEBAudio.chapterFiles(hrefs: hrefs, chapterCount: 4).isEmpty)
    }

    func testListingParsingAndFolders() {
        let html = #"<a href="?C=N;O=D">Name</a> <a href="/eng-web/audio/">Parent</a> <a href="0999%20John-Chapter%20Three.mp3">x</a> <A HREF="1000%20John-Chapter%20Four.MP3">y</A>"#
        XCTAssertEqual(WEBAudio.mp3Links(inListing: html), ["0999%20John-Chapter%20Three.mp3", "1000%20John-Chapter%20Four.MP3"])
        XCTAssertEqual(WEBAudio.folders.count, 66)
        XCTAssertEqual(WEBAudio.folderURL(bookID: "JHN")?.absoluteString, "https://ebible.org/eng-web/audio/43_John/")
        XCTAssertEqual(WEBAudio.folderURL(bookID: "REV")?.absoluteString, "https://ebible.org/eng-web/audio/66_Revelations/")
        XCTAssertNil(WEBAudio.folderURL(bookID: "XYZ"))
    }

    private func words(_ n: Int) -> String {
        let ones = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve",
                    "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"]
        let tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]
        var parts: [String] = []
        var m = n
        if m >= 100 { parts += ["One", "Hundred"]; m -= 100 }
        if m >= 20 { parts.append(tens[m / 10]); m %= 10 }
        if m > 0 { parts.append(ones[m]) }
        return parts.joined(separator: "%20")
    }
}
