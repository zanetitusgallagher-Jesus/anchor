import Foundation

/// A whole translation, as stored in the bundled `Bibles/<ID>.json` files.
public struct Bible: Codable, Sendable {
    public struct Book: Codable, Sendable, Identifiable {
        /// USFM book code (GEN, EXO, ... REV). Also used by API.Bible.
        public let id: String
        public let name: String
        /// chapters[c-1][v-1] is the text of verse c:v.
        public let chapters: [[String]]
    }

    public let id: String
    public let name: String
    public let books: [Book]

    public func book(_ id: String) -> Book? { books.first { $0.id == id } }

    public func verses(_ ref: ChapterRef) -> [Verse] {
        guard let b = book(ref.bookID), ref.chapter >= 1, ref.chapter <= b.chapters.count else { return [] }
        return b.chapters[ref.chapter - 1].enumerated().compactMap { i, text in
            text.isEmpty ? nil : Verse(ref: VerseRef(bookID: ref.bookID, chapter: ref.chapter, verse: i + 1), text: text)
        }
    }

    public func text(_ ref: VerseRef) -> String? {
        guard let b = book(ref.bookID),
              b.chapters.indices.contains(ref.chapter - 1),
              b.chapters[ref.chapter - 1].indices.contains(ref.verse - 1) else { return nil }
        return b.chapters[ref.chapter - 1][ref.verse - 1]
    }

    public static func decode(_ data: Data) throws -> Bible {
        try JSONDecoder().decode(Bible.self, from: data)
    }
}

public struct Verse: Hashable, Sendable, Identifiable {
    public let ref: VerseRef
    public let text: String
    public var id: VerseRef { ref }
}

public struct ChapterRef: Hashable, Codable, Sendable, CustomStringConvertible {
    public let bookID: String
    public let chapter: Int
    public init(bookID: String, chapter: Int) {
        self.bookID = bookID
        self.chapter = chapter
    }
    public var description: String { "\(BookCatalog.name(bookID)) \(chapter)" }
    /// API.Bible passage id, e.g. "JHN.3".
    public var apiBibleID: String { "\(bookID).\(chapter)" }
}

public struct VerseRef: Hashable, Codable, Sendable, CustomStringConvertible, Comparable {
    public let bookID: String
    public let chapter: Int
    public let verse: Int
    public init(bookID: String, chapter: Int, verse: Int) {
        self.bookID = bookID
        self.chapter = chapter
        self.verse = verse
    }
    public var description: String { "\(BookCatalog.name(bookID)) \(chapter):\(verse)" }

    public static func < (a: VerseRef, b: VerseRef) -> Bool {
        (BookCatalog.order(a.bookID), a.chapter, a.verse) < (BookCatalog.order(b.bookID), b.chapter, b.verse)
    }
}

/// Canonical book list with chapter counts (Protestant 66-book canon).
public enum BookCatalog {
    public struct Entry: Sendable {
        public let id: String
        public let name: String
        public let chapters: Int
        public var isNewTestament: Bool { BookCatalog.order(id) >= 39 }
    }

    public static let all: [Entry] = [
        ("GEN","Genesis",50),("EXO","Exodus",40),("LEV","Leviticus",27),("NUM","Numbers",36),("DEU","Deuteronomy",34),
        ("JOS","Joshua",24),("JDG","Judges",21),("RUT","Ruth",4),("1SA","1 Samuel",31),("2SA","2 Samuel",24),
        ("1KI","1 Kings",22),("2KI","2 Kings",25),("1CH","1 Chronicles",29),("2CH","2 Chronicles",36),("EZR","Ezra",10),
        ("NEH","Nehemiah",13),("EST","Esther",10),("JOB","Job",42),("PSA","Psalms",150),("PRO","Proverbs",31),
        ("ECC","Ecclesiastes",12),("SNG","Song of Solomon",8),("ISA","Isaiah",66),("JER","Jeremiah",52),
        ("LAM","Lamentations",5),("EZK","Ezekiel",48),("DAN","Daniel",12),("HOS","Hosea",14),("JOL","Joel",3),
        ("AMO","Amos",9),("OBA","Obadiah",1),("JON","Jonah",4),("MIC","Micah",7),("NAM","Nahum",3),
        ("HAB","Habakkuk",3),("ZEP","Zephaniah",3),("HAG","Haggai",2),("ZEC","Zechariah",14),("MAL","Malachi",4),
        ("MAT","Matthew",28),("MRK","Mark",16),("LUK","Luke",24),("JHN","John",21),("ACT","Acts",28),("ROM","Romans",16),
        ("1CO","1 Corinthians",16),("2CO","2 Corinthians",13),("GAL","Galatians",6),("EPH","Ephesians",6),
        ("PHP","Philippians",4),("COL","Colossians",4),("1TH","1 Thessalonians",5),("2TH","2 Thessalonians",3),
        ("1TI","1 Timothy",6),("2TI","2 Timothy",4),("TIT","Titus",3),("PHM","Philemon",1),("HEB","Hebrews",13),
        ("JAS","James",5),("1PE","1 Peter",5),("2PE","2 Peter",3),("1JN","1 John",5),("2JN","2 John",1),
        ("3JN","3 John",1),("JUD","Jude",1),("REV","Revelation",22),
    ].map { Entry(id: $0.0, name: $0.1, chapters: $0.2) }

    private static let index: [String: Int] = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1.id, $0) })

    public static func order(_ id: String) -> Int { index[id] ?? Int.max }
    public static func entry(_ id: String) -> Entry? { index[id].map { all[$0] } }
    public static func name(_ id: String) -> String { entry(id)?.name ?? id }

    public static func chapters(of ids: [String]) -> [ChapterRef] {
        ids.compactMap(entry).flatMap { e in (1...e.chapters).map { ChapterRef(bookID: e.id, chapter: $0) } }
    }
}
