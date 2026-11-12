import Foundation
import Testing
@testable import ZeusCore

private let previous = ScribeSessionID()
private let fresh = ScribeSessionID()

/// A card asking about "m1" at 0, alive for 45 s.
private func shownCard() -> ScribePopupLifecycle {
    var card = ScribePopupLifecycle()
    card.handle(.present(key: "m1", lifetime: 45, now: 0))
    return card
}

/// A card whose tap at 1 asked Scribe to start while Scribe sat on `.failed(previous)`.
private func startingCard() -> ScribePopupLifecycle {
    var card = shownCard()
    card.handle(.click(now: 1, scribe: .failed(previous, reason: "old"), microphoneBlocked: false))
    return card
}

@Suite("Scribe meeting card lifecycle")
struct ScribePopupLifecycleTests {
    @Test func aTapAsksForOneStartAndShowsStartingAtOnce() {
        var card = shownCard()
        let effects = card.handle(.click(now: 1, scribe: .idle, microphoneBlocked: false))
        #expect(effects == [.requestStart])
        #expect(card.phase == .starting)
        #expect(card.isBusy)
    }

    @Test func aDoubleTapStartsScribeOnlyOnce() {
        var card = shownCard()
        let first = card.handle(.click(now: 1, scribe: .idle, microphoneBlocked: false))
        let second = card.handle(.click(now: 1.2, scribe: .starting(fresh), microphoneBlocked: false))
        #expect(first == [.requestStart])
        #expect(second.isEmpty)
        #expect(card.phase == .starting)
    }

    @Test func aTapWhileTheAutomaticStartIsRunningConfirmsInsteadOfStartingTwice() {
        var card = shownCard()
        let effects = card.handle(.click(now: 1, scribe: .starting(fresh), microphoneBlocked: false))
        #expect(effects.isEmpty)
        #expect(card.phase == .started)
        #expect(card.session == fresh)
    }

    @Test func aTapAfterTheCallEndedStillStarts() {
        var card = shownCard()
        let gone = card.handle(.meetingGone(now: 2))
        #expect(gone == [.hide])
        #expect(card.phase == .expired)
        let effects = card.handle(.click(now: 2.1, scribe: .idle, microphoneBlocked: false))
        #expect(effects == [.requestStart])
        #expect(card.phase == .starting)
    }

    @Test func theCardNeverExpiresUnderThePointer() {
        var card = shownCard()
        card.handle(.pointer(inside: true, now: 40))
        let held = card.handle(.tick(now: 100))
        #expect(held.isEmpty)
        #expect(card.phase == .shown)
        card.handle(.pointer(inside: false, now: 100))
        let grace = card.handle(.tick(now: 102))
        #expect(grace.isEmpty)
        let gone = card.handle(.tick(now: 104))
        #expect(gone == [.hide, .timedOut])
        #expect(card.phase == .expired)
    }

    @Test func withoutThePointerTheCardTimesOutAsBefore() {
        var card = shownCard()
        let early = card.handle(.tick(now: 44))
        let due = card.handle(.tick(now: 45))
        #expect(early.isEmpty)
        #expect(due == [.hide, .timedOut])
    }

    @Test func aCardWhoseOwnerDecidesItsLifetimeNeverTimesOutByItself() {
        var card = ScribePopupLifecycle()
        card.handle(.present(key: "m1", lifetime: nil, now: 0))
        let effects = card.handle(.tick(now: 10_000))
        #expect(effects.isEmpty)
        #expect(card.phase == .shown)
    }

    @Test func aCaptureFailureIsShownWithItsReason() {
        var card = startingCard()
        card.handle(.scribe(.starting(fresh), now: 1.1))
        card.handle(.scribe(.failed(fresh, reason: "Screen Recording is off."), now: 2))
        #expect(card.phase == .failed(.captureFailed("Screen Recording is off.")))
        #expect(card.isBusy)
        if case .failed(let failure) = card.phase {
            #expect(failure.message == "Scribe couldn't start. Screen Recording is off.")
            #expect(failure.actionTitle == "Try again")
        }
    }

    @Test func theMicrophoneBeingOffIsSaidAndAllowOpensSettings() {
        var card = shownCard()
        let tap = card.handle(.click(now: 1, scribe: .idle, microphoneBlocked: true))
        #expect(tap.isEmpty)
        #expect(card.phase == .failed(.microphoneOff))
        if case .failed(let failure) = card.phase { #expect(failure.actionTitle == "Allow") }
        let allow = card.handle(.click(now: 2, scribe: .idle, microphoneBlocked: true))
        #expect(allow == [.openMicrophoneSettings])
        // Allowed in System Settings meanwhile: the same button now starts.
        let retry = card.handle(.click(now: 30, scribe: .idle, microphoneBlocked: false))
        #expect(retry == [.requestStart])
    }

    @Test func aStaleFailureFromThePreviousMeetingIsNotThisTapsFailure() {
        var card = startingCard()
        card.handle(.scribe(.failed(previous, reason: "old"), now: 1.1))
        #expect(card.phase == .starting)
        card.handle(.scribe(.starting(fresh), now: 1.2))
        card.handle(.scribe(.recording(fresh, since: 2), now: 2))
        #expect(card.phase == .started)
        #expect(card.session == fresh)
    }

    @Test func aTapWhileThePreviousMeetingIsStillSavingSaysSo() {
        var card = shownCard()
        let effects = card.handle(.click(now: 1, scribe: .processing(previous), microphoneBlocked: false))
        #expect(effects.isEmpty)
        #expect(card.phase == .failed(.stillSaving))
        let again = card.handle(.click(now: 20, scribe: .complete(previous), microphoneBlocked: false))
        #expect(again == [.requestStart])
    }

    @Test func noSignOfAStartBecomesAVisibleFailureThenALateStartStillConfirms() {
        var card = startingCard()
        let waiting = card.handle(.tick(now: 5.9))
        #expect(waiting.isEmpty)
        #expect(card.phase == .starting)
        card.handle(.tick(now: 6))
        #expect(card.phase == .failed(.noResponse))
        card.handle(.scribe(.recording(fresh, since: 8), now: 8))
        #expect(card.phase == .started)
    }

    @Test func aStartWaitingOnAPermissionAnswerGetsTheLongerTimeout() {
        var card = startingCard()
        card.handle(.scribe(.starting(fresh), now: 1.1))
        card.handle(.tick(now: 30))
        #expect(card.phase == .starting)
        card.handle(.tick(now: 46))
        #expect(card.phase == .failed(.noResponse))
    }

    @Test func theConfirmationLeavesOnItsOwn() {
        var card = startingCard()
        card.handle(.scribe(.recording(fresh, since: 2), now: 2))
        let stays = card.handle(.tick(now: 3))
        let leaves = card.handle(.tick(now: 3.5))
        #expect(stays.isEmpty)
        #expect(leaves == [.hide])
        #expect(card.phase == .hidden)
    }

    @Test func aNewPromptNeverResetsATapInFlight() {
        var card = startingCard()
        let effects = card.handle(.present(key: "m2", lifetime: 45, now: 2))
        #expect(effects.isEmpty)
        #expect(card.phase == .starting)
        #expect(card.key == "m1")
    }

    @Test func notNowAndStrayTapsAfterItDoNothing() {
        var card = shownCard()
        let close = card.handle(.dismiss(now: 1))
        #expect(close == [.hide])
        let tap = card.handle(.click(now: 1.1, scribe: .idle, microphoneBlocked: false))
        #expect(tap.isEmpty)
        #expect(card.phase == .dismissed)
    }

    @Test func aStrayCloseNeverCancelsAStartInFlight() {
        var card = startingCard()
        let effects = card.handle(.dismiss(now: 1.5))
        #expect(effects.isEmpty)
        #expect(card.phase == .starting)
    }

    @Test func failureWordsUsePlainPunctuation() {
        let failures: [ScribePopupFailure] = [.microphoneOff, .stillSaving, .captureFailed("x"), .noResponse]
        for failure in failures {
            #expect(!failure.message.contains("\u{2014}"))
            #expect(!failure.message.isEmpty)
        }
    }
}
