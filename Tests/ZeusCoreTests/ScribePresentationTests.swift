import Foundation
import Testing
@testable import ZeusCore

@Suite("Scribe presentation")
struct ScribePresentationTests {
    private func recording(_ id: ScribeSessionID) -> ScribeSessionMachine {
        var machine = ScribeSessionMachine()
        _ = machine.start(id, now: 0)
        _ = machine.acknowledgeCapture(id, now: 1)
        return machine
    }

    private func state(_ machine: ScribeSessionMachine, reveal: TimeInterval? = nil, reduce: Bool = false) -> ScribePresentation {
        ScribePresentation.state(for: machine.phase, elapsed: 7, revealElapsed: reveal, reduceMotion: reduce)
    }

    // MARK: Indicators

    @Test func micIndicatorFailsClosed() {
        #expect(ScribeMicIndicator(.unmuted) == .listening)
        #expect(ScribeMicIndicator(.unmuted).label == "Listening")
        #expect(ScribeMicIndicator(.muted).label == "Mic muted, not recorded")
        #expect(ScribeMicIndicator(.unknown).label == "Mic status unknown, not recorded")
        #expect(ScribeMicIndicator(nil) == .unknownNotRecorded)
        #expect(!ScribeMicIndicator(.muted).isRecorded)
        #expect(!ScribeMicIndicator(nil).isRecorded)
    }

    @Test func systemIndicatorFollowsFrames() {
        #expect(ScribeSystemIndicator(framesReceived: false) == .waiting)
        #expect(ScribeSystemIndicator(framesReceived: true) == .receiving)
    }

    @Test func completeAnnouncesNotesReadyAtRevealStart() {
        let announced = ScribePresentation.state(for: .complete(ScribeSessionID()), revealElapsed: 0).announcement
        #expect(announced == "Notes are ready")
    }

    // MARK: Mapping

    @Test func machineEventsMapToPresentationInOrder() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        #expect(state(machine) == .idle)

        _ = machine.start(id, now: 0)
        #expect(state(machine) == .connecting)

        _ = machine.acknowledgeCapture(id, now: 1)
        #expect(state(machine) == .recording(elapsed: 7))

        _ = machine.requestEnd(id, now: 2, grace: 5)
        #expect(state(machine) == .confirmingEnd)

        _ = machine.keepRecording(id)
        #expect(state(machine) == .recording(elapsed: 7))

        _ = machine.requestEnd(id, now: 3, grace: 5)
        _ = machine.captureEnded(id)
        #expect(state(machine) == .writing)

        _ = machine.transcriptFinalized(id)
        #expect(state(machine) == .writing)

        _ = machine.notesReady(id)
        #expect(state(machine) == .complete)
        #expect(state(machine, reveal: 0) == .revealing)
    }

    @Test func failureCarriesItsReasonAndCancelReturnsToIdle() {
        let id = ScribeSessionID()
        var failing = recording(id)
        _ = failing.fail(id, reason: "capture lost")
        #expect(state(failing) == .failed("capture lost"))

        var cancelled = recording(id)
        _ = cancelled.cancel(id)
        #expect(state(cancelled) == .idle)
    }

    @Test func writingPersistsUntilNotesReadyNoMatterHowLongItTakes() {
        let id = ScribeSessionID()
        var machine = recording(id)
        _ = machine.captureEnded(id)
        // No wall-clock input can complete the wait: the presentation has no time parameter in this phase.
        for reveal in [nil, 0, 1, 60, 3600] as [TimeInterval?] {
            #expect(ScribePresentation.state(for: machine.phase, revealElapsed: reveal) == .writing)
        }
        for _ in 0..<10 { _ = machine.transcriptUpdated(id) }
        #expect(state(machine) == .writing)
        _ = machine.transcriptFinalized(id)
        #expect(state(machine) == .writing)
        #expect(state(machine).glowStage == .writing)
        #expect(state(machine).bodyIsEmpty)
    }

    @Test func revealingOnlyAfterNotesReadyAndEndsByRevealClock() {
        let id = ScribeSessionID()
        var machine = recording(id)
        _ = machine.captureEnded(id)
        _ = machine.transcriptFinalized(id)
        #expect(state(machine, reveal: 0) == .writing)   // notesReady has not arrived

        _ = machine.notesReady(id)
        let full = ScribeGlow.revealDuration(reduceMotion: false)
        #expect(state(machine, reveal: full - 0.01) == .revealing)
        #expect(state(machine, reveal: full) == .complete)
        #expect(state(machine, reveal: nil) == .complete)
        let reduced = ScribeGlow.revealDuration(reduceMotion: true)
        #expect(state(machine, reveal: reduced - 0.01, reduce: true) == .revealing)
        #expect(state(machine, reveal: reduced, reduce: true) == .complete)
    }

    @Test func glowStageFollowsState() {
        #expect(ScribePresentation.idle.glowStage == .off)
        #expect(ScribePresentation.connecting.glowStage == .off)
        #expect(ScribePresentation.recording(elapsed: 3).glowStage == .off)
        #expect(ScribePresentation.confirmingEnd.glowStage == .off)
        #expect(ScribePresentation.writing.glowStage == .writing)
        #expect(ScribePresentation.revealing.glowStage == .reveal)
        #expect(ScribePresentation.complete.glowStage == .off)
        #expect(ScribePresentation.failed("x").glowStage == .off)
    }

    @Test func topBarRecordingStateCoversRecordingAndConfirm() {
        #expect(ScribePresentation.recording(elapsed: 1).isRecordingState)
        #expect(ScribePresentation.confirmingEnd.isRecordingState)
        for other in [ScribePresentation.idle, .connecting, .writing, .revealing, .complete, .failed("x")] {
            #expect(!other.isRecordingState)
        }
    }

    // MARK: Glow motion

    @Test func surgeExistsOnlyInTheRevealStage() {
        for t in stride(from: 0.0, through: 30.0, by: 0.05) {
            #expect(ScribeGlow.glowHeight(stage: .writing, t: t, reduceMotion: false) <= ScribeGlow.riseHeight + 1e-9)
        }
        #expect(ScribeGlow.glowHeight(stage: .reveal, t: ScribeGlow.surgeDuration, reduceMotion: false) == 1)
    }

    @Test func reduceMotionHasStaticBandAndNoSurge() {
        for t in stride(from: 0.0, through: 20.0, by: 0.1) {
            #expect(ScribeGlow.glowHeight(stage: .writing, t: t, reduceMotion: true) == ScribeGlow.reducedBand)
        }
        for t in stride(from: 0.0, to: ScribeGlow.crossfadeDuration, by: 0.01) {
            let h = ScribeGlow.glowHeight(stage: .reveal, t: t, reduceMotion: true)
            #expect(h == ScribeGlow.reducedBand)
        }
        #expect(ScribeGlow.glowHeight(stage: .reveal, t: 5, reduceMotion: true) == 0)
        // Crossfade: the glow fades out while the notes fade in.
        #expect(ScribeGlow.glowOpacity(stage: .reveal, t: 0, reduceMotion: true) == 1)
        #expect(ScribeGlow.glowOpacity(stage: .reveal, t: ScribeGlow.crossfadeDuration, reduceMotion: true) == 0)
        #expect(ScribeGlow.contentOpacity(t: 0, reduceMotion: true) == 0)
        #expect(ScribeGlow.contentOpacity(t: ScribeGlow.crossfadeDuration, reduceMotion: true) == 1)
    }

    @Test func glowHeightStaysInUnitRange() {
        let stages: [ScribeGlow.Stage] = [.off, .writing, .reveal]
        for stage in stages {
            for reduce in [false, true] {
                for t in [-5, 0, 0.1, 0.17, 0.5, 1, 2, 3.7, 10, 100, 1e6, .infinity, .nan] as [TimeInterval] {
                    let h = ScribeGlow.glowHeight(stage: stage, t: t, reduceMotion: reduce)
                    #expect((0...1).contains(h))
                    let o = ScribeGlow.glowOpacity(stage: stage, t: t, reduceMotion: reduce)
                    #expect((0...1).contains(o))
                }
            }
        }
    }

    @Test func riseIsMonotonicAndReachesQuarterHeight() {
        #expect(ScribeGlow.glowHeight(stage: .writing, t: 0, reduceMotion: false) == 0)
        #expect(ScribeGlow.glowHeight(stage: .writing, t: ScribeGlow.riseDelay, reduceMotion: false) == 0)
        var previous = 0.0
        let end = ScribeGlow.riseDelay + ScribeGlow.riseDuration
        for t in stride(from: ScribeGlow.riseDelay, through: end, by: 0.01) {
            let h = ScribeGlow.glowHeight(stage: .writing, t: t, reduceMotion: false)
            #expect(h >= previous - 1e-12)
            previous = h
        }
        #expect(abs(ScribeGlow.glowHeight(stage: .writing, t: end, reduceMotion: false) - ScribeGlow.riseHeight) < 1e-9)
    }

    @Test func breathingBandStaysInItsRangeForAsLongAsWritingLasts() {
        let settled = ScribeGlow.riseDelay + ScribeGlow.riseDuration + ScribeGlow.holdDuration + ScribeGlow.recedeDuration
        var seen = Set<Double>()
        for t in stride(from: settled, through: settled + 600, by: 0.37) {
            let h = ScribeGlow.glowHeight(stage: .writing, t: t, reduceMotion: false)
            #expect(h >= 0.05 - 1e-9 && h <= 0.08 + 1e-9)
            seen.insert((h * 1e6).rounded())
        }
        #expect(seen.count > 3)   // it actually breathes
    }

    @Test func writingGlowIsContinuousThroughTheRecede() {
        var previous = ScribeGlow.glowHeight(stage: .writing, t: 0.3, reduceMotion: false)
        for t in stride(from: 0.3, through: 4, by: 0.01) {
            let h = ScribeGlow.glowHeight(stage: .writing, t: t, reduceMotion: false)
            #expect(abs(h - previous) < 0.02)
            previous = h
        }
    }

    @Test func surgeRisesMonotonicallyToFullThenHoldsThenClears() {
        var previous = 0.0
        for t in stride(from: 0.0, through: ScribeGlow.surgeDuration, by: 0.01) {
            let h = ScribeGlow.glowHeight(stage: .reveal, t: t, reduceMotion: false)
            #expect(h >= previous - 1e-12)
            previous = h
        }
        #expect(previous > 0.99)
        #expect(ScribeGlow.glowHeight(stage: .reveal, t: ScribeGlow.surgeDuration, reduceMotion: false) == 1)
        let holdMid = ScribeGlow.surgeDuration + ScribeGlow.surgeHold / 2
        #expect(ScribeGlow.glowHeight(stage: .reveal, t: holdMid, reduceMotion: false) == 1)
        #expect(ScribeGlow.glowOpacity(stage: .reveal, t: holdMid, reduceMotion: false) == 1)
        let fadeStart = ScribeGlow.surgeDuration + ScribeGlow.surgeHold
        #expect(ScribeGlow.glowOpacity(stage: .reveal, t: fadeStart + ScribeGlow.fadeDuration / 2, reduceMotion: false) < 1)
        let done = ScribeGlow.revealDuration(reduceMotion: false)
        #expect(ScribeGlow.glowOpacity(stage: .reveal, t: done, reduceMotion: false) == 0)
        #expect(ScribeGlow.glowHeight(stage: .reveal, t: done, reduceMotion: false) == 0)
    }

    @Test func notesSwapInBeneathTheWashNotBefore() {
        #expect(ScribeGlow.contentOpacity(t: 0, reduceMotion: false) == 0)
        #expect(ScribeGlow.contentOpacity(t: ScribeGlow.surgeDuration - 0.01, reduceMotion: false) == 0)
        #expect(ScribeGlow.contentOpacity(t: ScribeGlow.surgeDuration, reduceMotion: false) == 1)
    }

    @Test func measuredConstantsMatchTheReference() {
        #expect(ScribeGlow.riseHeight == 0.25)
        #expect(ScribeGlow.riseDelay == 0.17)
        #expect(ScribeGlow.riseDuration == 0.45)
        #expect(ScribeGlow.surgeDuration == 0.4)
        #expect(ScribeGlow.surgeHold == 0.28)
        #expect(ScribeGlow.fadeDuration == 0.3)
        #expect(ScribeGlow.washColor == ScribeGlow.RGB(110, 80, 160))
        #expect(ScribeGlow.edgeColor == ScribeGlow.RGB(155, 119, 185))
        #expect(ScribeGlow.peakColor == ScribeGlow.RGB(115, 85, 158))
    }

    // MARK: Accessibility

    @Test func everyStateHasAccessibilityLabelAndValue() {
        let all: [ScribePresentation] = [
            .idle, .connecting, .recording(elapsed: 65), .confirmingEnd, .writing, .revealing, .complete, .failed("Nope")
        ]
        for presentation in all {
            #expect(!presentation.accessibilityLabel.isEmpty)
            #expect(!presentation.accessibilityValue.isEmpty)
        }
        #expect(ScribePresentation.recording(elapsed: 65).accessibilityValue == "1 minute, 5 seconds")
        #expect(ScribePresentation.failed("Nope").accessibilityValue == "Nope")
        #expect(ScribePresentation.writing.announcement?.isEmpty == false)
        #expect(ScribePresentation.revealing.announcement?.isEmpty == false)
        #expect(ScribePresentation.failed("Nope").announcement?.contains("Nope") == true)
    }
}
