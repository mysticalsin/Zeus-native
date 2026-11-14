import Foundation
import Testing
@testable import ZeusCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let identity = ScribeCallProcessIdentity(pid: 4242, bundleID: "synthetic.call", launchedAt: 10)

private func slot(title: String = "Weekly sync", guests: [String] = [], app: ScribeCallApp? = nil) -> ScribeCalendarSlot {
    ScribeCalendarSlot(id: "slot-1", title: title, start: t0, attendeeNames: guests, hasCallLink: app != nil, callApp: app)
}

private func scheduled(_ slot: ScribeCalendarSlot) -> ScribeMeeting {
    ScribeMeeting(key: slot.id, title: slot.title, callApp: slot.callApp, slot: slot)
}

@Suite("Scribe meeting context")
struct ScribeMeetingContextTests {
    @Test func aSlotMeetingCarriesItsTitleAndGuests() {
        let meeting = scheduled(slot(title: "  Roadmap \n", guests: ["Ada Fixture", "Grace Fixture"]))
        let context = meeting.context(callIdentity: nil)
        #expect(context == ScribeMeetingContext(title: "Roadmap", attendeeNames: ["Ada Fixture", "Grace Fixture"]))
    }

    @Test func guestsPassThroughTheNameCleaner() {
        var raw = slot()
        raw.attendeeNames = ["Ada Fixture", "ada  fixture", "ada@example.invalid", "  ", "Grace Fixture"]
        let context = scheduled(raw).context(callIdentity: nil)
        #expect(context.attendeeNames == ["Ada Fixture", "Grace Fixture"])
    }

    @Test func aCallWithNoSlotKeepsTheRecapTitleOfItsApp() {
        let call = ScribeMeeting(key: "call:Synthetic", title: "Call", callApp: .other("Synthetic"), isLive: true)
        let context = call.context(callIdentity: nil)
        #expect(context.title == "Synthetic call")
        #expect(context.attendeeNames.isEmpty)
        let teams = ScribeMeeting(key: "call:Teams", title: "Call", callApp: .teams, isLive: true)
        #expect(teams.context(callIdentity: nil).title == "Teams call")
    }

    @Test func aMeetingWithNeitherSlotNorAppHasNoTitle() {
        let bare = ScribeMeeting(key: "call:none", title: "Call", callApp: nil, isLive: true)
        #expect(bare.context(callIdentity: nil) == ScribeMeetingContext())
    }

    @Test func anEmptyTitleIsNil() {
        #expect(scheduled(slot(title: "")).context(callIdentity: nil).title == nil)
        #expect(scheduled(slot(title: "  \n\t")).context(callIdentity: nil).title == nil)
    }

    @Test func aHeadsUpStartHasNoCallBinding() {
        let meeting = scheduled(slot(app: .other("Synthetic")))
        #expect(!meeting.isLive)
        #expect(meeting.context(callIdentity: identity).callIdentity == nil)
    }

    @Test func aLiveMeetingKeepsItsBinding() {
        let live = slot(title: "Live sync", app: .other("Synthetic"))
        let calendarCall = ScribeMeeting(key: live.id, title: live.title, callApp: .other("Synthetic"), slot: live, isLive: true)
        #expect(calendarCall.context(callIdentity: identity).callIdentity == identity)
        let bareCall = ScribeMeeting(key: "call:Synthetic", title: "Call", callApp: .other("Synthetic"), isLive: true)
        #expect(bareCall.context(callIdentity: identity).callIdentity == identity)
    }

    @Test func aLiveMeetingWithoutAnIdentityStaysUnbound() {
        let bareCall = ScribeMeeting(key: "call:Synthetic", title: "Call", callApp: .other("Synthetic"), isLive: true)
        #expect(bareCall.context(callIdentity: nil).callIdentity == nil)
    }

    @Test func theEmptyContextHasNothing() {
        let none = ScribeMeetingContext()
        #expect(none.title == nil)
        #expect(none.attendeeNames.isEmpty)
        #expect(none.callIdentity == nil)
    }
}
