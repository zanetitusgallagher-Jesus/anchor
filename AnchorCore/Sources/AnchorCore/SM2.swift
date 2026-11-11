import Foundation

/// Spaced-repetition state for one memory verse, scheduled with the SM-2
/// algorithm (Wozniak, 1990).
public struct SM2State: Codable, Equatable, Sendable {
    /// Consecutive successful reviews (quality >= 3).
    public var repetitions: Int
    /// Days until the next review.
    public var interval: Int
    /// Ease factor; never below 1.3.
    public var easeFactor: Double
    /// The day the card is next due.
    public var due: DayKey

    public static let initialEase = 2.5
    public static let minimumEase = 1.3

    public init(repetitions: Int = 0, interval: Int = 0, easeFactor: Double = SM2State.initialEase, due: DayKey) {
        self.repetitions = repetitions
        self.interval = interval
        self.easeFactor = easeFactor
        self.due = due
    }

    /// A new card is due the day it is added.
    public static func new(on day: DayKey) -> SM2State {
        SM2State(due: day)
    }

    public func isDue(on day: DayKey) -> Bool { due <= day }

    /// A verse counts as "memorized" once it survives a three-week interval.
    public var isMemorized: Bool { interval >= 21 }
}

public enum SM2 {
    /// Applies one review.
    ///
    /// - Parameter quality: 0 (blackout) ... 5 (perfect recall).
    ///
    /// Follows the original SM-2 description:
    /// * quality < 3: repetitions restart (I(1) = 1 day) and the ease factor
    ///   is left unchanged.
    /// * quality >= 3: I(1) = 1, I(2) = 6, I(n) = round(I(n-1) * EF), then
    ///   EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)), floored at 1.3.
    public static func review(_ state: SM2State, quality rawQuality: Int, on day: DayKey, calendar: Calendar = .current) -> SM2State {
        let q = min(5, max(0, rawQuality))
        var next = state

        if q < 3 {
            next.repetitions = 0
            next.interval = 1
        } else {
            switch state.repetitions {
            case 0: next.interval = 1
            case 1: next.interval = 6
            default: next.interval = Int((Double(state.interval) * state.easeFactor).rounded())
            }
            next.repetitions = state.repetitions + 1
            let delta = 0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02)
            next.easeFactor = max(SM2State.minimumEase, state.easeFactor + delta)
        }

        next.due = day.adding(days: next.interval, calendar: calendar)
        return next
    }

    /// SM-2 step 7: within one session, items graded below 4 are repeated
    /// until they reach 4. The app re-queues such cards (without rescheduling
    /// them a second time).
    public static func needsRepeatInSession(quality: Int) -> Bool { quality < 4 }
}
