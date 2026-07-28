import Foundation

/// User-tunable scheduling parameters.
struct ScheduleConfig: Equatable {
    var tapsPerHour: Int = 4
    var minGap: TimeInterval = 600          // 10 minutes
    var debugFastHour: Bool = false         // compress the "hour" to 60s for fast testing

    var hourLength: TimeInterval { debugFastHour ? 60 : 3600 }

    /// One stratification bucket — the slice of the hour each tap is drawn from.
    var bucket: TimeInterval { hourLength / Double(max(1, tapsPerHour)) }

    /// Minimum gap scaled to the (possibly compressed) hour, so the 60-second debug
    /// mode stays meaningful instead of collapsing every tap onto the 5-minute floor.
    ///
    /// Capped just under one bucket: a gap at or above the bucket size would clamp
    /// every draw to the floor, turning the schedule into a deterministic ladder
    /// (and, once `tapsPerHour × gap > 1 hour`, pushing taps past the session's
    /// expiry entirely). The cap keeps the randomness that is the whole point.
    var effectiveMinGap: TimeInterval {
        min(minGap * (hourLength / 3600), bucket * 0.9)
    }
}

/// Stratified-random tap scheduler.
///
/// The hour is divided into `tapsPerHour` equal buckets and one moment is drawn
/// inside each, enforcing `effectiveMinGap` between consecutive taps. Uniform
/// sampling across the whole hour clusters badly (two taps seconds apart, then long
/// silence, reads as a malfunction); stratification keeps each tap unpredictable
/// while keeping the spacing usable.
///
/// Buckets are anchored to `epoch` — the moment the session started — not to the
/// clock hour. A session lasts exactly one hour, so anchoring this way guarantees
/// all `tapsPerHour` taps fall inside it; clock-hour anchoring would strand taps
/// past the session's expiry and produce long silences.
///
/// Generation is forward-only and lazy: the current hour is cached and regenerated
/// only when time crosses into the next one, so each hour is drawn fresh and the
/// schedule never cycles. Generic over the RNG so tests can inject a seeded
/// generator; the app uses `SystemRandomNumberGenerator`.
final class Scheduler<R: RandomNumberGenerator> {
    var config: ScheduleConfig
    private var rng: R
    private let epoch: Date

    private var genHourIndex: Int?
    private var genFires: [Date] = []
    private var prevFire: Date?            // last fire generated, for cross-bucket min-gap

    init(config: ScheduleConfig, rng: R, epoch: Date = Date()) {
        self.config = config
        self.rng = rng
        self.epoch = epoch
        // The start moment counts as a virtual "previous fire", so the minimum gap
        // applies to the first tap too. Without this the first draw could land
        // instantly and blur into the ascending "started" confirmation haptic.
        self.prevFire = epoch
    }

    /// The next tap strictly after `now`, or nil if the config admits no taps.
    func nextFire(after now: Date) -> Date? {
        guard config.tapsPerHour >= 1 else { return nil }
        var index = max(0, Int((now.timeIntervalSince(epoch) / config.hourLength).rounded(.down)))
        for _ in 0..<1000 {                 // safety bound
            if genHourIndex != index { generate(hourIndex: index) }
            if let fire = genFires.first(where: { $0 > now }) { return fire }
            index += 1
        }
        return nil
    }

    // MARK: - Generation

    private func generate(hourIndex index: Int) {
        let bucket = config.bucket
        let hourStart = epoch.addingTimeInterval(Double(index) * config.hourLength)
        var fires: [Date] = []
        var previous = prevFire
        let gap = config.effectiveMinGap
        for i in 0..<config.tapsPerHour {
            let bucketStart = hourStart.addingTimeInterval(Double(i) * bucket)
            let bucketEnd = bucketStart.addingTimeInterval(bucket)

            // Draw inside the part of the bucket the minimum gap actually allows,
            // instead of drawing anywhere and clamping. Clamping piles probability
            // onto the floor itself: with a 10-minute gap in a 15-minute bucket,
            // two-thirds of draws would land on *exactly* the floor, so the tap
            // would arrive a predictable 10 minutes after the previous one — which
            // defeats the entire point of the app.
            let lower = max(bucketStart, previous?.addingTimeInterval(gap) ?? bucketStart)
            let t: Date
            if bucketEnd > lower {
                let span = bucketEnd.timeIntervalSince(lower)
                t = lower.addingTimeInterval(Double.random(in: 0..<span, using: &rng))
            } else {
                t = lower       // the gap consumed the whole bucket; fall back to the floor
            }
            fires.append(t)
            previous = t
        }
        genHourIndex = index
        genFires = fires
        prevFire = fires.last ?? prevFire
    }
}
