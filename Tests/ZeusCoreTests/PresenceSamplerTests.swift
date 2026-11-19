import Foundation
import Testing
@testable import ZeusCore

@Suite("Presence sampler")
struct PresenceSamplerTests {
    @Test func oneAnalysisInFlightAndHalfSecondSpacing() {
        var sampler = PresenceSampler()
        #expect(PresenceSampler.interval == 0.5)
        #expect(!sampler.isAnalyzing)

        // The first frame is analyzed at once; the camera delivers many more while it runs, and they are dropped.
        do { let taken = sampler.shouldAnalyze(at: 10.0); #expect(taken) }
        #expect(sampler.isAnalyzing)
        for step in 1...30 {
            do { let taken = sampler.shouldAnalyze(at: 10.0 + Double(step) * 0.03); #expect(!taken) }
        }

        // The analysis ends quickly, but the spacing still holds the next frame back.
        sampler.analysisFinished()
        #expect(!sampler.isAnalyzing)
        do { let taken = sampler.shouldAnalyze(at: 10.2); #expect(!taken) }
        do { let taken = sampler.shouldAnalyze(at: 10.49); #expect(!taken) }
        // Exactly half a second after the last start is allowed.
        do { let taken = sampler.shouldAnalyze(at: 10.5); #expect(taken) }
        #expect(sampler.isAnalyzing)

        // A slow analysis keeps later frames out even when the spacing has long passed.
        do { let taken = sampler.shouldAnalyze(at: 11.0); #expect(!taken) }
        do { let taken = sampler.shouldAnalyze(at: 12.5); #expect(!taken) }
        sampler.analysisFinished()
        do { let taken = sampler.shouldAnalyze(at: 12.6); #expect(taken) }
    }

    @Test func spacingCountsFromTheStartOfTheLastAnalysis() {
        var sampler = PresenceSampler()
        do { let taken = sampler.shouldAnalyze(at: 0); #expect(taken) }
        // The analysis took 0.4 s, so the next one may start 0.1 s later, not 0.5 s later.
        sampler.analysisFinished()
        do { let taken = sampler.shouldAnalyze(at: 0.4); #expect(!taken) }
        do { let taken = sampler.shouldAnalyze(at: 0.5); #expect(taken) }
        sampler.analysisFinished()
        // Dropped frames do not move the clock: a frame at 0.9 is refused, one at 1.0 is taken.
        do { let taken = sampler.shouldAnalyze(at: 0.9); #expect(!taken) }
        do { let taken = sampler.shouldAnalyze(at: 1.0); #expect(taken) }
    }

    @Test func aStopForgetsTheFlightAndTheClock() {
        var sampler = PresenceSampler()
        do { let taken = sampler.shouldAnalyze(at: 5); #expect(taken) }
        // The camera stopped while an analysis was out: its result will be dropped, and the next watch starts clean.
        sampler.reset()
        #expect(!sampler.isAnalyzing)
        do { let taken = sampler.shouldAnalyze(at: 5.01); #expect(taken) }
    }

    @Test func aFinishWithNothingInFlightChangesNothing() {
        var sampler = PresenceSampler()
        sampler.analysisFinished()
        #expect(!sampler.isAnalyzing)
        do { let taken = sampler.shouldAnalyze(at: 1); #expect(taken) }
        sampler.analysisFinished()
        sampler.analysisFinished()
        do { let taken = sampler.shouldAnalyze(at: 1.2); #expect(!taken) }
    }

    @Test func oddTimestampsNeverStickTheSampler() {
        var sampler = PresenceSampler()
        // A timestamp that is not a number is never an analysis.
        do { let taken = sampler.shouldAnalyze(at: .nan); #expect(!taken) }
        do { let taken = sampler.shouldAnalyze(at: .infinity); #expect(!taken) }
        #expect(!sampler.isAnalyzing)

        // A clock that steps back (a restarted capture session) does not freeze the sampler until it catches up.
        do { let taken = sampler.shouldAnalyze(at: 100); #expect(taken) }
        sampler.analysisFinished()
        do { let taken = sampler.shouldAnalyze(at: 3); #expect(taken) }
    }

    @Test func aSteadyStreamIsSampledTwiceASecond() {
        var sampler = PresenceSampler()
        var taken = 0
        // 30 frames per second for 10 seconds, each analysis takes 0.1 s.
        var busyUntil = -1.0
        for frame in 0..<300 {
            let now = Double(frame) / 30
            if sampler.isAnalyzing, now >= busyUntil { sampler.analysisFinished() }
            if sampler.shouldAnalyze(at: now) {
                taken += 1
                busyUntil = now + 0.1
            }
        }
        #expect(taken == 20)
    }
}
