import Foundation
import Testing
@testable import ZeusCore

@Suite struct BoostScheduleTests {
    @Test func aShorterBoostDoesNotCutALongerOne() {
        var schedule = BoostSchedule()
        let long = schedule.boost(now: 0, seconds: 5)
        let kept = schedule.boost(now: 0, seconds: 1)
        #expect(long == 5)
        #expect(kept == 5)
        #expect(schedule.stillBoosted(at: 2))
        #expect(schedule.stillBoosted(at: 5) == false)
    }

    @Test func aLongerBoostExtendsTheDeadline() {
        var schedule = BoostSchedule()
        _ = schedule.boost(now: 0, seconds: 1)
        let kept = schedule.boost(now: 0.5, seconds: 4)
        #expect(kept == 4.5)
        #expect(schedule.stillBoosted(at: 4))
    }

    @Test func randomBoostsKeepTheFurthestDeadline() {
        var rng = BoostSplitMix(state: 0xB0057)
        for _ in 0..<200 {
            var schedule = BoostSchedule()
            var furthest = 0.0
            var now = 0.0
            for _ in 0..<Int(rng.next() % 6) + 1 {
                let seconds = Double(rng.next() % 10)
                let kept = schedule.boost(now: now, seconds: seconds)
                furthest = max(furthest, now + seconds)
                #expect(kept == furthest)
                now += 0.25
            }
        }
    }

    @Test func stressManyShortBoostsDoNotEraseALongOne() {
        var schedule = BoostSchedule()
        _ = schedule.boost(now: 0, seconds: 30)
        for index in 0..<100 {
            _ = schedule.boost(now: Double(index) * 0.01, seconds: 0.2)
        }
        #expect(schedule.stillBoosted(at: 10))
        #expect(schedule.deadline == 30)
    }
}

struct BoostSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
