import Foundation

public enum JournalTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case soap, gratitude, prayer, freeWrite
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .soap: "SOAP"
        case .gratitude: "Gratitude"
        case .prayer: "Prayer list"
        case .freeWrite: "Free write"
        }
    }

    public var fields: [JournalField] {
        switch self {
        case .soap: [.scripture, .observation, .application, .prayer]
        case .gratitude: [.gratitude1, .gratitude2, .gratitude3]
        case .prayer: [.prayerNotes]
        case .freeWrite: []
        }
    }
}

public enum JournalField: String, Codable, CaseIterable, Sendable {
    case scripture, observation, application, prayer
    case gratitude1, gratitude2, gratitude3
    case prayerNotes

    public var title: String {
        switch self {
        case .scripture: "Scripture"
        case .observation: "Observation"
        case .application: "Application"
        case .prayer: "Prayer"
        case .gratitude1: "1."
        case .gratitude2: "2."
        case .gratitude3: "3."
        case .prayerNotes: "Notes"
        }
    }

    public var placeholder: String {
        switch self {
        case .scripture: "Copy the verse that stood out to you."
        case .observation: "What is happening? What do you notice?"
        case .application: "How does this change today?"
        case .prayer: "Talk to God about it."
        case .gratitude1, .gratitude2, .gratitude3: "Something specific you're grateful for…"
        case .prayerNotes: "Anything else on your heart."
        }
    }
}

/// The plaintext body of a journal entry. The app encrypts this whole value
/// (as JSON) before it touches disk.
public struct JournalBody: Codable, Equatable, Sendable {
    public var fields: [JournalField: String]
    /// Free-write body as Markdown-ish plain text (rich text is kept separately as RTF).
    public var text: String

    public init(fields: [JournalField: String] = [:], text: String = "") {
        self.fields = fields
        self.text = text
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fields.values.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// A decrypted snapshot of an entry, as used by export and search.
public struct JournalSnapshot: Sendable {
    public var date: Date
    public var template: JournalTemplate
    public var body: JournalBody
    public var tags: [String]
    public var mood: Int?
    public var passage: String?

    public init(date: Date, template: JournalTemplate, body: JournalBody, tags: [String], mood: Int?, passage: String?) {
        self.date = date
        self.template = template
        self.body = body
        self.tags = tags
        self.mood = mood
        self.passage = passage
    }
}

public enum Tags {
    /// "Faith, #hope  , faith" -> ["faith", "hope"]
    public static func parse(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

public enum JournalSearch {
    public struct Query: Sendable {
        public var text = ""
        public var tag: String?
        public var bookID: String?
        public var from: Date?
        public var to: Date?
        public init(text: String = "", tag: String? = nil, bookID: String? = nil, from: Date? = nil, to: Date? = nil) {
            self.text = text
            self.tag = tag
            self.bookID = bookID
            self.from = from
            self.to = to
        }
    }

    public static func matches(_ e: JournalSnapshot, _ q: Query) -> Bool {
        if let tag = q.tag, !e.tags.contains(tag.lowercased()) { return false }
        if let from = q.from, e.date < from { return false }
        if let to = q.to, e.date > to { return false }
        if let book = q.bookID {
            let name = BookCatalog.name(book)
            guard let p = e.passage, p.hasPrefix(name) else { return false }
        }
        let needle = q.text.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            let haystack = ([e.body.text, e.passage ?? ""] + e.body.fields.values + e.tags).joined(separator: "\n")
            if haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return false }
        }
        return true
    }
}

public enum JournalExporter {
    public static func markdown(_ entries: [JournalSnapshot], calendar: Calendar = .current) -> String {
        let df = DateFormatter()
        df.calendar = calendar
        df.timeZone = calendar.timeZone
        df.dateStyle = .full
        df.timeStyle = .short
        df.locale = Locale(identifier: "en_US_POSIX")
        df.setLocalizedDateFormatFromTemplate("EEEE, MMMM d, yyyy h:mm a")

        var out = "# Anchor Journal\n"
        for e in entries.sorted(by: { $0.date < $1.date }) {
            out += "\n---\n\n## \(df.string(from: e.date)) — \(e.template.title)\n\n"
            var meta: [String] = []
            if let p = e.passage { meta.append("**Passage:** \(p)") }
            if let m = e.mood { meta.append("**Mood:** \(m)/5") }
            if !e.tags.isEmpty { meta.append("**Tags:** " + e.tags.map { "#\($0)" }.joined(separator: " ")) }
            if !meta.isEmpty { out += meta.joined(separator: "  \n") + "\n\n" }
            for f in e.template.fields {
                let v = e.body.fields[f]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !v.isEmpty else { continue }
                if e.template == .gratitude {
                    out += "\(f.title) \(v)\n"
                } else {
                    out += "### \(f.title)\n\n\(v)\n\n"
                }
            }
            if e.template == .gratitude { out += "\n" }
            let t = e.body.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out += t + "\n\n" }
        }
        return out
    }
}
