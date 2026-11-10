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
        #expect(initial.visible && initial.reveal == 0 && initial.glow > 0)
        #expect(revealed.visible && revealed.reveal == 1)
        #expect(settled.visible && settled.glow == 0 && settled.frost == 0)
        #expect(!RecordingFeedback.frame(state, at: 15, reduceMotion: false, reduceTransparency: false).visible)
    }

    @Test func reducedMotionIsStaticWhileStatusRemainsReadable() {
        for phase: RecordingFeedback.Phase in [.starting, .finishing, .writing, .exporting, .completed, .failed] {
            let a = RecordingFeedback.frame(snapshot(phase), at: 10.1, reduceMotion: true, reduceTransparency: false)
            let b = RecordingFeedback.frame(snapshot(phase), at: 13, reduceMotion: true, reduceTransparency: false)
            #expect(a == b)
            #expect(a.reveal == 1 && a.sweep == 0.5)
        }
    }

    @Test func reduceTransparencyEliminatesFrost() {
        for phase: RecordingFeedback.Phase in [.starting, .writing, .completed, .failed] {
            #expect(RecordingFeedback.frame(snapshot(phase), at: 10.3, reduceMotion: false, reduceTransparency: true).frost == 0)
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
            #expect(working.glow.isFinite && working.frost.isFinite && working.sweep.isFinite)
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
}
