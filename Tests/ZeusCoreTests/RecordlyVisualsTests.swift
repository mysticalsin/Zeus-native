import Foundation
import Testing
@testable import ZeusCore

@Suite("Recordly visuals")
struct RecordlyVisualsTests {
    @Test func redFrameOnlyWhileCapturing() {
        for phase in [RecordlyVisualPhase.idle, .countdown(3), .starting, .saved] {
            #expect(RecordlyVisualTokens.tokens(for: phase).liveFrameOpacity == 0)
            #expect(!RecordlyVisualTokens.tokens(for: phase).showsLiveCapsule)
        }
        let recording = RecordlyVisualTokens.tokens(for: .recording)
        #expect(recording.liveFrameOpacity == 1)
        #expect(recording.showsLiveCapsule)
        #expect(recording.showsMeters)
        #expect(recording.buttonCorner < RecordlyVisualTokens.tokens(for: .idle).buttonCorner)
    }

    @Test func countdownDimsPreviewSlightlyAndLocksIt() {
        let countdown = RecordlyVisualTokens.tokens(for: .countdown(2))
        #expect(countdown.previewDim > 0 && countdown.previewDim < 0.5)
        #expect(countdown.showsCountdownNumeral)
        #expect(!countdown.previewInteractive)
        #expect(RecordlyVisualTokens.tokens(for: .idle).previewInteractive)
        #expect(RecordlyVisualTokens.tokens(for: .idle).ambientGlow > 0)
        #expect(RecordlyVisualTokens.tokens(for: .recording).ambientGlow == 0)
    }

    @Test func numeralClampsAndRingProgresses() {
        #expect(RecordlyCountdownVisual.numeral(remaining: nil) == nil)
        #expect(RecordlyCountdownVisual.numeral(remaining: 3) == "3")
        #expect(RecordlyCountdownVisual.numeral(remaining: 0) == "1")
        #expect(RecordlyCountdownVisual.numeral(remaining: 9) == "3")
        #expect(RecordlyCountdownVisual.ringProgress(elapsed: -1) == 0)
        #expect(RecordlyCountdownVisual.ringProgress(elapsed: 1.5) == 0.5)
        #expect(RecordlyCountdownVisual.ringProgress(elapsed: 99) == 1)
        #expect(RecordlyCountdownVisual.ringProgress(elapsed: .nan) == 0)
    }

    @Test func numeralSpringsInThenFadesOut() {
        #expect(RecordlyCountdownVisual.stepFraction(elapsed: 1.25) == 0.25)
        #expect(RecordlyCountdownVisual.stepFraction(elapsed: -2) == 0)
        #expect(abs(RecordlyCountdownVisual.numeralScale(stepFraction: 0) - 1.35) < 1e-9)
        #expect(abs(RecordlyCountdownVisual.numeralScale(stepFraction: 0.5) - 1) < 1e-9)
        #expect(RecordlyCountdownVisual.numeralScale(stepFraction: 0.1) > RecordlyCountdownVisual.numeralScale(stepFraction: 0.2))
        #expect(RecordlyCountdownVisual.numeralOpacity(stepFraction: 0) == 0)
        #expect(RecordlyCountdownVisual.numeralOpacity(stepFraction: 0.5) == 1)
        #expect(RecordlyCountdownVisual.numeralOpacity(stepFraction: 1) == 0)
    }

    @Test func meterAttacksFastAndReleasesSlowly() {
        var meter = RecordlyLevelMeter()
        meter.step(target: 1, dt: 0.05)
        let risen = meter.value
        #expect(risen > 0.5)
        meter.step(target: 0, dt: 0.05)
        #expect(meter.value > risen * 0.6)
        for _ in 0..<200 { meter.step(target: 0, dt: 0.05) }
        #expect(meter.value == 0)
    }

    @Test func meterIgnoresBadInput() {
        var meter = RecordlyLevelMeter()
        meter.step(target: .nan, dt: 0.1)
        #expect(meter.value == 0)
        meter.step(target: 5, dt: 100)
        #expect(meter.value <= 1)
        meter.reset()
        #expect(meter.value == 0)
    }

    @Test func perceptualMapsDecibels() {
        #expect(RecordlyLevelMeter.perceptual(peak: 0) == 0)
        #expect(RecordlyLevelMeter.perceptual(peak: .nan) == 0)
        #expect(abs(RecordlyLevelMeter.perceptual(peak: 1) - 1) < 1e-9)
        #expect(RecordlyLevelMeter.perceptual(peak: 0.001) == 0)
        #expect(abs(RecordlyLevelMeter.perceptual(peak: 0.0630957) - 0.5) < 0.01)
        #expect(RecordlyLevelMeter.litSegments(value: 0.5, count: 10) == 5)
        #expect(RecordlyLevelMeter.litSegments(value: 2, count: 10) == 10)
        #expect(RecordlyLevelMeter.litSegments(value: 1, count: 0) == 0)
    }

    @Test func entranceTakesAboutAThirdOfASecondAndStaggersInOrder() {
        #expect(abs(RecordlyEntrance.totalDuration - 0.35) < 1e-9)
        let delays = RecordlyEntrance.Item.allCases.map { RecordlyEntrance.delay($0, reduceMotion: false) }
        #expect(delays == delays.sorted())
        #expect(delays.first == 0)
        #expect(RecordlyEntrance.Item.allCases.allSatisfy { RecordlyEntrance.delay($0, reduceMotion: true) == 0 })
        #expect(RecordlyEntrance.offset(reduceMotion: true) == 0)
        #expect(RecordlyEntrance.offset(reduceMotion: false) > 0)
    }

    @Test func chipStates() {
        #expect(RecordlySourceChipState.resolve(on: true, available: true, needsPermission: false) == .on)
        #expect(RecordlySourceChipState.resolve(on: false, available: true, needsPermission: false) == .off)
        #expect(RecordlySourceChipState.resolve(on: false, available: false, needsPermission: false) == .unavailable)
        #expect(RecordlySourceChipState.resolve(on: true, available: true, needsPermission: true) == .needsPermission)
        #expect(RecordlySourceChipState.needsPermission.word == "Needs permission")
        #expect(!RecordlySourceChipState.unavailable.isInteractive)
        #expect(RecordlySourceChipState.off.isInteractive)
    }

    @Test func clipSummaryText() {
        #expect(RecordlyClipSummary.duration(7) == "0:07")
        #expect(RecordlyClipSummary.duration(65) == "1:05")
        #expect(RecordlyClipSummary.duration(3729) == "1:02:09")
        #expect(RecordlyClipSummary.duration(-3) == "0:00")
        #expect(RecordlyClipSummary.fileSize(812_000) == "812 KB")
        #expect(RecordlyClipSummary.fileSize(4_200_000) == "4.2 MB")
        #expect(RecordlyClipSummary.fileSize(1_300_000_000) == "1.3 GB")
        #expect(RecordlyClipSummary.fileSize(0) == "0 KB")
        #expect(RecordlyClipSummary.line(duration: 7, bytes: 4_200_000) == "0:07 \u{00B7} 4.2 MB")
        #expect(RecordlyClipSummary.line(duration: nil, bytes: 4_200_000) == "4.2 MB")
        #expect(RecordlyClipSummary.line(duration: nil, bytes: nil) == "")
    }
}
