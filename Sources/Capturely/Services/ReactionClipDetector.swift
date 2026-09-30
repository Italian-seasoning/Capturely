import Foundation

struct ReactionClipDetector {
    private var lastSample: TimeInterval = 0
    private var lastTrigger = -Double.greatestFiniteMagnitude
    private var wasLoud = false

    mutating func shouldClip(level: Double, sampledAt: TimeInterval, now: TimeInterval,
                             threshold: Double, cooldown: TimeInterval, eligible: Bool) -> Bool {
        guard eligible, level.isFinite, sampledAt > 0, now - sampledAt < 1.5 else {
            wasLoud = false
            return false
        }
        guard sampledAt > lastSample else { return false }
        lastSample = sampledAt
        let loud = level >= threshold
        defer { wasLoud = loud }
        guard loud, !wasLoud, now - lastTrigger >= cooldown else { return false }
        lastTrigger = now
        return true
    }
}
