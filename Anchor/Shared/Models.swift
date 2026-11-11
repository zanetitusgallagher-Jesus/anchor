import Foundation
import AnchorCore
import SwiftData

// SwiftData models. Anything personal (journal text, prayers, reflections,
// rewire answers) is stored only as AES-GCM ciphertext; see JournalCrypto.

@Model
final class DailySession {
    @Attribute(.unique) var dayKey: String
    var startedAt: Date
    var completedAt: Date?
    var readingSeconds: Double = 0
    var passage: String?
    var reflectionPrompt: String?
    /// Encrypted `ReflectionRecord`.
    var reflectionCipher: Data?
    var stepsCompleted: [String] = []

    init(dayKey: String, startedAt: Date = .now) {
        self.dayKey = dayKey
        self.startedAt = startedAt
    }
}

/// Every emergency unlock, failsafe release and Shift safe-launch is logged here.
@Model
final class UnlockEvent {
    var date: Date
    var dayKey: String
    /// "emergency", "failsafe" or "safeLaunch".
    var kind: String
    var reason: String?

    init(date: Date = .now, dayKey: String, kind: String, reason: String? = nil) {
        self.date = date
        self.dayKey = dayKey
        self.kind = kind
        self.reason = reason
    }
}

@Model
final class JournalEntry {
    var id: UUID = UUID()
    var createdAt: Date
    var updatedAt: Date
    var dayKey: String
    var templateRaw: String
    /// Encrypted `JournalPayload` (body, tags, mood, passage).
    var payloadCipher: Data
    /// Encrypted RTF for free-write entries.
    var richTextCipher: Data?

    init(createdAt: Date = .now, dayKey: String, templateRaw: String, payloadCipher: Data, richTextCipher: Data? = nil) {
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.dayKey = dayKey
        self.templateRaw = templateRaw
        self.payloadCipher = payloadCipher
        self.richTextCipher = richTextCipher
    }
}

@Model
final class MemoryVerse {
    var id: UUID = UUID()
    var bookID: String
    var chapter: Int
    var verse: Int
    var translationID: String
    var text: String
    var addedAt: Date
    var lastReviewedAt: Date?
    // SM-2 state
    var repetitions: Int = 0
    var interval: Int = 0
    var easeFactor: Double = 2.5
    var dueKey: String

    init(bookID: String, chapter: Int, verse: Int, translationID: String, text: String, today: String) {
        self.bookID = bookID
        self.chapter = chapter
        self.verse = verse
        self.translationID = translationID
        self.text = text
        self.addedAt = .now
        self.dueKey = today
    }
}

@Model
final class PrayerRequest {
    var id: UUID = UUID()
    var createdAt: Date
    /// Encrypted `PrayerPayload`.
    var cipher: Data
    var answeredAt: Date?

    init(createdAt: Date = .now, cipher: Data) {
        self.createdAt = createdAt
        self.cipher = cipher
    }
}

@Model
final class RewireEntry {
    var id: UUID = UUID()
    var date: Date
    var dayKey: String
    var kindRaw: String
    /// Encrypted `[String: String]` of the exercise's answers.
    var cipher: Data

    init(date: Date = .now, dayKey: String, kindRaw: String, cipher: Data) {
        self.date = date
        self.dayKey = dayKey
        self.kindRaw = kindRaw
        self.cipher = cipher
    }
}

@Model
final class PlanProgressRecord {
    @Attribute(.unique) var planID: String
    var startedAt: Date
    var completedDays: [Int] = []
    /// When each plan day was finished, parallel to `completedDays`.
    var completedDates: [Date] = []

    init(planID: String, startedAt: Date = .now) {
        self.planID = planID
        self.startedAt = startedAt
    }
}

@Model
final class CustomPlanRecord {
    @Attribute(.unique) var planID: String
    var name: String
    var bookIDs: [String]
    var days: Int

    init(planID: String, name: String, bookIDs: [String], days: Int) {
        self.planID = planID
        self.name = name
        self.bookIDs = bookIDs
        self.days = days
    }
}

enum AnchorSchema {
    static let models: [any PersistentModel.Type] = [
        DailySession.self, UnlockEvent.self, JournalEntry.self, MemoryVerse.self,
        PrayerRequest.self, RewireEntry.self, PlanProgressRecord.self, CustomPlanRecord.self,
    ]

    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration("Anchor", schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not open Anchor's data store: \(error)")
        }
    }
}

// MARK: - Plaintext payloads (only ever stored encrypted)

struct JournalPayload: Codable, Equatable {
    var body: JournalBody
    var tags: [String]
    var mood: Int?
    var passage: String?
    var bookID: String?
}

struct ReflectionRecord: Codable {
    var prompt: String
    var answer: String
    var aiQuestions: [String] = []
    var aiAnswers: [String] = []
    var aiFeedback: String?
}

struct PrayerPayload: Codable {
    var title: String
    var details: String
    var answerNote: String?
}
