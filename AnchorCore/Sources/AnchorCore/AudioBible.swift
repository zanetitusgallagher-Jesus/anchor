import Foundation

/// The human-narrated World English Bible from eBible.org (public domain),
/// one MP3 per chapter over HTTPS.
///
/// The files are named inconsistently from book to book, for example:
///   01_01_Genesis_Chapter_One.mp3
///   0999 John-Chapter Three.mp3
///   0499 Psalms-Twenty One.mp3            (no "Chapter")
///   0629 Proverbs-Chapter 001.mp3         (digits)
///   01 1167 Revelations-Chapter One.mp3   (sequence number off by one)
///   0549 Psalms-Seventy One (1).mp3       (duplicate)
/// so Anchor never guesses a file name. It reads each book's folder listing
/// and works out the chapter from the end of each name.
public enum WEBAudio {
    public static let base = URL(string: "https://ebible.org/eng-web/audio/")!

    /// Folder for each book, in canonical order (exactly as listed on eBible.org).
    public static let folders: [String] = [
        "01_Genesis", "02_Exodus", "03_Leviticus", "04_Numbers", "05_Deuteronomy", "06_Joshua", "07_Judges",
        "08_Ruth", "09_First_Samuel", "10_Second_Samuel", "11_First_Kings", "12_Second_Kings",
        "13_First_Chronicles", "14_Second_Chronicles", "15_Ezra", "16_Nehemiah", "17_Esther", "18_Job",
        "19_Psalms", "20_Proverbs", "21_Ecclesiastes", "22_Song_of_Solomon", "23_Isaiah", "24_Jeremiah",
        "25_Lamentations", "26_Ezekiel", "27_Daniel", "28_Hosea", "29_Joel", "30_Amos", "31_Obadiah",
        "32_Jonah", "33_Micah", "34_Nahum", "35_Habakkuk", "36_Zephaniah", "37_Haggai", "38_Zechariah",
        "39_Malachi", "40_Matthew", "41_Mark", "42_Luke", "43_John", "44_Acts", "45_Romans",
        "46_First_Corinthians", "47_Second_Corinthians", "48_Galatians", "49_Ephesians", "50_Philippians",
        "51_Colossians", "52_First_Thessalonians", "53_Second_Thessalonians", "54_First_Timothy",
        "55_Second_Timothy", "56_Titus", "57_Philemon", "58_Hebrews", "59_James", "60_First_Peter",
        "61_Second_Peter", "62_First_John", "63_Second_John", "64_Third_John", "65_Jude", "66_Revelations",
    ]

    /// The folder listing URL for a book (USFM id), e.g. https://ebible.org/eng-web/audio/43_John/
    public static func folderURL(bookID: String) -> URL? {
        let i = BookCatalog.order(bookID)
        guard folders.indices.contains(i) else { return nil }
        return base.appendingPathComponent(folders[i], isDirectory: true)
    }

    /// MP3 links in an Apache-style directory listing (hrefs as written, still percent-encoded).
    public static func mp3Links(inListing html: String) -> [String] {
        var out: [String] = []
        var rest = html[...]
        while let r = rest.range(of: "href=\"", options: .caseInsensitive) {
            let after = rest[r.upperBound...]
            guard let end = after.firstIndex(of: "\"") else { break }
            let href = String(after[..<end])
            if href.lowercased().hasSuffix(".mp3") { out.append(href) }
            rest = after[end...]
        }
        return out
    }

    /// Maps chapter number -> href for a book's listing. Uses the chapter written
    /// at the end of each name; if that doesn't account for every chapter
    /// exactly once, falls back to sorted order (when the count matches).
    public static func chapterFiles(hrefs: [String], chapterCount: Int) -> [Int: String] {
        var byChapter: [Int: String] = [:]
        // Prefer names without a "(1)"-style duplicate marker.
        let ordered = hrefs.sorted { isDuplicate($0) == isDuplicate($1) ? $0 < $1 : !isDuplicate($0) }
        for href in ordered {
            guard let c = chapterNumber(fromFileName: href), (1...chapterCount).contains(c) else { continue }
            if byChapter[c] == nil { byChapter[c] = href }
        }
        if byChapter.count == chapterCount { return byChapter }

        let unique = hrefs.filter { !isDuplicate($0) }.sorted()
        if unique.count == chapterCount {
            return Dictionary(uniqueKeysWithValues: unique.enumerated().map { ($0.offset + 1, $0.element) })
        }
        return byChapter
    }

    static func isDuplicate(_ href: String) -> Bool {
        let name = href.removingPercentEncoding ?? href
        return name.range(of: #"\(\d+\)\.mp3$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "0999%20John-Chapter%20Three.mp3" -> 3, "01_21_Genesis_Chapter_Twenty_One.mp3" -> 21,
    /// "0628 Psalms-One Hundred Fifty.mp3" -> 150, "0629 Proverbs-Chapter 001.mp3" -> 1.
    public static func chapterNumber(fromFileName href: String) -> Int? {
        var name = (href.removingPercentEncoding ?? href)
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        if name.lowercased().hasSuffix(".mp3") { name = String(name.dropLast(4)) }
        name = name.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)

        let tokens = name.split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" }).map { $0.lowercased() }
        // Collect the run of number words / digits at the end of the name.
        var tail: [String] = []
        for t in tokens.reversed() {
            if numberWords[t] != nil || t == "hundred" || (t.allSatisfy(\.isNumber) && tail.isEmpty) {
                tail.insert(t, at: 0)
                if t.allSatisfy(\.isNumber) { break }
            } else {
                break
            }
        }
        guard !tail.isEmpty else { return nil }
        if tail.count == 1, let n = Int(tail[0]) { return n }

        var total = 0
        for t in tail {
            if t == "hundred" { total = max(total, 1) * 100 }
            else if let v = numberWords[t] { total += v }
            else { return nil }
        }
        return total > 0 ? total : nil
    }

    static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
        "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
}
