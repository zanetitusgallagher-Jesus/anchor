import Foundation

/// Cuts a passage (some verses of a chapter) out of a whole-chapter recording.
///
/// The recordings have no verse timestamps, so:
/// 1. each verse's position is estimated from the length of its text (a
///    narrator's pace is steady within a chapter, and the recording opens by
///    announcing the book and chapter);
/// 2. each cut is moved to the nearest pause in the audio, so no word is cut
///    off, leaning earlier for the start and later for the end, so the
///    passage is never clipped.
public enum NarrationTiming {
    public enum Lean: Sendable { case earlier, later }

    /// Where each verse starts, as a fraction (0..<1) of the recording.
    /// `introCharacters` stands in for the spoken "John, chapter three."
    public static func verseStartFractions(verseLengths: [Int], introCharacters: Int = 24) -> [Double] {
        let weights = verseLengths.map { Double(max(1, $0)) + 6 } // +6: the pause after each verse
        let total = Double(introCharacters) + weights.reduce(0, +)
        guard total > 0 else { return [] }
        var at = Double(introCharacters)
        return weights.map { w in
            defer { at += w }
            return at / total
        }
    }

    /// Estimated start and end (seconds) of verses `start...end` (1-based; nil = chapter start / end).
    public static func estimate(verseLengths: [Int], start: Int?, end: Int?, duration: Double,
                                introCharacters: Int = 24) -> (start: Double, end: Double) {
        let f = verseStartFractions(verseLengths: verseLengths, introCharacters: introCharacters)
        guard !f.isEmpty, duration > 0 else { return (0, duration) }
        let s = start.map { min(max($0, 1), f.count) } ?? 1
        let from = s <= 1 ? 0 : f[s - 1] * duration
        let to: Double
        if let e = end, e < f.count { to = f[e] * duration } else { to = duration }
        return (from, max(from, to))
    }

    /// The pause to cut at: the middle of the quiet stretch nearest `target`.
    /// - Parameters:
    ///   - levels: loudness (RMS) of consecutive windows of `step` seconds, the first starting at `offset`.
    ///   - maxShift: never move the cut further than this.
    public static func snapToPause(levels: [Float], step: Double, offset: Double, target: Double,
                                   lean: Lean, maxShift: Double = 6, minPause: Double = 0.25) -> Double {
        guard levels.count > 4 else { return target }
        let sorted = levels.sorted()
        // Pauses can be a small share of a recording, so take the noise floor from the quietest 2%.
        let floor = sorted[sorted.count / 50]
        let median = sorted[sorted.count / 2]
        guard median > floor else { return target }
        let threshold = floor + (median - floor) * 0.2

        // Quiet runs long enough to be a pause between verses.
        var pauses: [Double] = []
        var runStart: Int?
        for i in 0...levels.count {
            let quiet = i < levels.count && levels[i] <= threshold
            if quiet, runStart == nil { runStart = i }
            if !quiet, let r = runStart {
                if Double(i - r) * step >= minPause {
                    pauses.append(offset + (Double(r) + Double(i - r) / 2) * step)
                }
                runStart = nil
            }
        }
        let near = pauses.filter { abs($0 - target) <= maxShift }
        guard !near.isEmpty else { return target }
        // Lean so the passage is never clipped: a little early for the start, a little late for the end.
        let slack = 0.75
        let preferred = near.filter { lean == .earlier ? $0 <= target + slack : $0 >= target - slack }
        let pool = preferred.isEmpty ? near : preferred
        return pool.min { abs($0 - target) < abs($1 - target) }!
    }

    /// Which verse (1-based index into `verseLengths`) is being read at `time`.
    public static func verseIndex(at time: Double, duration: Double, verseLengths: [Int], introCharacters: Int = 24) -> Int? {
        let f = verseStartFractions(verseLengths: verseLengths, introCharacters: introCharacters)
        guard duration > 0, let first = f.first, time >= first * duration else { return nil }
        let x = time / duration
        return (f.lastIndex { $0 <= x } ?? 0) + 1
    }
}
