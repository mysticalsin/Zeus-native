import Foundation
import Testing
@testable import ZeusCore

@Suite("Real recording lifecycle feedback")
struct RecordingFeedbackTests {
    @Test func partialExportRequiresAttentionAndNeverEmitsWholeExportSuccess() {
        #expect(RecordingFeedback.exportDisposition(completedFiles: 1, failedFormats: 1) == .partial)
        #expect(RecordingFeedback.exportDisposition(completedFiles: 0, failedFormats: 0) == .failed)
        #expect(RecordingFeedback.exportDisposition(completedFiles: 0, failedFormats: 2) == .failed)
        #expect(RecordingFeedback.exportDisposition(completedFiles: 2, failedFormats: 0) == .saved)
    }
    private func snapshot(_ phase: RecordingFeedback.Phase, producer: RecordingFeedback.Producer = .recordly,
                          began: Double = 10) -> RecordingFeedback.Snapshot {
        .init(producer: producer, phase: phase, sessionKey: "fixture", beganAt: began, label: "Fixture status")
    }

    @Test func processingNeverBecomesSuccessBecauseTimePasses() {
        for phase: RecordingFeedback.Phase in [.starting, .finishing, .writing, .exporting] {
            for elapsed in [0.0, 1, 5, 60, 3_600, 86_400] {
                let state = snapshot(phase)
                let frame = RecordingFeedback.frame(state, at: 10 + elapsed, reduceMotion: false, reduceTransparency: false)
                #expect(frame.visible)
                #expect(state.phase == phase)
                #expect(frame.reveal == 1)
            }
        }
    }

    @Test func bothProductionSourcesUseTheSameTemporalContract() {
        for phase: RecordingFeedback.Phase in [.starting, .finishing, .writing, .exporting, .completed, .failed] {
            for elapsed in [0.0, 0.2, 0.4, 0.7, 1, 3, 5] {
                let a = RecordingFeedback.frame(snapshot(phase), at: 10 + elapsed, reduceMotion: false, reduceTransparency: false)
                let b = RecordingFeedback.frame(snapshot(phase, producer: .meetings), at: 10 + elapsed,
                                                reduceMotion: false, reduceTransparency: false)
                #expect(a == b)
            }
        }
    }

    @Test func completionSurgesRevealsThenExpires() {
        let state = snapshot(.completed)
        let initial = RecordingFeedback.frame(state, at: 10, reduceMotion: false, reduceTransparency: false)
        let revealed = RecordingFeedback.frame(state, at: 10.5, reduceMotion: false, reduceTransparency: false)
        let settled = RecordingFeedback.frame(state, at: 12, reduceMotion: false, reduceTransparency: false)
        #expect(initial.visible && initial.reveal == 0 && initial.beamOpacity > 0)
        #expect(revealed.visible && revealed.reveal == 1)
        #expect(settled.visible && settled.beamOpacity == 0 && settled.blur == 0)
        #expect(!RecordingFeedback.frame(state, at: 15, reduceMotion: false, reduceTransparency: false).visible)
    }

    @Test func reducedMotionIsStaticWhileStatusRemainsReadable() {
        for phase: RecordingFeedback.Phase in [.starting, .finishing, .writing, .exporting, .completed, .failed] {
            let a = RecordingFeedback.frame(snapshot(phase), at: 10.1, reduceMotion: true, reduceTransparency: false)
            let b = RecordingFeedback.frame(snapshot(phase), at: 13, reduceMotion: true, reduceTransparency: false)
            #expect(a == b)
            #expect(a.reveal == 1 && a.blur == 0 && a.elapsed == 0)
        }
    }

    @Test func reduceTransparencyEliminatesFrost() {
        for phase: RecordingFeedback.Phase in [.starting, .writing, .completed, .failed] {
            #expect(RecordingFeedback.frame(snapshot(phase), at: 10.3, reduceMotion: false, reduceTransparency: true).beamOpacity == 0)
        }
    }

    @Test func invalidClocksNeverRevealSuccessOrNonfiniteFrames() {
        let inputs = [(Double.nan, 0.0), (Double.infinity, 0.0), (9.0, 10.0),
                      (Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude),
                      (Double.greatestFiniteMagnitude, 0.0)]
        for (now, began) in inputs {
            let completed = RecordingFeedback.frame(snapshot(.completed, began: began), at: now,
                                                     reduceMotion: false, reduceTransparency: false)
            #expect(!completed.visible)
            let working = RecordingFeedback.frame(snapshot(.writing, began: began), at: now,
                                                   reduceMotion: false, reduceTransparency: false)
            #expect(working.visible)
            #expect(working.reveal.isFinite && working.blur.isFinite && working.beamOpacity.isFinite && working.elapsed.isFinite)
        }
    }

    @Test func anOldCompletionCannotBeDisplayedForAnotherProjectOrAfterExpiry() {
        let start = Date(timeIntervalSinceReferenceDate: 10)
        let notice = RecordingFeedback.Completion(sessionKey: "saved-project", beganAt: start, label: "Recording saved")
        #expect(notice.snapshot(for: .recordly, currentSessionKey: "saved-project", now: start) != nil)
        #expect(notice.snapshot(for: .recordly, currentSessionKey: "new-project", now: start) == nil)
        #expect(notice.snapshot(for: .recordly, currentSessionKey: "saved-project", now: start.addingTimeInterval(5)) == nil)
        #expect(notice.snapshot(for: .recordly, currentSessionKey: "saved-project", now: start.addingTimeInterval(-1)) == nil)
    }

    private func status(_ label: String, session: String = "fixture", producer: RecordingFeedback.Producer = .recordly) -> RecordingFeedback.Snapshot {
        .init(producer: producer, phase: .exporting, sessionKey: session, beganAt: 10, label: label)
    }

    @Test func statusSwapUsesReferenceTimingDistanceAndBlur() {
        var transition = RecordingFeedback.StatusTransition(status("Starting"))
        transition.update(status("Exporting"), at: 10, reduceMotion: false)
        #expect(transition.frame(at: 10, reduceMotion: false) == .settled("Starting"))
        let leaving = transition.frame(at: 10.075, reduceMotion: false)
        #expect(leaving.text == "Starting")
        #expect(abs(leaving.opacity - 0.5) < 0.000001)
        #expect(abs(leaving.offsetY + 2) < 0.000001)
        #expect(abs(leaving.blur - 1) < 0.000001)
        let entering = transition.frame(at: 10.225, reduceMotion: false)
        #expect(entering.text == "Exporting")
        #expect(abs(entering.opacity - 0.5) < 0.000001)
        #expect(abs(entering.offsetY - 2) < 0.000001)
        #expect(abs(entering.blur - 1) < 0.000001)
        #expect(transition.frame(at: 10.301, reduceMotion: false) == .settled("Exporting"))
        #expect(!transition.isAnimating(at: 10.301))
    }

    @Test func retargetBeforeMidpointShowsOnlyNewestPendingStatus() {
        var transition = RecordingFeedback.StatusTransition(status("Starting"))
        transition.update(status("Exporting"), at: 10, reduceMotion: false)
        transition.update(status("Export needs attention"), at: 10.08, reduceMotion: false)
        #expect(transition.frame(at: 10.149, reduceMotion: false).text == "Starting")
        #expect(transition.frame(at: 10.151, reduceMotion: false).text == "Export needs attention")
        #expect(transition.frame(at: 10.301, reduceMotion: false) == .settled("Export needs attention"))
        #expect(!transition.isAnimating(at: 10.301), "Retargeting must not postpone the original swap deadline")
    }

    @Test func reversingBeforeMidpointCancelsThePendingLabel() {
        var transition = RecordingFeedback.StatusTransition(status("Recording"))
        transition.update(status("Finishing"), at: 10, reduceMotion: false)
        transition.update(status("Recording"), at: 10.08, reduceMotion: false)
        for time in [10.08, 10.16, 10.31, 11] {
            #expect(transition.frame(at: time, reduceMotion: false) == .settled("Recording"))
            #expect(!transition.isAnimating(at: time))
        }
    }

    @Test func interruptedEntranceStartsFromItsPresentedFrame() {
        var transition = RecordingFeedback.StatusTransition(status("Starting"))
        transition.update(status("Writing"), at: 10, reduceMotion: false)
        let before = transition.frame(at: 10.22, reduceMotion: false)
        transition.update(status("Saved"), at: 10.22, reduceMotion: false)
        #expect(transition.frame(at: 10.22, reduceMotion: false) == before)
        #expect(transition.frame(at: 10.371, reduceMotion: false).text == "Saved")
        #expect(transition.frame(at: 10.521, reduceMotion: false) == .settled("Saved"))
    }

    @Test func replacingSessionOrProducerDiscardsEveryPendingLabel() {
        for replacement in [status("New recording", session: "next"), status("New meeting", producer: .meetings)] {
            var transition = RecordingFeedback.StatusTransition(status("Old recording"))
            transition.update(status("Old saved"), at: 10, reduceMotion: false)
            transition.update(replacement, at: 10.08, reduceMotion: false)
            for time in [10.08, 10.16, 10.31] {
                #expect(transition.frame(at: time, reduceMotion: false) == .settled(replacement.label))
                #expect(!transition.isAnimating(at: time))
            }
        }
    }

    @Test func reducedMotionAndInvalidClocksSettleWithoutReplayingPendingText() {
        for (time, reduced) in [(10.08, true), (Double.nan, false), (Double.infinity, false), (9.99, false)] {
            var transition = RecordingFeedback.StatusTransition(status("Starting"))
            transition.update(status("Writing"), at: 10, reduceMotion: false)
            transition.update(status("Saved"), at: time, reduceMotion: reduced)
            #expect(transition.frame(at: 10.09, reduceMotion: true) == .settled("Saved"))
            #expect(transition.frame(at: 10.1, reduceMotion: false) == .settled("Saved"))
            #expect(!transition.isAnimating(at: 10.1))
        }
    }

    @Test func completionRevealMatchesSuppliedCubicAnd350MillisecondDeadline() {
        #expect(abs(RecordingFeedback.Motion.smoothOut(0.3425) - 0.875) < 0.000001)
        #expect(abs(RecordingFeedback.Motion.easeInOut(0.5) - 0.5) < 0.000001)
        let state = snapshot(.completed)
        let beginning = RecordingFeedback.frame(state, at: 10, reduceMotion: false, reduceTransparency: false)
        let middle = RecordingFeedback.frame(state, at: 10 + 0.35 * 0.3425, reduceMotion: false, reduceTransparency: false)
        let complete = RecordingFeedback.frame(state, at: 10.351, reduceMotion: false, reduceTransparency: false)
        #expect(beginning.reveal == 0 && beginning.blur == 1)
        #expect(abs(middle.reveal - 0.875) < 0.000001 && abs(middle.blur - 0.125) < 0.000001)
        #expect(complete.reveal == 1 && complete.blur == 0 && complete.beamOpacity == 0)
        #expect(state.phase == .completed)
    }

    @Test func beamPhaseClockContinuesAcrossWorkAndCompletionWithoutRestarting() {
        var timeline = RecordingFeedback.BeamTimeline(snapshot(.starting))
        timeline.update(snapshot(.writing, began: 12))
        #expect(timeline.elapsed(at: 12) == 2)
        timeline.update(snapshot(.completed, began: 13))
        #expect(timeline.elapsed(at: 13.25) == 3.25)
        #expect(timeline.elapsed(at: .infinity) == 0)
        #expect(timeline.elapsed(at: 9) == 0)
    }

    @Test func beamClockResetsForReplacementAndRetryInsteadOfBorrowingOldMotion() {
        var timeline = RecordingFeedback.BeamTimeline(snapshot(.writing))
        timeline.update(.init(producer: .recordly, phase: .starting, sessionKey: "next", beganAt: 20, label: "Starting"))
        #expect(timeline.elapsed(at: 20.5) == 0.5)
        timeline.update(.init(producer: .recordly, phase: .failed, sessionKey: "next", beganAt: 21, label: "Failed"))
        timeline.update(.init(producer: .recordly, phase: .exporting, sessionKey: "next", beganAt: 22, label: "Retrying"))
        #expect(timeline.elapsed(at: 22.5) == 0.5)
        timeline.update(.init(producer: .meetings, phase: .writing, sessionKey: "next", beganAt: 25, label: "Writing"))
        #expect(timeline.elapsed(at: 25.5) == 0.5)
    }

    // Dense temporal samples establish timing and continuity, not delivered display throughput.
    @Test func statusAndRevealRemainContinuousAt240HertzSampling() {
        var transition = RecordingFeedback.StatusTransition(status("Starting"))
        transition.update(status("Writing"), at: 0, reduceMotion: false)
        var previous = transition.frame(at: 0, reduceMotion: false)
        for index in 0...72 {
            let elapsed = Double(index) / 240
            let frame = transition.frame(at: elapsed, reduceMotion: false)
            #expect([frame.opacity, frame.offsetY, frame.blur].allSatisfy { $0.isFinite })
            #expect((0...1).contains(frame.opacity) && (-4...4).contains(frame.offsetY) && (0...2).contains(frame.blur))
            #expect(frame.text == (index < 36 ? "Starting" : "Writing"))
            if index > 0 && index != 36 {
                #expect(abs(frame.opacity - previous.opacity) <= 0.05)
                #expect(abs(frame.offsetY - previous.offsetY) <= 0.2)
                #expect(abs(frame.blur - previous.blur) <= 0.1)
                #expect(index < 36 ? frame.opacity <= previous.opacity : frame.opacity >= previous.opacity)
            }
            if index == 36 {
                #expect(frame.opacity == 0 && frame.offsetY == 4 && frame.blur == 2)
                #expect(previous.opacity < 0.002, "Changing the status glyph must occur only while it is invisible")
            }
            previous = frame
        }
        #expect(previous == .settled("Writing"))

        let completion = snapshot(.completed, began: 0)
        var lastReveal = 0.0
        for index in 0...84 {
            let frame = RecordingFeedback.frame(completion, at: Double(index) / 240,
                                                 reduceMotion: false, reduceTransparency: false)
            #expect(frame.visible && frame.reveal >= lastReveal && frame.reveal <= 1)
            #expect(frame.reveal - lastReveal <= 0.06)
            #expect(abs(frame.blur - (1 - frame.reveal)) < 0.000001)
            lastReveal = frame.reveal
        }
        #expect(lastReveal == 1, "350ms must remain 350ms at 240Hz sampling")
    }

    @Test func motionUsesElapsedTimeRatherThanRefreshRateOrMissedFrameCount() {
        func samples(rate: Int, reduced: Bool) -> [RecordingFeedback.StatusFrame] {
            var transition = RecordingFeedback.StatusTransition(status("Starting"))
            transition.update(status("Writing"), at: 0, reduceMotion: reduced)
            var sharedFrames: [RecordingFeedback.StatusFrame] = []
            for index in 0...rate {
                let frame = transition.frame(at: Double(index) / Double(rate), reduceMotion: reduced)
                if index % (rate / 60) == 0 { sharedFrames.append(frame) }
            }
            return sharedFrames
        }
        for reduced in [false, true] {
            let baseline = samples(rate: 60, reduced: reduced)
            #expect(samples(rate: 120, reduced: reduced) == baseline)
            #expect(samples(rate: 240, reduced: reduced) == baseline)
            if reduced { #expect(baseline.allSatisfy { $0 == .settled("Writing") }) }
        }

        let completion = snapshot(.completed, began: 0)
        func revealSamples(rate: Int, reduced: Bool) -> [RecordingFeedback.Frame] {
            var sharedFrames: [RecordingFeedback.Frame] = []
            for index in 0...(rate * 5) {
                let frame = RecordingFeedback.frame(completion, at: Double(index) / Double(rate),
                                                     reduceMotion: reduced, reduceTransparency: false)
                if index % (rate / 60) == 0 { sharedFrames.append(frame) }
            }
            return sharedFrames
        }
        for reduced in [false, true] {
            let baseline = revealSamples(rate: 60, reduced: reduced)
            #expect(revealSamples(rate: 120, reduced: reduced) == baseline)
            #expect(revealSamples(rate: 240, reduced: reduced) == baseline)
        }

        var interrupted = RecordingFeedback.StatusTransition(status("Starting"))
        interrupted.update(status("Writing"), at: 0, reduceMotion: false)
        _ = interrupted.frame(at: 1.0 / 240, reduceMotion: false)
        #expect(interrupted.frame(at: 0.301, reduceMotion: false) == .settled("Writing"),
                "A hidden or delayed frame must catch up from time without replaying the missed frames")
        #expect(!RecordingFeedback.frame(completion, at: 5, reduceMotion: false, reduceTransparency: false).visible)
    }

    @Test func completedMotionStopsAtTheLastVisibleTransitionInsteadOfNoticeExpiry() {
        let saved = RecordingFeedback.Snapshot(producer: .recordly, phase: .completed, sessionKey: "fixture", beganAt: 10, label: "Saved")
        var transition = RecordingFeedback.StatusTransition(status("Exporting"))
        transition.update(saved, at: 10, reduceMotion: false)
        #expect(abs(RecordingFeedback.transientMotionRemaining(saved, status: transition, at: 10, reduceMotion: false) - 0.35) < 0.000001)
        #expect(abs(RecordingFeedback.transientMotionRemaining(saved, status: transition, at: 10.2, reduceMotion: false) - 0.15) < 0.000001)
        #expect(RecordingFeedback.transientMotionRemaining(saved, status: transition, at: 10.351, reduceMotion: false) == 0)
        #expect(RecordingFeedback.frame(saved, at: 14.99, reduceMotion: false, reduceTransparency: false).visible)
        #expect(!RecordingFeedback.frame(saved, at: 15, reduceMotion: false, reduceTransparency: false).visible)

        var lateLabel = RecordingFeedback.StatusTransition(status("Exporting"))
        lateLabel.update(saved, at: 10.2, reduceMotion: false)
        #expect(abs(RecordingFeedback.transientMotionRemaining(saved, status: lateLabel, at: 10.2, reduceMotion: false) - 0.3) < 0.000001)
        #expect(RecordingFeedback.transientMotionRemaining(saved, status: lateLabel, at: 10.501, reduceMotion: false) == 0)
    }

    @Test func staticTerminalFeedbackNeverStartsAnAnimationClockWhenReopenedOrReduced() {
        for phase: RecordingFeedback.Phase in [.completed, .failed] {
            let state = snapshot(phase)
            var transition = RecordingFeedback.StatusTransition(state)
            #expect(RecordingFeedback.transientMotionRemaining(state, status: transition, at: 11, reduceMotion: false) == 0)
            transition.update(status("New label"), at: 10, reduceMotion: false)
            #expect(RecordingFeedback.transientMotionRemaining(state, status: transition, at: 10.1, reduceMotion: true) == 0)
            #expect(RecordingFeedback.transientMotionRemaining(state, status: transition, at: .nan, reduceMotion: false) == 0)
        }
    }
}
