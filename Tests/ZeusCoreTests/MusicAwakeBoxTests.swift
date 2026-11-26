import Foundation
import Testing
@testable import ZeusCore

@Suite("Music awake box")
struct MusicAwakeBoxTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func decide(enabled: Bool = true, isPlaying: Bool = true, lastPlayedAt: Date? = nil,
                        grace: TimeInterval = 20,
                        power: MusicAwakeBox.PowerStop = .clear) -> MusicAwakeBox.Verdict {
        MusicAwakeBox.decide(enabled: enabled, isPlaying: isPlaying, lastPlayedAt: lastPlayedAt,
                             now: now, grace: grace, power: power)
    }

    @Test func theShippedGraceLeaseAndRenewal() {
        #expect(MusicAwakeBox.defaultGrace == 20)
        #expect(MusicAwakeBox.lease == 120)
        #expect(MusicAwakeBox.renewEvery == 60)
        #expect(MusicAwakeBox.renewTolerance == 10)
        #expect(MusicAwakeBox.margin == 5)
    }

    @Test func offWinsBeforeSilenceAndBeforeAPowerStop() {
        #expect(decide(enabled: false) == .release(.off))
        #expect(decide(enabled: false, isPlaying: false, lastPlayedAt: now, power: .tooHot) == .release(.off))
        #expect(decide(enabled: false, power: .lowBattery(3)) == .release(.off))
        #expect(decide() == .hold)
    }

    @Test func playingHoldsEvenWhenTheLastPlayTimeIsMissingOrInTheFuture() {
        #expect(decide(isPlaying: true, lastPlayedAt: nil) == .hold)
        #expect(decide(isPlaying: true, lastPlayedAt: now.addingTimeInterval(60)) == .hold)
        #expect(decide(isPlaying: true, lastPlayedAt: now.addingTimeInterval(-300), power: .clear) == .hold)
    }

    @Test func aPauseInsideTheGraceUsesThePowerStop() {
        let recent = now.addingTimeInterval(-19)
        #expect(decide(isPlaying: false, lastPlayedAt: recent, power: .clear) == .hold)
        #expect(decide(isPlaying: false, lastPlayedAt: now, power: .clear) == .hold)
        #expect(decide(isPlaying: false, lastPlayedAt: recent, power: .tooHot) == .release(.tooHot))
        #expect(decide(isPlaying: false, lastPlayedAt: recent, power: .lowBattery(9)) == .release(.lowBattery(9)))
    }

    @Test func atTheGraceAndBeyondReleasesForSilence() {
        #expect(decide(isPlaying: false, lastPlayedAt: now.addingTimeInterval(-20), power: .clear) == .release(.notPlaying))
        #expect(decide(isPlaying: false, lastPlayedAt: now.addingTimeInterval(-300), power: .tooHot) == .release(.notPlaying))
        #expect(decide(isPlaying: false, lastPlayedAt: now.addingTimeInterval(-19), power: .clear) == .hold)
    }

    @Test func aMissingOrFuturePlayTimeReleasesForSilence() {
        #expect(decide(isPlaying: false, lastPlayedAt: nil, power: .tooHot) == .release(.notPlaying))
        #expect(decide(isPlaying: false, lastPlayedAt: now.addingTimeInterval(60), power: .lowBattery(1)) == .release(.notPlaying))
    }

    @Test func aGraceThatIsNotAPositiveWindowDoesNotCountAPauseAsRecent() {
        #expect(decide(isPlaying: false, lastPlayedAt: now, grace: .nan, power: .clear) == .release(.notPlaying))
        #expect(decide(isPlaying: false, lastPlayedAt: now, grace: -1, power: .tooHot) == .release(.notPlaying))
        #expect(decide(isPlaying: false, lastPlayedAt: now, grace: 0, power: .clear) == .release(.notPlaying))
        #expect(decide(isPlaying: true, grace: .nan, power: .clear) == .hold)
        #expect(decide(isPlaying: false, lastPlayedAt: now.addingTimeInterval(-10_000), grace: .infinity, power: .clear) == .hold)
    }

    @Test func theReleaseCarriesTheBatteryPercent() {
        #expect(decide(power: .lowBattery(9)) == .release(.lowBattery(9)))
        #expect(decide(power: .lowBattery(0)) == .release(.lowBattery(0)))
        #expect(decide(power: .lowBattery(100)) == .release(.lowBattery(100)))
        #expect(decide(power: .tooHot) == .release(.tooHot))
    }

    @Test func holdFlagFollowsTheVerdict() {
        #expect(decide().holds)
        #expect(!decide(enabled: false).holds)
        #expect(!decide(power: .tooHot).holds)
    }

    @Test func theShippedTimingIsSafe() {
        #expect(MusicAwakeBox.isSafe(lease: MusicAwakeBox.lease, renewEvery: MusicAwakeBox.renewEvery,
                                     tolerance: MusicAwakeBox.renewTolerance))
    }

    @Test func theRenewalMustLandBeforeTheLeaseEnds() {
        #expect(!MusicAwakeBox.isSafe(lease: 120, renewEvery: 120, tolerance: 0))
        #expect(!MusicAwakeBox.isSafe(lease: 120, renewEvery: 130, tolerance: 0))
        #expect(!MusicAwakeBox.isSafe(lease: 120, renewEvery: 60, tolerance: 60))
        #expect(!MusicAwakeBox.isSafe(lease: 120, renewEvery: 110, tolerance: 5, margin: 5))
        #expect(MusicAwakeBox.isSafe(lease: 120, renewEvery: 110, tolerance: 5, margin: 4))
        #expect(MusicAwakeBox.isSafe(lease: 120, renewEvery: 100, tolerance: 10, margin: 5))
    }

    @Test func aRenewalPeriodThatIsNotPositiveIsNotSafe() {
        #expect(!MusicAwakeBox.isSafe(lease: 120, renewEvery: 0, tolerance: 0))
        #expect(!MusicAwakeBox.isSafe(lease: 120, renewEvery: -5, tolerance: 0))
        #expect(MusicAwakeBox.isSafe(lease: 120, renewEvery: 1, tolerance: 0, margin: 0))
    }

    @Test func aNonFiniteTimingIsNotSafe() {
        #expect(!MusicAwakeBox.isSafe(lease: .nan, renewEvery: 60, tolerance: 10))
        #expect(!MusicAwakeBox.isSafe(lease: 120, renewEvery: .nan, tolerance: 10))
        #expect(!MusicAwakeBox.isSafe(lease: 120, renewEvery: 60, tolerance: .infinity))
        #expect(!MusicAwakeBox.isSafe(lease: 120, renewEvery: .infinity, tolerance: 0, margin: 0))
        #expect(MusicAwakeBox.isSafe(lease: 120, renewEvery: 60, tolerance: 10, margin: 5))
    }
}
