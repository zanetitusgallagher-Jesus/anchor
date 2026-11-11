import AnchorCore
import Foundation
import Observation

/// Loads the bundled public-domain translations on demand (each is ~4 MB of JSON).
@MainActor
@Observable
final class BibleStore {
    static let bundled: [(id: String, name: String)] = [
        ("WEB", "World English Bible"),
        ("KJV", "King James Version"),
    ]

    private var cache: [String: Bible] = [:]

    func bible(_ id: String) -> Bible? {
        let id = Self.bundled.contains { $0.id == id } ? id : "WEB"
        if let b = cache[id] { return b }
        guard let url = Self.resourceURL(id, subdirectory: "Bibles"),
              let data = try? Data(contentsOf: url),
              let b = try? Bible.decode(data) else {
            NSLog("Anchor: could not load bundled Bible \(id)")
            return nil
        }
        cache[id] = b
        return b
    }

    static func resourceURL(_ name: String, subdirectory: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: "json")
    }
}

/// Seed plans from `Resources/Plans` plus the user's custom plans.
@MainActor
@Observable
final class PlanStore {
    static let seedIDs = ["bible-in-a-year", "nt-90", "psalms-proverbs", "gospels-45", "verse-a-day"]

    private(set) var seedPlans: [ReadingPlan] = []

    init() {
        let decoder = JSONDecoder()
        seedPlans = Self.seedIDs.compactMap { id in
            guard let url = BibleStore.resourceURL(id, subdirectory: "Plans"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ReadingPlan.self, from: data)
        }
    }

    @ObservationIgnored private var generated: [String: ReadingPlan] = [:]

    /// - Parameter structure: a translation used for verse counts (always KJV,
    ///   so a shuffled plan never changes when the reading translation does).
    func plan(id: String, custom: [CustomPlanRecord], bible: Bible?, structure: Bible? = nil) -> ReadingPlan? {
        if let p = seedPlans.first(where: { $0.id == id }) { return p }
        if let seed = ReadingPlanGenerator.seed(fromShuffledID: id), let structure {
            if let cached = generated[id] { return cached }
            let p = ReadingPlanGenerator.shuffledWholeBible(verseCounts: ReadingPlanGenerator.verseCounts(of: structure), seed: seed)
            generated[id] = p
            return p
        }
        if let c = custom.first(where: { $0.planID == id }) {
            return ReadingPlanGenerator.custom(id: c.planID, name: c.name, bookIDs: c.bookIDs, days: c.days, bible: bible)
        }
        return seedPlans.first
    }
}
