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
    static let seedIDs = ["bible-in-a-year", "nt-90", "psalms-proverbs", "gospels-45"]

    private(set) var seedPlans: [ReadingPlan] = []

    init() {
        let decoder = JSONDecoder()
        seedPlans = Self.seedIDs.compactMap { id in
            guard let url = BibleStore.resourceURL(id, subdirectory: "Plans"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ReadingPlan.self, from: data)
        }
    }

    func plan(id: String, custom: [CustomPlanRecord], bible: Bible?) -> ReadingPlan? {
        if let p = seedPlans.first(where: { $0.id == id }) { return p }
        if let c = custom.first(where: { $0.planID == id }) {
            return ReadingPlanGenerator.custom(id: c.planID, name: c.name, bookIDs: c.bookIDs, days: c.days, bible: bible)
        }
        return seedPlans.first
    }
}
