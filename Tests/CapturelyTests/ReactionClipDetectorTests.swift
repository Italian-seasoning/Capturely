import Testing
@testable import Capturely

@Test func reactionClipsRequireFreshMicCrossingAndRespectCooldown() {
    var detector = ReactionClipDetector()
    func sample(_ level: Double, _ time: Double, eligible: Bool = true) -> Bool {
        detector.shouldClip(level: level, sampledAt: time, now: time, threshold: 0.4, cooldown: 30, eligible: eligible)
    }
    #expect(!sample(0.1, 1))
    #expect(sample(0.7, 2))
    #expect(!sample(0.8, 3))
    #expect(!sample(0.1, 4))
    #expect(!sample(0.8, 5))
    #expect(!sample(0.1, 32))
    #expect(sample(0.8, 33))
    #expect(!sample(0.8, 33))
    #expect(!sample(0.9, 65, eligible: false))
    let stale = detector.shouldClip(level: 1, sampledAt: 66, now: 70, threshold: 0.4, cooldown: 30, eligible: true)
    #expect(!stale)
}
