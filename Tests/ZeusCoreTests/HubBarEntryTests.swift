import Foundation
import Testing
@testable import ZeusCore

/// The shortcut and openWindow open the panel on Chat. They do not open the floating window.
/// With sound opted out, a finish is silent. With sound opted in, one chime, and not another inside 3 seconds.
/// The 20 second and 3 second windows stay the existing constants.
@Suite("Hub bar entry")
struct HubBarEntryTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func optedIn() -> HubBarEntry {
        var entry = HubBarEntry()
        _ = entry.setOptIn(true)
        return entry
    }

    private func tail(_ log: HubBarLog) -> String {
        let line = FlightRecorder.line(
            RecordedEvent(date: Date(timeIntervalSince1970: 0), source: log.source, stage: log.stage, detail: log.detail))
        guard let space = line.firstIndex(of: " ") else { return line }
        return String(line[line.index(after: space)...])
    }

    private func expectTail(_ logs: [HubBarLog], _ index: Int = 0, _ expected: String) {
        #expect(logs.count > index)
        if logs.indices.contains(index) { #expect(tail(logs[index]) == expected) }
    }

    private func tick(
        _ entry: inout HubBarEntry,
        _ sessions: [HubBarSession],
        at now: Date,
        approval: Bool = false,
        approvalID: String? = nil,
        startEnabled: Bool = false,
        systemFinishSound: Bool = false
    ) -> HubBarEntryEffect {
        let effect = entry.tick(
            sessions: sessions,
            approvalVisible: approval,
            approvalSessionID: approvalID,
            at: now,
            startEnabled: startEnabled,
            systemFinishSound: systemFinishSound)
        entry = effect.entry
        return effect
    }

    @Test func everyEntryPairOpensThePanelOnChat() {
        let open = HubBarPlace(presentation: .panel, tab: .chat, opensFloatingWindow: false)
        for presentation in HubBarPresentation.allCases {
            for tab in HubBarTab.allCases {
                for request in HubBarEntryRequest.allCases {
                    let start = HubBarPlace(presentation: presentation, tab: tab, opensFloatingWindow: true)
                    #expect(HubBarEntry.nextPlace(start, request) == open)
                    var entry = HubBarEntry(place: start)
                    let effect = entry.enter(request)
                    #expect(effect.opensFloatingWindow == false)
                    #expect(effect.navigation == open)
                    #expect(effect.cues.isEmpty)
                    #expect(effect.playsSystemFinishSound == false)
                    #expect(effect.logs == [HubBarLog(source: "chat", stage: "tab", detail: "chat")])
                    expectTail(effect.logs, 0, "chat     tab          chat")
                    #expect(entry.place == open)
                    #expect(entry.sound.status == .silent)
                    let again = entry.enter(request)
                    #expect(again.navigation == open)
                    #expect(again.opensFloatingWindow == false)
                }
            }
        }
    }

    @Test func soundAndFinishLeaveThePlaceAndDoNotOpenAWindow() {
        for presentation in HubBarPresentation.allCases {
            for tab in HubBarTab.allCases {
                for event in HubBarHeldEvent.allCases {
                    let start = HubBarPlace(presentation: presentation, tab: tab, opensFloatingWindow: true)
                    let held = HubBarEntry.heldPlace(start, event)
                    #expect(held.presentation == presentation)
                    #expect(held.tab == tab)
                    #expect(held.opensFloatingWindow == false)
                }
            }
        }
        var entry = HubBarEntry(place: HubBarPlace(presentation: .peek, tab: .agents, opensFloatingWindow: true))
        let armed = entry.setOptIn(true)
        entry = armed.entry
        #expect(armed.navigation == nil)
        #expect(armed.opensFloatingWindow == false)
        #expect(entry.place == HubBarPlace(presentation: .peek, tab: .agents, opensFloatingWindow: false))
        let working = tick(&entry, [HubBarSession(id: "s", status: .working)], at: at(0))
        #expect(working.navigation == nil)
        #expect(working.opensFloatingWindow == false)
        #expect(entry.place.presentation == .peek)
        #expect(entry.place.tab == .agents)
    }

    @Test func everyOptInPairMatchesTheSoundTable() {
        let rows: [(HubSoundStatus, Bool, HubSoundStatus, String?)] = [
            (.silent, true, .armed, "armed"),
            (.silent, false, .silent, nil),
            (.armed, true, .armed, nil),
            (.armed, false, .silent, "silent"),
            (.playing, true, .playing, nil),
            (.playing, false, .silent, "silent"),
        ]
        for (status, on, next, stage) in rows {
            var entry = entry(in: status, place: HubBarPlace(presentation: .panel, tab: .todo, opensFloatingWindow: false))
            let effect = entry.setOptIn(on)
            entry = effect.entry
            #expect(entry.sound.status == next)
            #expect(effect.navigation == nil)
            #expect(effect.opensFloatingWindow == false)
            #expect(effect.cues.isEmpty)
            #expect(effect.playsSystemFinishSound == false)
            #expect(entry.place.tab == .todo)
            if let stage {
                #expect(effect.logs == [HubBarLog(source: "sound", stage: stage, detail: "master")])
                let literal = stage == "armed" ? "sound    armed        master" : "sound    silent       master"
                expectTail(effect.logs, 0, literal)
            } else {
                #expect(effect.logs.isEmpty)
            }
        }
    }

    @Test func optedOutFinishIsSilentEvenWhenTheSystemSoundIsRequested() {
        var entry = HubBarEntry()
        #expect(entry.sound.status == .silent)
        _ = tick(&entry, [HubBarSession(id: "s11", status: .working)], at: at(0))
        let finished = tick(
            &entry,
            [HubBarSession(id: "s11", status: .done)],
            at: at(HubSound.minWorkSeconds + 20),
            systemFinishSound: true)
        #expect(finished.cues.isEmpty)
        #expect(finished.playsSystemFinishSound == false)
        #expect(finished.opensFloatingWindow == false)
        #expect(finished.navigation == nil)
        #expect(finished.logs == [HubBarLog(source: "sound", stage: "suppressed", detail: "done s11")])
        expectTail(finished.logs, 0, "sound    suppressed   done s11")
        #expect(entry.sound.status == .silent)
        let later = tick(&entry, [HubBarSession(id: "s11", status: .done)], at: at(80), systemFinishSound: true)
        #expect(later.cues.isEmpty)
        #expect(later.logs.isEmpty)
    }

    @Test func optedInFinishChimesOnceAndNotAgainInsideThreeSeconds() {
        #expect(HubSound.minWorkSeconds == 20)
        #expect(HubSound.coalesceSeconds == 3)
        var fresh = HubBarEntry()
        let opt = fresh.setOptIn(true)
        #expect(opt.logs == [HubBarLog(source: "sound", stage: "armed", detail: "master")])
        expectTail(opt.logs, 0, "sound    armed        master")
        var entry = opt.entry
        #expect(entry.sound.status == .armed)

        _ = tick(&entry, [
            HubBarSession(id: "s13", status: .working),
            HubBarSession(id: "s14", status: .working),
        ], at: at(0))
        let first = tick(&entry, [
            HubBarSession(id: "s13", status: .done),
            HubBarSession(id: "s14", status: .working),
        ], at: at(HubSound.minWorkSeconds + 10), systemFinishSound: true)
        #expect(first.cues == [.done])
        #expect(first.playsSystemFinishSound == false)
        #expect(first.logs == [HubBarLog(source: "sound", stage: "playing", detail: "done s13")])
        expectTail(first.logs, 0, "sound    playing      done s13")

        let inside = tick(&entry, [
            HubBarSession(id: "s13", status: .done),
            HubBarSession(id: "s14", status: .done),
        ], at: at(HubSound.minWorkSeconds + 10 + HubSound.coalesceSeconds - 0.001), systemFinishSound: true)
        #expect(inside.cues.isEmpty)
        #expect(inside.playsSystemFinishSound == false)
        #expect(inside.logs == [HubBarLog(source: "sound", stage: "suppressed", detail: "done s14")])
        expectTail(inside.logs, 0, "sound    suppressed   done s14")
    }

    @Test func theTwentySecondBoundaryStays() {
        let limit = HubSound.minWorkSeconds
        #expect(limit == 20)
        var early = optedIn()
        _ = tick(&early, [HubBarSession(id: "s12", status: .working)], at: at(0))
        let under = tick(&early, [HubBarSession(id: "s12", status: .done)], at: at(limit - 1), systemFinishSound: true)
        #expect(under.cues.isEmpty)
        #expect(under.playsSystemFinishSound == false)
        #expect(under.logs == [HubBarLog(source: "sound", stage: "suppressed", detail: "done s12")])
        expectTail(under.logs, 0, "sound    suppressed   done s12")

        var onTime = optedIn()
        _ = tick(&onTime, [HubBarSession(id: "s13", status: .working)], at: at(0))
        let exact = tick(&onTime, [HubBarSession(id: "s13", status: .done)], at: at(limit), systemFinishSound: false)
        #expect(exact.cues == [.done])
        #expect(exact.playsSystemFinishSound == false)
    }

    @Test func theThreeSecondBoundaryStays() {
        let gap = HubSound.coalesceSeconds
        #expect(gap == 3)
        var entry = optedIn()
        _ = tick(&entry, [
            HubBarSession(id: "a", status: .working),
            HubBarSession(id: "b", status: .working),
        ], at: at(0))
        let first = tick(&entry, [
            HubBarSession(id: "a", status: .done),
            HubBarSession(id: "b", status: .working),
        ], at: at(30))
        #expect(first.cues == [.done])
        let atGap = tick(&entry, [
            HubBarSession(id: "a", status: .done),
            HubBarSession(id: "b", status: .done),
        ], at: at(30 + gap))
        #expect(atGap.cues == [.done])
        #expect(atGap.logs == [HubBarLog(source: "sound", stage: "playing", detail: "done b")])
    }

    @Test func oneTickPlaysAtMostOneChime() {
        var entry = optedIn()
        _ = tick(&entry, [
            HubBarSession(id: "a", status: .working),
            HubBarSession(id: "b", status: .working),
        ], at: at(0))
        let both = tick(&entry, [
            HubBarSession(id: "a", status: .done),
            HubBarSession(id: "b", status: .done),
        ], at: at(30), systemFinishSound: true)
        #expect(both.cues == [.done])
        #expect(both.playsSystemFinishSound == false)
        #expect(both.logs == [
            HubBarLog(source: "sound", stage: "playing", detail: "done a"),
            HubBarLog(source: "sound", stage: "suppressed", detail: "done b"),
        ])
    }

    @Test func optingOutSilencesALaterFinishAndALaterApproval() {
        var entry = optedIn()
        _ = tick(&entry, [HubBarSession(id: "a", status: .working)], at: at(0), startEnabled: true)
        #expect(entry.sound.status == .playing)
        let off = entry.setOptIn(false)
        entry = off.entry
        #expect(off.logs == [HubBarLog(source: "sound", stage: "silent", detail: "master")])
        expectTail(off.logs, 0, "sound    silent       master")
        #expect(entry.sound.status == .silent)
        let finished = tick(&entry, [HubBarSession(id: "a", status: .done)], at: at(40), systemFinishSound: true)
        #expect(finished.cues.isEmpty)
        #expect(finished.playsSystemFinishSound == false)
        let approval = tick(
            &entry,
            [HubBarSession(id: "b", status: .working)],
            at: at(50),
            approval: true,
            approvalID: "b")
        #expect(approval.cues.isEmpty)
        #expect(approval.logs.contains(HubBarLog(source: "sound", stage: "suppressed", detail: "approval b")))
    }

    @Test func anApprovalChimesOnceWhenArmedAndNotInsideTheWindow() {
        var entry = optedIn()
        let shown = tick(&entry, [], at: at(0), approval: true, approvalID: "s13")
        #expect(shown.cues == [.approval])
        #expect(shown.logs == [HubBarLog(source: "sound", stage: "playing", detail: "approval s13")])
        expectTail(shown.logs, 0, "sound    playing      approval s13")
        let held = tick(&entry, [], at: at(1), approval: true, approvalID: "s13")
        #expect(held.cues.isEmpty)
        #expect(held.logs.isEmpty)

        var later = optedIn()
        _ = tick(&later, [HubBarSession(id: "s13", status: .working)], at: at(0))
        let finished = tick(&later, [HubBarSession(id: "s13", status: .done)], at: at(30))
        #expect(finished.cues == [.done])
        let crowded = tick(
            &later,
            [HubBarSession(id: "s13", status: .done)],
            at: at(31),
            approval: true,
            approvalID: "s13")
        #expect(crowded.cues.isEmpty)
        #expect(crowded.logs == [HubBarLog(source: "sound", stage: "suppressed", detail: "approval s13")])
    }

    @Test func aStartChimeStillRequiresItsOwnSwitch() {
        var off = optedIn()
        let silent = tick(&off, [HubBarSession(id: "a", status: .working)], at: at(0), startEnabled: false)
        #expect(silent.cues.isEmpty)
        var on = optedIn()
        let played = tick(&on, [HubBarSession(id: "a", status: .working)], at: at(0), startEnabled: true)
        #expect(played.cues == [.start])
        let again = tick(&on, [HubBarSession(id: "a", status: .working)], at: at(1), startEnabled: true)
        #expect(again.cues.isEmpty)
    }

    @Test func aFailedTurnIsNotADoneChime() {
        var entry = optedIn()
        _ = tick(&entry, [HubBarSession(id: "a", status: .working)], at: at(0))
        let failed = tick(&entry, [HubBarSession(id: "a", status: .failed)], at: at(40), systemFinishSound: true)
        #expect(failed.cues.isEmpty)
        #expect(failed.logs.isEmpty)
        #expect(failed.playsSystemFinishSound == false)
    }

    @Test func waitingThenDoneStillUsesTheSameStretch() {
        var entry = optedIn()
        _ = tick(&entry, [HubBarSession(id: "a", status: .working)], at: at(0))
        _ = tick(&entry, [HubBarSession(id: "a", status: .needsYou)], at: at(10))
        let done = tick(&entry, [HubBarSession(id: "a", status: .done)], at: at(21))
        #expect(done.cues == [.done])
    }

    @Test func theMacWalkOpensChatAndChimesOnce() {
        var entry = HubBarEntry(place: HubBarPlace(presentation: .closed, tab: .agents, opensFloatingWindow: false))
        let shortcut = entry.enter(.shortcut)
        entry = shortcut.entry
        #expect(shortcut.navigation == HubBarPlace(presentation: .panel, tab: .chat, opensFloatingWindow: false))
        expectTail(shortcut.logs, 0, "chat     tab          chat")
        let tapped = entry.enter(.openWindow)
        entry = tapped.entry
        #expect(tapped.opensFloatingWindow == false)
        #expect(tapped.navigation?.tab == .chat)

        _ = tick(&entry, [HubBarSession(id: "s11", status: .working)], at: at(0))
        let silent = tick(
            &entry, [HubBarSession(id: "s11", status: .done)], at: at(40), systemFinishSound: true)
        #expect(silent.cues.isEmpty)
        expectTail(silent.logs, 0, "sound    suppressed   done s11")

        let opt = entry.setOptIn(true)
        entry = opt.entry
        expectTail(opt.logs, 0, "sound    armed        master")

        _ = tick(&entry, [HubBarSession(id: "s12", status: .working)], at: at(100))
        let short = tick(&entry, [HubBarSession(id: "s12", status: .done)], at: at(119), systemFinishSound: true)
        #expect(short.cues.isEmpty)
        expectTail(short.logs, 0, "sound    suppressed   done s12")

        _ = tick(&entry, [
            HubBarSession(id: "s13", status: .working),
            HubBarSession(id: "s14", status: .working),
        ], at: at(200))
        let chime = tick(&entry, [
            HubBarSession(id: "s13", status: .done),
            HubBarSession(id: "s14", status: .working),
        ], at: at(230), systemFinishSound: true)
        #expect(chime.cues == [.done])
        expectTail(chime.logs, 0, "sound    playing      done s13")
        let second = tick(&entry, [
            HubBarSession(id: "s13", status: .done),
            HubBarSession(id: "s14", status: .done),
        ], at: at(232.9), systemFinishSound: true)
        #expect(second.cues.isEmpty)
        expectTail(second.logs, 0, "sound    suppressed   done s14")
    }

    /// Builds a sound status without going through a window.
    private func entry(in status: HubSoundStatus, place: HubBarPlace) -> HubBarEntry {
        var entry = HubBarEntry(place: place)
        switch status {
        case .silent:
            break
        case .armed:
            _ = entry.setOptIn(true)
        case .playing:
            _ = entry.setOptIn(true)
            _ = entry.tick(
                sessions: [HubBarSession(id: "seed", status: .working)],
                approvalVisible: false,
                approvalSessionID: nil,
                at: at(0),
                startEnabled: true,
                systemFinishSound: false)
        }
        return entry
    }
}
