import Foundation
import Testing
@testable import ZeusCore

/// The master switch sits in front of the existing chime policy.
/// Off, a done cue, a start cue, and an approval cue are silence.
/// On, the 20 second and 3 second rules still decide, and a finish returns one cue.
@Suite("Hub sound")
struct HubSoundTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func optedIn() -> HubSound {
        var sound = HubSound()
        _ = sound.apply(.optIn)
        return sound
    }

    @Test func masterOffSilencesDoneStartAndApproval() {
        var sound = HubSound()
        #expect(sound.status == .silent)
        #expect(sound.session("a", status: .working, at: at(0), startEnabled: true).cues == [])
        #expect(sound.approval(visible: true, at: at(1)).cues == [])
        #expect(sound.session("a", status: .done, at: at(20), startEnabled: true).cues == [])
        #expect(sound.finish("a", at: at(40), startEnabled: true, systemFinishSound: true).cues == [])
        #expect(sound.status == .silent)
    }

    @Test func masterOnKeepsTheTwentySecondAndThreeSecondRules() {
        var short = optedIn()
        _ = short.session("a", status: .working, at: at(0), startEnabled: false)
        #expect(short.session("a", status: .done, at: at(19), startEnabled: false).cues == [])

        var done = optedIn()
        _ = done.session("a", status: .working, at: at(0), startEnabled: false)
        let finished = done.session("a", status: .done, at: at(20), startEnabled: false)
        #expect(finished.cues == [.done])
        #expect(done.session("a", status: .done, at: at(40), startEnabled: false).cues == [])

        var starts = optedIn()
        #expect(starts.session("a", status: .working, at: at(0), startEnabled: false).cues == [])
        #expect(starts.session("b", status: .working, at: at(4), startEnabled: true).cues == [.start])

        var coalesce = optedIn()
        _ = coalesce.session("a", status: .working, at: at(0), startEnabled: false)
        _ = coalesce.session("b", status: .working, at: at(0), startEnabled: false)
        #expect(coalesce.session("a", status: .done, at: at(30), startEnabled: false).cues == [.done])
        #expect(coalesce.session("b", status: .done, at: at(32.9), startEnabled: false).cues == [])
        _ = coalesce.session("b", status: .working, at: at(33), startEnabled: false)
        #expect(coalesce.session("b", status: .done, at: at(60), startEnabled: false).cues == [.done])

        var approval = optedIn()
        #expect(approval.approval(visible: true, at: at(0)).cues == [.approval])
        #expect(approval.approval(visible: true, at: at(1)).cues == [])
    }

    @Test func aFinishNeverReturnsTwoCues() {
        var sound = optedIn()
        _ = sound.session("a", status: .working, at: at(0), startEnabled: false)
        let both = sound.finish("a", at: at(20), startEnabled: false, systemFinishSound: true)
        #expect(both.cues.count <= 1)
        #expect(both.cues == [.done])

        var under = optedIn()
        _ = under.session("a", status: .working, at: at(0), startEnabled: false)
        #expect(under.finish("a", at: at(19), startEnabled: false, systemFinishSound: true).cues == [])

        var once = optedIn()
        _ = once.session("a", status: .working, at: at(0), startEnabled: false)
        #expect(once.finish("a", at: at(20), startEnabled: false, systemFinishSound: false).cues == [.done])
        #expect(once.finish("a", at: at(40), startEnabled: false, systemFinishSound: true).cues == [])

        var spaced = optedIn()
        _ = spaced.session("a", status: .working, at: at(0), startEnabled: false)
        _ = spaced.session("b", status: .working, at: at(0), startEnabled: false)
        #expect(spaced.finish("a", at: at(30), startEnabled: false, systemFinishSound: true).cues == [.done])
        #expect(spaced.finish("b", at: at(32.9), startEnabled: false, systemFinishSound: true).cues == [])
    }

    @Test func theTwentySecondAndThreeSecondWindowsKeepTheirNames() {
        #expect(HubSound.minWorkSeconds == AgentChimePolicy.minWorkSeconds)
        #expect(HubSound.coalesceSeconds == AgentChimePolicy.coalesceSeconds)
        #expect(HubSound.minWorkSeconds == 20)
        #expect(HubSound.coalesceSeconds == 3)
    }

    @Test func everySoundPairMatchesTheTable() {
        let named: [(HubSoundStatus, HubSoundEvent, HubSoundStatus)] = [
            (.silent, .optIn, .armed),
            (.armed, .optOut, .silent),
            (.armed, .cueAllowed, .playing),
            (.armed, .cueSuppressed, .armed),
            (.playing, .optOut, .silent),
            (.playing, .soundEnded, .armed),
        ]
        var seen: Set<String> = []
        for (status, event, next) in named {
            #expect(HubSound.next(status, event) == next)
            seen.insert(status.storedLabel + " " + event.storedLabel)
        }
        for status in HubSoundStatus.allCases {
            for event in HubSoundEvent.allCases {
                let key = status.storedLabel + " " + event.storedLabel
                if seen.contains(key) { continue }
                #expect(HubSound.next(status, event) == status)
            }
        }
    }

    @Test func optingOutStopsAPlayingCue() {
        var sound = HubSound()
        #expect(sound.apply(.optIn) == .armed)
        let started = sound.session("a", status: .working, at: at(0), startEnabled: true)
        #expect(started.cues == [.start])
        #expect(started.status == .playing)
        #expect(sound.apply(.optOut) == .silent)
        #expect(sound.approval(visible: true, at: at(1)).cues == [])
        #expect(sound.session("a", status: .done, at: at(30), startEnabled: true).cues == [])
        #expect(sound.status == .silent)
    }

    @Test func approvalAnswerStillFollowsTheExistingWindow() {
        var fast = optedIn()
        #expect(fast.approval(visible: true, at: at(0)).cues == [.approval])
        #expect(fast.approval(visible: false, at: at(1.9)).cues == [])

        var slow = optedIn()
        _ = slow.approval(visible: true, at: at(0))
        #expect(slow.approval(visible: false, at: at(5)).cues == [.answer])
        #expect(slow.approval(visible: false, at: at(6)).cues == [])
    }

    @Test func forgettingASessionDropsItsStretch() {
        var sound = optedIn()
        _ = sound.session("a", status: .working, at: at(0), startEnabled: false)
        sound.forget(keeping: [])
        #expect(sound.session("a", status: .done, at: at(60), startEnabled: false).cues == [])
    }
}
