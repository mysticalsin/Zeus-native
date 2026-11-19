import Foundation
import Testing
@testable import ZeusCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// A calendar meeting that starts `startsIn` seconds after `t0`.
private func calendarMeeting(title: String = "Weekly sync", startsIn: TimeInterval = 120) -> ScribeMeeting {
    let slot = ScribeCalendarSlot(id: "slot-1", title: title, start: t0.addingTimeInterval(startsIn), hasCallLink: true)
    return ScribeMeeting(key: slot.id, title: title, callApp: .other("Synthetic"), slot: slot)
}

/// A call with no calendar meeting behind it.
private func bareCall() -> ScribeMeeting {
    ScribeMeeting(key: "call:Synthetic", title: "Synthetic call", callApp: .other("Synthetic"))
}

private struct Row {
    var name: String
    var card: ScribeMeetingCard
    var title: String
    var status: String
    var primary: String?
    var cancel: String?
    var dismiss: Bool
}

private let m = calendarMeeting()

private let rows: [Row] = [
    Row(name: "offer", card: .offer(m, blocked: nil), title: "Weekly sync", status: "in 2 min",
        primary: "Record", cancel: nil, dismiss: true),
    Row(name: "offer, not chosen", card: .offer(m, blocked: .notChosen), title: "Weekly sync", status: "in 2 min",
        primary: "Record", cancel: nil, dismiss: true),
    Row(name: "offer, no opt-in", card: .offer(m, blocked: .noOptIn), title: "Weekly sync", status: "in 2 min",
        primary: "Record", cancel: nil, dismiss: true),
    Row(name: "offer, microphone not asked", card: .offer(m, blocked: .microphoneNotAsked), title: "Weekly sync",
        status: "Microphone not allowed yet", primary: "Record", cancel: nil, dismiss: true),
    Row(name: "offer, microphone denied", card: .offer(m, blocked: .microphoneDenied), title: "Weekly sync",
        status: "Microphone is off for Zeus", primary: "Record", cancel: nil, dismiss: true),
    Row(name: "offer, first recording owed", card: .offer(m, blocked: .firstRecordingOwed), title: "Weekly sync",
        status: "Automatic start needs one recording first", primary: "Record", cancel: nil, dismiss: true),
    Row(name: "offer, a call with no meeting", card: .offer(bareCall(), blocked: nil), title: "Call", status: "now",
        primary: "Record", cancel: nil, dismiss: true),
    Row(name: "offer, empty title", card: .offer(calendarMeeting(title: "  \n"), blocked: nil), title: "Meeting",
        status: "in 2 min", primary: "Record", cancel: nil, dismiss: true),
    Row(name: "countdown", card: .countdown(m, seconds: 5, deadline: 105, total: 5), title: "Weekly sync",
        status: "Recording starts in 5", primary: nil, cancel: "Cancel", dismiss: false),
    Row(name: "waiting", card: .waiting(m), title: "Weekly sync", status: "Starts once your last meeting is saved",
        primary: nil, cancel: "Cancel", dismiss: false),
    Row(name: "starting, cancellable", card: .starting(m, cancellable: true), title: "Weekly sync", status: "Starting",
        primary: nil, cancel: "Cancel", dismiss: false),
    Row(name: "starting, not cancellable", card: .starting(m, cancellable: false), title: "Weekly sync",
        status: "Starting", primary: nil, cancel: nil, dismiss: false),
    Row(name: "recording", card: .recording(m), title: "Weekly sync", status: "Recording", primary: nil, cancel: nil,
        dismiss: false),
    Row(name: "failed, microphone off", card: .failed(m, .microphoneOff), title: "Weekly sync",
        status: "Microphone is off for Zeus", primary: "Allow", cancel: nil, dismiss: true),
    Row(name: "failed, still saving", card: .failed(m, .stillSaving), title: "Weekly sync",
        status: "Still saving your last meeting", primary: "Try again", cancel: nil, dismiss: true),
    Row(name: "failed, capture reason", card: .failed(m, .captureFailed("No input device")), title: "Weekly sync",
        status: "No input device", primary: "Try again", cancel: nil, dismiss: true),
    Row(name: "failed, blank capture reason", card: .failed(m, .captureFailed(" \n")), title: "Weekly sync",
        status: "Couldn't start", primary: "Try again", cancel: nil, dismiss: true),
    Row(name: "failed, no response", card: .failed(m, .noResponse), title: "Weekly sync", status: "Didn't start. Try again.",
        primary: "Try again", cancel: nil, dismiss: true),
    Row(name: "next meeting", card: .next(m), title: "Weekly sync", status: "in 2 min", primary: "Switch", cancel: nil,
        dismiss: true),
]

@Suite("Scribe meeting card contract")
struct ScribeMeetingCardTests {
    @Test func eachCardHasItsTitleAndStatus() {
        for row in rows {
            #expect(row.card.meeting.map(ScribeMeetingCardText.title) == row.title, "\(row.name)")
            #expect(ScribeMeetingCardText.status(row.card, now: t0) == row.status, "\(row.name)")
        }
    }

    @Test func aMeetingWithASlotIsTitledByTheSlotNotByTheCallApp() {
        let slot = ScribeCalendarSlot(id: "slot-2", title: "Planning", start: t0.addingTimeInterval(120), hasCallLink: true)
        let meeting = ScribeMeeting(key: slot.id, title: "Planning", callApp: .other("Synthetic Call App"), slot: slot)
        #expect(ScribeMeetingCardText.title(meeting) == "Planning")
        #expect(ScribeMeetingCardText.label(.offer(meeting, blocked: nil), now: t0) == "Planning, in 2 min")
        let call = ScribeMeeting(key: "call:Synthetic Call App", title: "Synthetic Call App", callApp: .other("Synthetic Call App"))
        #expect(ScribeMeetingCardText.title(call) == "Call")
    }

    @Test func eachCardHasItsControls() {
        for row in rows {
            #expect(ScribeMeetingCardText.primary(row.card) == row.primary, "\(row.name)")
            #expect(ScribeMeetingCardText.cancel(row.card) == row.cancel, "\(row.name)")
            #expect(ScribeMeetingCardText.canDismiss(row.card) == row.dismiss, "\(row.name)")
        }
    }

    @Test func aVisibleCardOffersExactlyOneActionExceptWhileItIsOnItsWay() {
        for row in rows {
            let controls = [ScribeMeetingCardText.primary(row.card), ScribeMeetingCardText.cancel(row.card)].compactMap { $0 }
            switch row.card {
            case .recording, .starting(_, cancellable: false):
                #expect(controls.isEmpty, "\(row.name)")
            default:
                #expect(controls.count == 1, "\(row.name)")
            }
        }
    }

    @Test func theCountdownHasNoPrimaryAndNoDismiss() {
        let card = ScribeMeetingCard.countdown(m, seconds: 3, deadline: 103, total: 5)
        #expect(ScribeMeetingCardText.primary(card) == nil)
        #expect(ScribeMeetingCardText.cancel(card) == "Cancel")
        #expect(!ScribeMeetingCardText.canDismiss(card))
    }

    @Test func recordingIsTheStatusOfTheRecordingCardOnly() {
        for row in rows {
            let status = ScribeMeetingCardText.status(row.card, now: t0)
            if case .recording = row.card {
                #expect(status == "Recording")
            } else {
                #expect(status != "Recording", "\(row.name)")
            }
        }
    }

    @Test func aHiddenCardHasNothingToSay() {
        let card = ScribeMeetingCard.hidden
        #expect(card.meeting == nil)
        #expect(ScribeMeetingCardText.status(card, now: t0).isEmpty)
        #expect(ScribeMeetingCardText.label(card, now: t0).isEmpty)
        #expect(ScribeMeetingCardText.announcement(card, now: t0).isEmpty)
        #expect(ScribeMeetingCardText.primary(card) == nil)
        #expect(ScribeMeetingCardText.cancel(card) == nil)
        #expect(!ScribeMeetingCardText.canDismiss(card))
        #expect(ScribeMeetingCardText.accessibilityValue(card) == nil)
    }

    @Test func oneSymbolServesEveryCard() {
        #expect(ScribeMeetingCardText.symbol == "video.fill")
    }

    // MARK: Time text

    @Test(arguments: [
        (121.0, "in 3 min"), (120.0, "in 2 min"), (61.0, "in 2 min"), (60.0, "in 1 min"),
        (1.0, "in 1 min"), (0.0, "now"), (-1.0, "now"), (-299.0, "now"),
    ])
    func theTimeRoundsMinutesUpBeforeTheStartAndSaysNowAfter(_ untilStart: Double, _ text: String) {
        #expect(ScribeMeetingCardText.time(startsAt: t0.addingTimeInterval(untilStart), now: t0) == text)
    }

    @Test func aCardReadsTheTimeFromTheWallClockItIsGiven() {
        let card = ScribeMeetingCard.offer(m, blocked: nil)
        #expect(ScribeMeetingCardText.status(card, now: t0.addingTimeInterval(60)) == "in 1 min")
        #expect(ScribeMeetingCardText.status(card, now: t0.addingTimeInterval(120)) == "now")
    }

    // MARK: Countdown arithmetic

    @Test(arguments: [
        (100.0, 5), (100.1, 5), (101.0, 4), (102.5, 3), (104.0, 1), (104.9, 1), (105.0, 0), (106.0, 0),
    ])
    func theSecondsCountTheOneInProgress(_ now: Double, _ expected: Int) {
        #expect(ScribeMeetingCardText.seconds(deadline: 105, now: now) == expected)
    }

    @Test func theRingIsTheShareLeftClampedToZeroAndOne() {
        #expect(ScribeMeetingCardText.ring(deadline: 105, now: 100, total: 5) == 1)
        #expect(ScribeMeetingCardText.ring(deadline: 105, now: 102.5, total: 5) == 0.5)
        #expect(ScribeMeetingCardText.ring(deadline: 105, now: 105, total: 5) == 0)
        #expect(ScribeMeetingCardText.ring(deadline: 105, now: 106, total: 5) == 0)
        #expect(ScribeMeetingCardText.ring(deadline: 105, now: 99, total: 5) == 1)
        #expect(ScribeMeetingCardText.ring(deadline: 105, now: 100, total: 0) == 0)
    }

    // MARK: Accessibility

    @Test func theLabelIsTheTitleAndTheStatus() {
        #expect(ScribeMeetingCardText.label(.offer(m, blocked: nil), now: t0) == "Weekly sync, in 2 min")
        #expect(ScribeMeetingCardText.label(.recording(m), now: t0) == "Weekly sync, Recording")
        #expect(ScribeMeetingCardText.label(.offer(bareCall(), blocked: nil), now: t0) == "Call, now")
    }

    @Test func theCountdownIsAnnouncedOnceNotEachSecond() {
        let five = ScribeMeetingCard.countdown(m, seconds: 5, deadline: 105, total: 5)
        let two = ScribeMeetingCard.countdown(m, seconds: 2, deadline: 105, total: 5)
        #expect(ScribeMeetingCardText.announcement(five, now: t0) == "Weekly sync, Recording starts in 5")
        #expect(ScribeMeetingCardText.announcement(two, now: t0) == ScribeMeetingCardText.announcement(five, now: t0))
    }

    @Test func otherCardsAreAnnouncedAsTheyAreLabelled() {
        for row in rows {
            if case .countdown = row.card { continue }
            #expect(ScribeMeetingCardText.announcement(row.card, now: t0) == ScribeMeetingCardText.label(row.card, now: t0),
                    "\(row.name)")
        }
    }

    @Test func cancelExposesTheSecondsAsItsValue() {
        let card = ScribeMeetingCard.countdown(m, seconds: 3, deadline: 103, total: 5)
        #expect(ScribeMeetingCardText.accessibilityValue(card) == "3")
        for row in rows {
            if case .countdown = row.card { continue }
            #expect(ScribeMeetingCardText.accessibilityValue(row.card) == nil, "\(row.name)")
        }
    }

    @Test func theDismissControlIsNamedDismiss() {
        #expect(ScribeMeetingCardText.dismiss == "Dismiss")
    }

    // MARK: Words

    @Test func noWordOnACardHasADashOrAProductName() {
        var words: [String] = [ScribeMeetingCardText.symbol, ScribeMeetingCardText.dismiss]
        for row in rows {
            words.append(ScribeMeetingCardText.status(row.card, now: t0))
            words.append(ScribeMeetingCardText.label(row.card, now: t0))
            words.append(ScribeMeetingCardText.announcement(row.card, now: t0))
            words.append(contentsOf: [ScribeMeetingCardText.primary(row.card), ScribeMeetingCardText.cancel(row.card),
                                      ScribeMeetingCardText.accessibilityValue(row.card)].compactMap { $0 })
        }
        for block in ScribeAutoStartBlock.allCases {
            words.append(contentsOf: ScribeMeetingCardText.reason(block).map { [$0] } ?? [])
        }
        words.append(contentsOf: [ScribeMeetingCardText.reason(.microphoneOff), ScribeMeetingCardText.reason(.stillSaving),
                                  ScribeMeetingCardText.reason(.captureFailed("")), ScribeMeetingCardText.reason(.noResponse)])
        words.append(ScribeMeetingCardText.title(bareCall()))
        let banned = ["\u{2014}", "\u{2013}", "-", "Teams", "Zoom", "Webex", "Google", "Microsoft", "Slack", "Scribe"]
        for word in words {
            for item in banned {
                #expect(!word.contains(item), "\"\(word)\" contains \"\(item)\"")
            }
        }
    }

    @Test func aBlockOnlyHasAReasonWhenThePersonCanActOnIt() {
        #expect(ScribeMeetingCardText.reason(.notChosen) == nil)
        #expect(ScribeMeetingCardText.reason(.noOptIn) == nil)
        #expect(ScribeMeetingCardText.reason(.microphoneNotAsked) == "Microphone not allowed yet")
        #expect(ScribeMeetingCardText.reason(.microphoneDenied) == "Microphone is off for Zeus")
        #expect(ScribeMeetingCardText.reason(.firstRecordingOwed) == "Automatic start needs one recording first")
    }

    // MARK: Placement

    @Test func theCardSitsAtTheTopRightOfTheScreenWithTheMargin() {
        let size = CGSize(width: 340, height: 80)
        let origin = ScribeMeetingCardPlacement.origin(size: size, visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), margin: 16)
        #expect(origin == CGPoint(x: 1084, y: 804))
    }

    @Test func thePlacementFollowsTheScreenFrameOnAnotherDisplay() {
        let size = CGSize(width: 340, height: 80)
        let right = ScribeMeetingCardPlacement.origin(size: size, visibleFrame: CGRect(x: 1440, y: 25, width: 1920, height: 1055), margin: 16)
        #expect(right == CGPoint(x: 1440 + 1920 - 340 - 16, y: 25 + 1055 - 80 - 16))
        let left = ScribeMeetingCardPlacement.origin(size: size, visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), margin: 16)
        #expect(left == CGPoint(x: -356, y: 984))
    }

    @Test func theCardStaysInsideAFrameSmallerThanItself() {
        let origin = ScribeMeetingCardPlacement.origin(size: CGSize(width: 340, height: 80),
                                                       visibleFrame: CGRect(x: 10, y: 20, width: 200, height: 50), margin: 16)
        #expect(origin == CGPoint(x: 10, y: 20))
    }
}
