import Foundation
import Testing
@testable import ZeusCore

@Suite("RecordlyVisualsBox")
struct RecordlyVisualsBoxTests {
    @Test func idleTokensAreCalmAndInteractive() {
        let tokens = RecordlyVisualsBox.tokens(for: .idle)
        #expect(tokens.previewDim == 0)
        #expect(tokens.liveFrameOpacity == 0)
        #expect(tokens.ambientGlow == 0.34)
        #expect(tokens.buttonCorner == 0.5)
        #expect(!tokens.showsLiveCapsule)
        #expect(!tokens.showsMeters)
        #expect(!tokens.showsCountdownNumeral)
        #expect(tokens.previewInteractive)
    }

    @Test func countdownTokensDimThePreviewAndShowTheNumeral() {
        let tokens = RecordlyVisualsBox.tokens(for: .countdown)
        #expect(tokens.previewDim == 0.32)
        #expect(tokens.liveFrameOpacity == 0)
        #expect(tokens.ambientGlow == 0.5)
        #expect(tokens.buttonCorner == 0.5)
        #expect(!tokens.showsLiveCapsule)
        #expect(!tokens.showsMeters)
        #expect(tokens.showsCountdownNumeral)
        #expect(!tokens.previewInteractive)
    }

    @Test func startingTokensHoldThePreview() {
        let tokens = RecordlyVisualsBox.tokens(for: .starting)
        #expect(tokens.previewDim == 0.18)
        #expect(tokens.liveFrameOpacity == 0)
        #expect(tokens.ambientGlow == 0.2)
        #expect(tokens.buttonCorner == 0.5)
        #expect(!tokens.showsLiveCapsule)
        #expect(!tokens.showsMeters)
        #expect(!tokens.showsCountdownNumeral)
        #expect(!tokens.previewInteractive)
    }

    @Test func recordingTokensShowTheLiveFrameAndMeters() {
        let tokens = RecordlyVisualsBox.tokens(for: .recording)
        #expect(tokens.previewDim == 0)
        #expect(tokens.liveFrameOpacity == 1)
        #expect(tokens.ambientGlow == 0)
        #expect(tokens.buttonCorner == 0.3)
        #expect(tokens.showsLiveCapsule)
        #expect(tokens.showsMeters)
        #expect(!tokens.showsCountdownNumeral)
        #expect(!tokens.previewInteractive)
    }

    @Test func stoppingTokensFadeTheLiveFrame() {
        let tokens = RecordlyVisualsBox.tokens(for: .stopping)
        #expect(tokens.previewDim == 0.12)
        #expect(tokens.liveFrameOpacity == 0.5)
        #expect(tokens.ambientGlow == 0)
        #expect(tokens.buttonCorner == 0.3)
        #expect(tokens.showsLiveCapsule)
        #expect(!tokens.showsMeters)
        #expect(!tokens.showsCountdownNumeral)
        #expect(!tokens.previewInteractive)
    }

    @Test func savedTokensRestTheButton() {
        let tokens = RecordlyVisualsBox.tokens(for: .saved)
        #expect(tokens.previewDim == 0)
        #expect(tokens.liveFrameOpacity == 0)
        #expect(tokens.ambientGlow == 0.2)
        #expect(tokens.buttonCorner == 0.5)
        #expect(!tokens.showsLiveCapsule)
        #expect(!tokens.showsMeters)
        #expect(!tokens.showsCountdownNumeral)
        #expect(!tokens.previewInteractive)
    }

    @Test func numeralClampsToTheCountdownLength() {
        #expect(RecordlyVisualsBox.numeral(remaining: nil, seconds: 3) == nil)
        #expect(RecordlyVisualsBox.numeral(remaining: 3, seconds: 3) == "3")
        #expect(RecordlyVisualsBox.numeral(remaining: 0, seconds: 3) == "1")
        #expect(RecordlyVisualsBox.numeral(remaining: 9, seconds: 3) == "3")
        #expect(RecordlyVisualsBox.numeral(remaining: 9, seconds: 5) == "5")
        #expect(RecordlyVisualsBox.numeral(remaining: 4, seconds: 5) == "4")
    }

    @Test func ringProgressFillsAcrossTheCountdown() {
        #expect(RecordlyVisualsBox.ringProgress(elapsed: -1, seconds: 3) == 0)
        #expect(RecordlyVisualsBox.ringProgress(elapsed: 1.5, seconds: 3) == 0.5)
        #expect(RecordlyVisualsBox.ringProgress(elapsed: 99, seconds: 3) == 1)
        #expect(RecordlyVisualsBox.ringProgress(elapsed: .nan, seconds: 3) == 0)
        #expect(RecordlyVisualsBox.ringProgress(elapsed: .infinity, seconds: 3) == 0)
        #expect(RecordlyVisualsBox.ringProgress(elapsed: 2, seconds: 4) == 0.5)
    }

    @Test func numeralScaleSettlesAndOpacityFades() {
        #expect(RecordlyVisualsBox.stepFraction(elapsed: 1.25) == 0.25)
        #expect(RecordlyVisualsBox.stepFraction(elapsed: -2) == 0)
        #expect(RecordlyVisualsBox.stepFraction(elapsed: .nan) == 0)
        #expect(RecordlyVisualsBox.stepFraction(elapsed: 2) == 0)
        #expect(abs(RecordlyVisualsBox.numeralScale(stepFraction: 0) - 1.35) < 1e-9)
        #expect(abs(RecordlyVisualsBox.numeralScale(stepFraction: 0.35) - 1) < 1e-9)
        #expect(abs(RecordlyVisualsBox.numeralScale(stepFraction: 0.1) - 1.1275510204081634) < 1e-9)
        #expect(RecordlyVisualsBox.numeralScale(stepFraction: 0.1) > RecordlyVisualsBox.numeralScale(stepFraction: 0.2))
        #expect(RecordlyVisualsBox.numeralOpacity(stepFraction: 0) == 0)
        #expect(RecordlyVisualsBox.numeralOpacity(stepFraction: 0.5) == 1)
        #expect(RecordlyVisualsBox.numeralOpacity(stepFraction: 1) == 0)
        #expect(abs(RecordlyVisualsBox.numeralOpacity(stepFraction: 0.06) - 0.5) < 1e-9)
        #expect(abs(RecordlyVisualsBox.numeralOpacity(stepFraction: 0.875) - 0.5) < 1e-9)
    }

    @Test func meterAttacksFastReleasesSlowlyAndSnapsOff() {
        let risen = RecordlyVisualsBox.meterStep(value: 0, target: 1, dt: 0.05)
        #expect(abs(risen - 0.5934303402594009) < 1e-9)
        let fallen = RecordlyVisualsBox.meterStep(value: risen, target: 0, dt: 0.05)
        #expect(abs(fallen - 0.4738637514010273) < 1e-9)
        #expect(fallen > risen * 0.6)
        #expect(RecordlyVisualsBox.meterStep(value: 0.0009, target: 0.0009, dt: 0) == 0)
        #expect(RecordlyVisualsBox.meterStep(value: 0.5, target: 0.5, dt: -3) == 0.5)
    }

    @Test func meterRejectsNonFiniteInputAndClampsTheStep() {
        #expect(RecordlyVisualsBox.meterStep(value: 0, target: .nan, dt: 0.1) == 0)
        #expect(RecordlyVisualsBox.meterStep(value: 0.4, target: 1, dt: .nan) == 0.4)
        let clamped = RecordlyVisualsBox.meterStep(value: 0, target: 5, dt: 100)
        #expect(abs(clamped - 0.9888910034617577) < 1e-9)
        #expect(clamped < 1)
        #expect(RecordlyVisualsBox.attackPerSecond == 18)
        #expect(RecordlyVisualsBox.releasePerSecond == 4.5)
    }

    @Test func perceptualMapsAFortyEightDecibelRange() {
        #expect(RecordlyVisualsBox.perceptual(peak: 0) == 0)
        #expect(RecordlyVisualsBox.perceptual(peak: .nan) == 0)
        #expect(RecordlyVisualsBox.perceptual(peak: -0.2) == 0)
        #expect(abs(RecordlyVisualsBox.perceptual(peak: 1) - 1) < 1e-9)
        #expect(abs(RecordlyVisualsBox.perceptual(peak: 2) - 1) < 1e-9)
        #expect(RecordlyVisualsBox.perceptual(peak: 0.001) == 0)
        #expect(abs(RecordlyVisualsBox.perceptual(peak: 0.0630957) - 0.5) < 0.01)
        #expect(RecordlyVisualsBox.litSegments(value: 0.5, count: 10) == 5)
        #expect(RecordlyVisualsBox.litSegments(value: 2, count: 10) == 10)
        #expect(RecordlyVisualsBox.litSegments(value: 1, count: 0) == 0)
        #expect(RecordlyVisualsBox.litSegments(value: .nan, count: 8) == 0)
    }

    @Test func entranceStaggersThenDropsUnderReduceMotion() {
        #expect(RecordlyVisualsBox.entranceItemDuration == 0.2)
        #expect(RecordlyVisualsBox.entranceStagger == 0.05)
        #expect(abs(RecordlyVisualsBox.entranceTotal(itemCount: 4) - 0.35) < 1e-9)
        #expect(RecordlyVisualsBox.entranceTotal(itemCount: 1) == 0.2)
        #expect(RecordlyVisualsBox.entranceDelay(index: 0, reduceMotion: false) == 0)
        #expect(abs(RecordlyVisualsBox.entranceDelay(index: 3, reduceMotion: false) - 0.15) < 1e-9)
        #expect(RecordlyVisualsBox.entranceDelay(index: 2, reduceMotion: true) == 0)
        #expect(RecordlyVisualsBox.entranceOffset(reduceMotion: false) == 10)
        #expect(RecordlyVisualsBox.entranceOffset(reduceMotion: true) == 0)
    }

    @Test func chipStateWordsAndInteraction() {
        #expect(RecordlyVisualsBox.chip(on: true, available: true, needsPermission: false) == .on)
        #expect(RecordlyVisualsBox.chip(on: false, available: true, needsPermission: false) == .off)
        #expect(RecordlyVisualsBox.chip(on: false, available: false, needsPermission: false) == .unavailable)
        #expect(RecordlyVisualsBox.chip(on: true, available: false, needsPermission: false) == .on)
        #expect(RecordlyVisualsBox.chip(on: true, available: true, needsPermission: true) == .needsPermission)
        #expect(RecordlyVisualsBox.chipWord(.on) == "On")
        #expect(RecordlyVisualsBox.chipWord(.off) == "Off")
        #expect(RecordlyVisualsBox.chipWord(.needsPermission) == "Needs permission")
        #expect(RecordlyVisualsBox.chipWord(.unavailable) == "Soon")
        #expect(RecordlyVisualsBox.chipInteractive(.on))
        #expect(RecordlyVisualsBox.chipInteractive(.off))
        #expect(!RecordlyVisualsBox.chipInteractive(.needsPermission))
        #expect(!RecordlyVisualsBox.chipInteractive(.unavailable))
    }

    @Test func clipDurationSizeAndLine() {
        #expect(RecordlyVisualsBox.durationText(7) == "0:07")
        #expect(RecordlyVisualsBox.durationText(65) == "1:05")
        #expect(RecordlyVisualsBox.durationText(3729) == "1:02:09")
        #expect(RecordlyVisualsBox.durationText(-3) == "0:00")
        #expect(RecordlyVisualsBox.durationText(.nan) == "0:00")
        #expect(RecordlyVisualsBox.durationText(0) == "0:00")
        #expect(RecordlyVisualsBox.fileSize(812_000) == "812 KB")
        #expect(RecordlyVisualsBox.fileSize(4_200_000) == "4.2 MB")
        #expect(RecordlyVisualsBox.fileSize(1_300_000_000) == "1.3 GB")
        #expect(RecordlyVisualsBox.fileSize(0) == "0 KB")
        #expect(RecordlyVisualsBox.fileSize(1) == "1 KB")
        #expect(RecordlyVisualsBox.summaryLine(duration: 7, bytes: 4_200_000) == "0:07 \u{00B7} 4.2 MB")
        #expect(RecordlyVisualsBox.summaryLine(duration: nil, bytes: 4_200_000) == "4.2 MB")
        #expect(RecordlyVisualsBox.summaryLine(duration: 7, bytes: nil) == "0:07")
        #expect(RecordlyVisualsBox.summaryLine(duration: nil, bytes: nil) == "")
        #expect(RecordlyVisualsBox.summaryLine(duration: 0, bytes: 0) == "")
    }

    @Test func micRowFollowsTheMicrophoneToggle() {
        #expect(RecordlyVisualsBox.showsMic(microphone: true))
        #expect(!RecordlyVisualsBox.showsMic(microphone: false))
    }
}
