import Foundation
import Testing
@testable import ZeusCore

@Suite("Scribe microphone input boundary")
struct ScribeMicrophoneIngressTests {
    private func ready(_ id: ScribeSessionID) -> ScribeMicrophoneIngress {
        let ingress = ScribeMicrophoneIngress(timeToLive: 1.5)
        ingress.begin(session: id)
        ingress.record(state: .unmuted, readStart: 10, readEnd: 10.1, externalInputDetected: false)
        _ = ingress.acknowledge(session: id, at: 10.2)
        return ingress
    }

    @Test func onlyAcknowledgedFreshEvidenceCanTouchSampleMemory() {
        let id = ScribeSessionID()
        let ingress = ScribeMicrophoneIngress()
        var copies = 0
        let copy = { copies += 1; return true }
        #expect(!ingress.admit(session: id, start: 10.3, duration: 0.1, now: 10.5, copy: copy))
        ingress.begin(session: id)
        ingress.record(state: .unmuted, readStart: 10, readEnd: 10.1, externalInputDetected: false)
        #expect(!ingress.admit(session: id, start: 10.3, duration: 0.1, now: 10.5, copy: copy))
        #expect(ingress.acknowledge(session: id, at: 10.2))
        #expect(ingress.admit(session: id, start: 10.3, duration: 0.1, now: 10.5, copy: copy))
        #expect(copies == 1)
    }

    @Test func mutedUnknownExpiredAndInvalidTimingNeverInvokeTheCopy() {
        let id = ScribeSessionID()
        let ingress = ready(id)
        var copies = 0
        let copy = { copies += 1; return true }
        for state: ScribeMuteState in [.muted, .unknown] {
            ingress.record(state: state, readStart: 10.1, readEnd: 10.2, externalInputDetected: false)
            #expect(!ingress.admit(session: id, start: 10.3, duration: 0.1, now: 10.5, copy: copy))
        }
        ingress.record(state: .unmuted, readStart: 10.2, readEnd: 10.3, externalInputDetected: false)
        for start: Double? in [nil, .nan, -.infinity, 10.1, 10.25, 11.65, 12] {
            #expect(!ingress.admit(session: id, start: start, duration: 0.1, now: 11.69, copy: copy))
        }
        for duration in [Double.nan, .infinity, 0, -0.1] {
            #expect(!ingress.admit(session: id, start: 10.4, duration: duration, now: 10.6, copy: copy))
        }
        #expect(!ingress.admit(session: id, start: 10.4, duration: 0.1, now: 12, copy: copy))
        #expect(copies == 0)
    }

    @Test func externalOwnerDisappearanceAndRecordingRestartCannotUnmute() {
        let first = ScribeSessionID(), second = ScribeSessionID()
        let ingress = ready(first)
        ingress.record(state: .unknown, readStart: 10.3, readEnd: 10.4, externalInputDetected: true)
        ingress.record(state: .unmuted, readStart: 11, readEnd: 11.1, externalInputDetected: false)
        #expect(ingress.currentState(now: 11.3) == .unknown)
        ingress.revoke(session: first)
        ingress.begin(session: second)
        _ = ingress.acknowledge(session: second, at: 11.2)
        var copies = 0
        #expect(!ingress.admit(session: second, start: 11.3, duration: 0.1, now: 11.5) { copies += 1; return true })
        #expect(copies == 0)
        let report = ingress.takeReport(now: 11.5)
        #expect(report.externalInputLatched)
        #expect(report.withheldSeconds == 0.1)
    }

    @Test func lateExternalOwnerEvidenceStillLatchesAgainstAFresherEmptyScan() {
        let id = ScribeSessionID()
        let ingress = ready(id)
        ingress.record(state: .unmuted, readStart: 11, readEnd: 11.1, externalInputDetected: false)
        ingress.record(state: .unknown, readStart: 10.5, readEnd: 11.2, externalInputDetected: true)
        #expect(ingress.currentState(now: 11.3) == .unknown)
        #expect(ingress.hasExternalInput)
    }

    @Test func contendedCallbackReturnsWithoutTouchingSamples() {
        let id = ScribeSessionID()
        let ingress = ready(id)
        var innerCopies = 0
        var innerAdmitted = true
        #expect(ingress.admit(session: id, start: 10.3, duration: 0.1, now: 10.5) {
            innerAdmitted = ingress.admit(session: id, start: 10.3, duration: 0.1, now: 10.5) {
                innerCopies += 1
                return true
            }
            return true
        })
        #expect(!innerAdmitted)
        #expect(innerCopies == 0)
    }

    @Test func stopClosesAdmissionAndStaleShutdownCannotCloseANewSession() {
        let old = ScribeSessionID(), new = ScribeSessionID()
        let ingress = ready(old)
        ingress.revoke(session: old)
        #expect(!ingress.acknowledge(session: old, at: 10.3))
        #expect(!ingress.admit(session: old, start: 10.4, duration: 0.1, now: 10.6) { Issue.record("Stopped copy ran"); return true })
        ingress.begin(session: new)
        _ = ingress.acknowledge(session: new, at: 10.3)
        ingress.revoke(session: old)
        #expect(ingress.admit(session: new, start: 10.4, duration: 0.1, now: 10.6) { true })
    }

    @Test func freshEvidenceCannotEraseTheReportOfPreviouslyWithheldAudio() {
        let id = ScribeSessionID()
        let ingress = ready(id)
        ingress.record(state: .unknown, readStart: 10.2, readEnd: 10.3, externalInputDetected: false)
        #expect(!ingress.admit(session: id, start: 10.4, duration: 0.1, now: 10.6) { true })
        ingress.record(state: .unmuted, readStart: 10.7, readEnd: 10.8, externalInputDetected: false)
        let report = ingress.takeReport(now: 10.9)
        #expect(report.state == .unknown)
        #expect(report.withheldSeconds == 0.1)
        #expect(ingress.takeReport(now: 10.9).state == .unmuted)
        #expect(ingress.takeReport(now: 10.9).withheldSeconds == 0)
    }

    @Test func positivelyActiveButUnresolvedOwnerRemainsExcludedAfterItReleasesInput() {
        let id = ScribeSessionID()
        let ingress = ready(id)
        let unresolved = ScribeProcessRead.activeInput(pid: nil, bundleID: nil)
        #expect(ScribeScanReducer.reduce(reads: [unresolved], running: [], ownPID: 42) == .incomplete)
        ingress.record(state: .unknown, readStart: 10.3, readEnd: 10.4,
                       externalInputDetected: unresolved.isExternalInput(excluding: 42))
        ingress.record(state: .unmuted, readStart: 11, readEnd: 11.1, externalInputDetected: false)
        #expect(ingress.currentState(now: 11.3) == .unknown)
        #expect(!ScribeProcessRead.activeInput(pid: 42, bundleID: nil).isExternalInput(excluding: 42))
    }
}
