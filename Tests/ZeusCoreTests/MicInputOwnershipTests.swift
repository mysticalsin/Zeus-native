import Testing
@testable import ZeusCore

@Suite("Microphone input ownership")
struct MicInputOwnershipTests {
    @Test func zeusOpensOnStartAndAlwaysReleasesOnStop() {
        var ownership = MicInputOwnership()
        let started = ownership.apply(.zeusStarted)
        #expect(started == [.openInput])
        #expect(ownership.recordsMicrophone)
        let again = ownership.apply(.zeusStarted)
        #expect(again.isEmpty)
        let stopped = ownership.apply(.zeusStopped)
        #expect(stopped == [.closeInput])
        #expect(ownership.phase == .released)
        #expect(!ownership.recordsMicrophone)
        let stoppedTwice = ownership.apply(.zeusStopped)
        #expect(stoppedTwice.isEmpty)
    }

    @Test func anotherAppNeverTakesTheMicrophoneAwayFromZeus() {
        var ownership = MicInputOwnership()
        _ = ownership.apply(.zeusStarted)
        let shared = ownership.apply(.otherApp(active: true))
        #expect(shared == [.sharedChanged(true)])
        #expect(ownership.recordsMicrophone)
        #expect(ownership.shared)
    }

    @Test func sharingClearsWhenTheOtherAppLetsGoAndNothingLatches() {
        var ownership = MicInputOwnership()
        _ = ownership.apply(.zeusStarted)
        _ = ownership.apply(.otherApp(active: true))
        let released = ownership.apply(.otherApp(active: false))
        #expect(released == [.sharedChanged(false)])
        #expect(!ownership.shared)
        #expect(ownership.recordsMicrophone)
        // Stopping while shared reports the end of sharing; a new recording starts from the latest reading only.
        _ = ownership.apply(.otherApp(active: true))
        let stopped = ownership.apply(.zeusStopped)
        #expect(stopped == [.closeInput, .sharedChanged(false)])
        let quiet = ownership.apply(.otherApp(active: false))
        #expect(quiet.isEmpty)
        let restarted = ownership.apply(.zeusStarted)
        #expect(restarted == [.openInput])
        #expect(!ownership.shared)
    }

    @Test func aDeviceChangeRebuildsTheInputOnlyWhileZeusHoldsIt() {
        var ownership = MicInputOwnership()
        let idle = ownership.apply(.defaultInputChanged)
        #expect(idle.isEmpty)
        _ = ownership.apply(.zeusStarted)
        let listening = ownership.apply(.defaultInputChanged)
        #expect(listening == [.reopenInput])
        _ = ownership.apply(.zeusStopped)
        let afterStop = ownership.apply(.defaultInputChanged)
        #expect(afterStop.isEmpty)
    }

    @Test func otherAppActivityWhileReleasedIsRememberedButNotShared() {
        var ownership = MicInputOwnership()
        let effects = ownership.apply(.otherApp(active: true))
        #expect(effects.isEmpty)
        #expect(!ownership.shared)
        let started = ownership.apply(.zeusStarted)
        #expect(started == [.openInput, .sharedChanged(true)])
    }
}
