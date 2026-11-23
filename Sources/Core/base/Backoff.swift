import Foundation

/// How a screen reads again while it waits on the server (tafs `docs/scale.md`): a slow fallback, never a fixed fast
/// loop. Each wait doubles from `base` up to `ceiling`, with jitter (±`jitter` of it) so many Macs don't read in step, and
/// the reads stop after `reads`. A screen learns of changes by push or the relay where it can; this is what it falls back on.
struct Backoff: Equatable {
    let base: TimeInterval
    let ceiling: TimeInterval
    /// The most reads before it stops.
    let reads: Int
    /// A fraction of each wait, added or taken away at random.
    var jitter: Double = 0.2

    /// The wait before read `n` (from 0), with `random` in 0...1 (the jitter's draw).
    func wait(_ n: Int, random: Double) -> TimeInterval {
        let doubled = base * pow(2, Double(max(0, n)))
        let plain = min(ceiling, doubled)
        let spread = plain * jitter * (random * 2 - 1)
        return max(0, plain + spread)
    }

    /// The wait before read `n`, drawn now.
    func wait(_ n: Int) -> TimeInterval { wait(n, random: Double.random(in: 0...1)) }

    /// An answer being written: soon at first, then less and less often (2 s up to 15 s, 30 reads: about 6 minutes).
    static let answer = Backoff(base: 2, ceiling: 15, reads: 30)
    /// A chat waiting on a connection made elsewhere (4 s up to 30 s, 40 reads: about 18 minutes).
    static let connection = Backoff(base: 4, ceiling: 30, reads: 40)
    /// Coach being started on the phone (10 s up to 2 minutes, 40 reads: about an hour), then it stops; the window's next
    /// open reads it again.
    static let start = Backoff(base: 10, ceiling: 120, reads: 40)
}
