import Foundation
import Testing
@testable import ZeusCore

@Suite("Scribe microphone input boundary")
struct ScribeMicrophoneIngressTests {
    private func ready(_ id: ScribeSessionID) -> ScribeMicrophoneIngress {
        let ingress = ScribeMicrophoneIngress(timeToLive: 1.5)
        ingress.begin(session: id)
        ingress.record(state: .unmuted, readStart: 10, readEnd: 10.1)
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
        ingress.record(state: .unmuted, readStart: 10, readEnd: 10.1)
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
            ingress.record(state: state, readStart: 10.1, readEnd: 10.2)
            #expect(!ingress.admit(session: id, start: 10.3, duration: 0.1, now: 10.5, copy: copy))
        }
        ingress.record(state: .unmuted, readStart: 10.2, readEnd: 10.3)
        for start: Double? in [nil, .nan, -.infinity, 10.1, 10.25, 11.65, 12] {
            #expect(!ingress.admit(session: id, start: start, duration: 0.1, now: 11.69, copy: copy))
        }
        for duration in [Double.nan, .infinity, 0, -0.1] {
            #expect(!ingress.admit(session: id, start: 10.4, duration: duration, now: 10.6, copy: copy))
        }
        #expect(!ingress.admit(session: id, start: 10.4, duration: 0.1, now: 12, copy: copy))
        #expect(copies == 0)
    }

    @Test func anotherAppUsingTheMicrophoneNeverWithholdsItAndARestartStartsClean() {
        let first = ScribeSessionID(), second = ScribeSessionID()
        let ingress = ready(first)
        // A call app (or any other app) capturing the input reads as unmuted: the device is not muted.
        let shared = ScribeMuteResolver.resolve(device: .noSwitch)
        ingress.record(state: shared, readStart: 10.3, readEnd: 10.4)
        #expect(ingress.currentState(now: 10.5) == .unmuted)
        ingress.revoke(session: first)
        ingress.begin(session: second)
        _ = ingress.acknowledge(session: second, at: 10.5)
        var copies = 0
        #expect(ingress.admit(session: second, start: 10.6, duration: 0.1, now: 10.8) { copies += 1; return true })
        #expect(copies == 1)
        let report = ingress.takeReport(now: 10.8)
        #expect(report.state == .unmuted)
        #expect(report.withheldSeconds == 0)
    }

    @Test func aMutedReadingWithholdsOnlyUntilTheNextUnmutedReading() {
        let id = ScribeSessionID()
        let ingress = ready(id)
        ingress.record(state: .muted, readStart: 10.3, readEnd: 10.4)
        #expect(ingress.currentState(now: 10.5) == .muted)
        ingress.record(state: .unmuted, readStart: 11, readEnd: 11.1)
        #expect(ingress.currentState(now: 11.3) == .unmuted)
        #expect(ingress.admit(session: id, start: 11.2, duration: 0.1, now: 11.4) { true })
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
        ingress.record(state: .unknown, readStart: 10.2, readEnd: 10.3)
        #expect(!ingress.admit(session: id, start: 10.4, duration: 0.1, now: 10.6) { true })
        ingress.record(state: .unmuted, readStart: 10.7, readEnd: 10.8)
        let report = ingress.takeReport(now: 10.9)
        #expect(report.state == .unknown)
        #expect(report.withheldSeconds == 0.1)
        #expect(ingress.takeReport(now: 10.9).state == .unmuted)
        #expect(ingress.takeReport(now: 10.9).withheldSeconds == 0)
    }

    @Test func anUnidentifiedMicrophoneOwnerNeverExcludesTheMicrophone() {
        let id = ScribeSessionID()
        let ingress = ready(id)
        let unresolved = ScribeProcessRead.activeInput(pid: nil, bundleID: nil)
        // Still noticed as another app using the input (for the shared note) ...
        #expect(unresolved.isExternalInput(excluding: 42))
        #expect(!ScribeProcessRead.activeInput(pid: 42, bundleID: nil).isExternalInput(excluding: 42))
        // ... but admission follows the device alone, during and after that app's use.
        ingress.record(state: ScribeMuteResolver.resolve(device: .notMuted), readStart: 10.3, readEnd: 10.4)
        #expect(ingress.currentState(now: 10.5) == .unmuted)
        #expect(ingress.admit(session: id, start: 10.4, duration: 0.1, now: 10.6) { true })
        ingress.record(state: ScribeMuteResolver.resolve(device: .notMuted), readStart: 11, readEnd: 11.1)
        #expect(ingress.currentState(now: 11.3) == .unmuted)
    }
}
