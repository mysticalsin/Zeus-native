import Foundation
import Testing
@testable import ZeusCore

@Suite("Face presence status")
struct FacePresenceStatusTests {
    typealias Machine = FacePresenceMachine

    static func status(_ state: Machine.State, lockAfter: Double = 120, at uptime: Double = 0) -> FacePresenceStatus {
        FacePresenceStatus.make(state: state, lockAfter: lockAfter, uptime: uptime)
    }

    @Test func everyStateHasItsWordAndSymbol() {
        let rows: [(Machine.State, String, String)] = [
            (.off, "Off", "person.crop.circle"),
            (.needsCameraConsent, "Needs camera", "video.slash"),
            (.enrolling(token: 1), "Enrolling", "person.crop.circle.badge.plus"),
            (.watching(since: 0), "Watching", "eye"),
            (.present(lastSeen: 0), "Present", "person.crop.circle.badge.checkmark"),
            (.paused(.lockedByZeus), "Locked", "lock"),
            (.paused(.launch), "Paused", "pause.circle"),
            (.paused(.screenLocked), "Paused", "pause.circle"),
            (.paused(.asleep), "Paused", "pause.circle"),
            (.paused(.noFace), "Paused", "pause.circle"),
            (.paused(.zeusCapture), "Paused", "pause.circle"),
            (.unavailable(.camera), "Unavailable", "exclamationmark.triangle"),
            (.unavailable(.lock), "Unavailable", "exclamationmark.triangle"),
            (.unavailable(.vault), "Unavailable", "exclamationmark.triangle"),
        ]
        for (state, word, symbol) in rows {
            let status = Self.status(state)
            #expect(status.word == word, "\(state)")
            #expect(status.symbol == symbol, "\(state)")
            #expect(status.countdown == nil, "\(state)")
            #expect(status.accessibilityText == "Face presence status: \(word)", "\(state)")
        }
    }

    @Test func awayShowsTheCountdownInTheWord() {
        // Away since 100 with two minutes: 18 seconds in, 1:42 are left.
        let status = Self.status(.away(since: 100), lockAfter: 120, at: 118)
        #expect(status.word == "Away 1:42")
        #expect(status.symbol == "person.crop.circle.badge.clock")
        #expect(status.countdown == "1:42")
    }

    @Test func statusNamesTheCountdownForVoiceOver() {
        let status = Self.status(.away(since: 100), lockAfter: 120, at: 118)
        #expect(status.accessibilityText == "Face presence status: Away, 1 minute 42 seconds left")
        let one = Self.status(.away(since: 0), lockAfter: 60, at: 0)
        #expect(one.accessibilityText == "Face presence status: Away, 1 minute left")
        let seconds = Self.status(.away(since: 0), lockAfter: 30, at: 29)
        #expect(seconds.accessibilityText == "Face presence status: Away, 1 second left")
        let two = Self.status(.away(since: 0), lockAfter: 300, at: 0)
        #expect(two.accessibilityText == "Face presence status: Away, 5 minutes left")
    }

    @Test func countdownTextUsesMinutesAndSeconds() {
        #expect(FacePresenceStatus.countdownText(seconds: 120) == "2:00")
        #expect(FacePresenceStatus.countdownText(seconds: 102) == "1:42")
        #expect(FacePresenceStatus.countdownText(seconds: 61) == "1:01")
        #expect(FacePresenceStatus.countdownText(seconds: 60) == "1:00")
        #expect(FacePresenceStatus.countdownText(seconds: 59) == "0:59")
        #expect(FacePresenceStatus.countdownText(seconds: 9) == "0:09")
        #expect(FacePresenceStatus.countdownText(seconds: 600) == "10:00")
        // A part of a second counts as the whole second still to go, so 0:00 shows only when the lock is due.
        #expect(FacePresenceStatus.countdownText(seconds: 0.2) == "0:01")
        #expect(FacePresenceStatus.countdownText(seconds: 101.5) == "1:42")
        // Below zero, or not a number, never shows a negative time.
        #expect(FacePresenceStatus.countdownText(seconds: 0) == "0:00")
        #expect(FacePresenceStatus.countdownText(seconds: -5) == "0:00")
        #expect(FacePresenceStatus.countdownText(seconds: .nan) == "0:00")
    }

    @Test func spokenDurationUsesWordsAndTheRightPlural() {
        #expect(FacePresenceStatus.spokenDuration(seconds: 102) == "1 minute 42 seconds")
        #expect(FacePresenceStatus.spokenDuration(seconds: 121) == "2 minutes 1 second")
        #expect(FacePresenceStatus.spokenDuration(seconds: 600) == "10 minutes")
        #expect(FacePresenceStatus.spokenDuration(seconds: 1) == "1 second")
        #expect(FacePresenceStatus.spokenDuration(seconds: 0) == "0 seconds")
        #expect(FacePresenceStatus.spokenDuration(seconds: -3) == "0 seconds")
    }

    @Test func theCountdownReachesZeroOnlyWhenTheLockIsDue() {
        let before = Self.status(.away(since: 100), lockAfter: 120, at: 219.5)
        #expect(before.countdown == "0:01")
        let due = Self.status(.away(since: 100), lockAfter: 120, at: 220)
        #expect(due.countdown == "0:00")
        let past = Self.status(.away(since: 100), lockAfter: 120, at: 400)
        #expect(past.countdown == "0:00")
        #expect(past.word == "Away 0:00")
    }

    @Test func theMachineGivesItsOwnStatus() {
        var machine = FacePresenceMachine()
        _ = machine.handle(.switchOn(camera: .authorized, enabledFaces: 1, canLock: true, vaultReadable: true, uptime: 100))
        _ = machine.handle(.observed(.notOwner, uptime: 101))
        let status = machine.status(at: 158)
        #expect(status.word == "Away 1:02")
        #expect(status == FacePresenceStatus.make(state: machine.state, lockAfter: machine.lockAfter, uptime: 158))
    }
}
