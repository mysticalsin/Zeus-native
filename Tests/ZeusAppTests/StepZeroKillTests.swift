import Testing
@testable import Zeus

@Suite("Step zero kill")
struct StepZeroKillTests {
    private let same = "aabbccddeeff0011"
    private let upper = "AABBCCDDEEFF0011"
    private let other = "aabbccddeeff0012"
    private let forged = "not-a-boot-mark!"
    private let held = KillTestSection.OrphanSight(
        vendorInterpreter: true, parentIsOne: true, sameUser: true, libraryMatches: true
    )

    @Test func anOpenRowStaysIdleAndASecondBeginDoesNothing() {
        let openSource = drive([
            .begin(systemSource: .open, lockScreen: .done, variant: .selfKill),
            .continueAsked,
            .locked,
            .skip,
            .ownerQuit,
            .waited(milliseconds: 60_000),
        ])
        #expect(openSource.0.phase == .idle)
        #expect(openSource.0.variant == nil)
        #expect(openSource.1.isEmpty)

        let openLock = drive([
            .begin(systemSource: .skipped, lockScreen: .open, variant: .hold),
        ])
        #expect(openLock.0.phase == .idle)
        #expect(openLock.1.isEmpty)

        let second = drive([
            .begin(systemSource: .done, lockScreen: .skipped, variant: .selfKill),
            .begin(systemSource: .open, lockScreen: .open, variant: .hold),
        ])
        #expect(second.0.phase == .gate)
        #expect(second.0.variant == .selfKill)
        #expect(second.1.isEmpty)

        let before = drive([
            .continueAsked,
            .locked,
            .skip,
            .ownerQuit,
            .resume(leftover: false, orphan: held),
            .cardGone(true),
            .boot(previous: same, current: other),
            .waited(milliseconds: 5_000),
        ])
        #expect(before.0.phase == .idle)
        #expect(before.0.fact == nil)
        #expect(before.1.isEmpty)
    }

    @Test func skipArmsNothing() {
        let skipped = drive([
            .begin(systemSource: .skipped, lockScreen: .skipped, variant: .hold),
            .skip,
            .continueAsked,
            .ownerQuit,
            .waited(milliseconds: 60_000),
            .locked,
        ])
        #expect(skipped.1.isEmpty)
        #expect(skipped.0.phase == .done)
        #expect(skipped.0.mark == .skipped)
        #expect(skipped.0.fact == nil)
        #expect(skipped.0.journalWritten == false)
    }

    @Test func theJournalIsWrittenBeforeTheSelfKillAndTheBoundaryHolds() {
        #expect(KillTestSection.selfKillMilliseconds == 5_000)
        #expect(KillTestSection.holdMilliseconds == 60_000)

        let open = drive([
            .begin(systemSource: .done, lockScreen: .skipped, variant: .selfKill),
            .continueAsked,
            .locked,
            .waited(milliseconds: 4_999),
        ])
        #expect(open.1 == [.startChild, .askLock, .showCard, .writeJournal])
        #expect(open.0.phase == .holding)
        #expect(open.0.journalWritten)
        #expect(open.0.fact == nil)
        #expect(open.0.clockMs == 4_999)
        #expect(open.0.mark == nil)

        let closed = drive([
            .begin(systemSource: .done, lockScreen: .done, variant: .selfKill),
            .continueAsked,
            .locked,
            .waited(milliseconds: 2_500),
            .waited(milliseconds: 2_500),
            .waited(milliseconds: 5_000),
            .ownerQuit,
        ])
        #expect(closed.1 == [.startChild, .askLock, .showCard, .writeJournal, .endProcess])
        #expect(closed.0.phase == .ended)
        #expect(closed.0.mark == .ran)
        #expect(closed.0.clockMs == 0)
        #expect(closed.0.fact?.journalBeforeKill == true)
        #expect(closed.0.fact?.spaceDestroyed == false)
        #expect(closed.0.fact?.forceQuit == .unanswered)
        #expect(closed.1.filter { $0 == .endProcess }.count == 1)
        #expect(closed.1.contains(.destroySpace) == false)
        #expect(closed.1.firstIndex(of: .writeJournal)! < closed.1.firstIndex(of: .endProcess)!)

        let jumped = drive([
            .begin(systemSource: .done, lockScreen: .done, variant: .selfKill),
            .continueAsked,
            .locked,
            .waited(milliseconds: 60_000),
        ])
        #expect(jumped.1 == [.startChild, .askLock, .showCard, .writeJournal, .endProcess])
        #expect(jumped.0.fact?.spaceDestroyed == false)
    }

    @Test func aResumeBeforeTheKillMarksNothing() {
        let early = drive([
            .begin(systemSource: .done, lockScreen: .done, variant: .selfKill),
            .continueAsked,
            .resume(leftover: false, orphan: held),
            .locked,
            .resume(leftover: true, orphan: held),
            .cardGone(true),
        ])
        #expect(early.1 == [.startChild, .askLock, .showCard, .writeJournal])
        #expect(early.0.phase == .holding)
        #expect(early.0.fact == nil)
        #expect(early.0.journalWritten)
    }

    @Test func aResumedJournalMarksTheOrphanAndTheCensus() {
        let clean = drive(selfKillEnded + [
            .resume(leftover: false, orphan: held),
        ])
        #expect(clean.1.last == .askCardGone)
        #expect(clean.1.filter { $0 == .askCardGone }.count == 1)
        #expect(clean.0.phase == .asking)
        #expect(clean.0.fact?.orphanAfterKill == .yes)
        #expect(clean.0.fact?.windowGone == .yes)
        #expect(clean.0.fact?.censusLeftover == false)
        #expect(clean.0.fact?.journalBeforeKill == true)

        let again = drive(selfKillEnded + [
            .resume(leftover: false, orphan: held),
            .resume(leftover: true, orphan: missedLibrary),
        ])
        #expect(again.1.filter { $0 == .askCardGone }.count == 1)
        #expect(again.0.fact?.orphanAfterKill == .yes)
        #expect(again.0.fact?.windowGone == .yes)
        #expect(again.0.fact?.censusLeftover == false)

        let leftover = drive(selfKillEnded + [
            .resume(leftover: true, orphan: held),
        ])
        #expect(leftover.0.fact?.windowGone == .no)
        #expect(leftover.0.fact?.censusLeftover == true)
        #expect(leftover.0.fact?.orphanAfterKill == .yes)
    }

    @Test func theOrphanRuleFailsClosed() {
        #expect(KillTestSection.orphanHolds(held))
        let misses = [missedVendor, missedParent, missedUser, missedLibrary]
        for sight in misses {
            #expect(KillTestSection.orphanHolds(sight) == false)
            let state = drive(selfKillEnded + [.resume(leftover: false, orphan: sight)]).0
            #expect(state.fact?.orphanAfterKill == .no)
            #expect(state.fact?.windowGone == .yes)
        }
    }

    @Test func theCardQuestionWaitsForTheResume() {
        let before = drive(selfKillEnded + [.cardGone(true)])
        #expect(before.0.phase == .ended)
        #expect(before.0.fact?.cardGone == .unanswered)
        #expect(before.1.contains(.askCardGone) == false)

        let answered = drive(selfKillEnded + [
            .resume(leftover: true, orphan: missedParent),
            .cardGone(false),
            .cardGone(true),
        ])
        #expect(answered.0.phase == .done)
        #expect(answered.0.fact?.cardGone == .no)
        #expect(answered.0.fact?.windowGone == .no)
        #expect(answered.0.fact?.orphanAfterKill == .no)
        #expect(answered.1.filter { $0 == .askCardGone }.count == 1)
    }

    @Test func theHoldAlwaysDestroysOnce() {
        let under = drive([
            .begin(systemSource: .skipped, lockScreen: .done, variant: .hold),
            .continueAsked,
            .waited(milliseconds: 59_999),
            .locked,
        ])
        #expect(under.1 == [.showCard, .writeJournal])
        #expect(under.0.phase == .holding)
        #expect(under.0.fact == nil)
        #expect(under.0.clockMs == 59_999)
        #expect(under.0.journalWritten)
        #expect(under.1.contains(.startChild) == false)
        #expect(under.1.contains(.endProcess) == false)

        let timeout = drive([
            .begin(systemSource: .done, lockScreen: .done, variant: .hold),
            .continueAsked,
            .waited(milliseconds: 30_000),
            .waited(milliseconds: 30_000),
            .ownerQuit,
            .waited(milliseconds: 60_000),
        ])
        #expect(timeout.1 == [.showCard, .writeJournal, .destroySpace])
        #expect(timeout.1.filter { $0 == .destroySpace }.count == 1)
        #expect(timeout.1.contains(.endProcess) == false)
        #expect(timeout.0.phase == .ended)
        #expect(timeout.0.mark == .ran)
        #expect(timeout.0.fact?.journalBeforeKill == true)
        #expect(timeout.0.fact?.forceQuit == .notTried)
        #expect(timeout.0.fact?.spaceDestroyed == true)
        #expect(timeout.1.firstIndex(of: .writeJournal)! < timeout.1.firstIndex(of: .destroySpace)!)

        let quit = drive([
            .begin(systemSource: .done, lockScreen: .skipped, variant: .hold),
            .continueAsked,
            .waited(milliseconds: 1),
            .ownerQuit,
            .ownerQuit,
            .waited(milliseconds: 60_000),
        ])
        #expect(quit.1 == [.showCard, .writeJournal, .destroySpace])
        #expect(quit.1.filter { $0 == .destroySpace }.count == 1)
        #expect(quit.0.fact?.forceQuit == .yes)
        #expect(quit.0.fact?.spaceDestroyed == true)
        #expect(quit.0.fact?.journalBeforeKill == true)
        #expect(quit.0.clockMs == 0)
    }

    @Test func bootMarksGiveYesAndNoAndTheCharactersAreDropped() {
        let changed = drive(holdEnded + [.boot(previous: same, current: other)])
        #expect(changed.0.fact?.bootReads == .yes)
        #expect(changed.0.fact?.bootChanged == .yes)
        #expect(storedStrings(changed.0).contains(same) == false)
        #expect(storedStrings(changed.0).contains(other) == false)

        let unchanged = drive(holdEnded + [.boot(previous: upper, current: same)])
        #expect(unchanged.0.fact?.bootReads == .yes)
        #expect(unchanged.0.fact?.bootChanged == .no)
        #expect(storedStrings(unchanged.0).contains(upper) == false)
        #expect(storedStrings(unchanged.0).contains(same) == false)

        let discarded = drive(holdEnded + [
            .boot(previous: forged, current: other),
            .boot(previous: same, current: other),
        ])
        #expect(discarded.0.fact?.bootReads == .no)
        #expect(discarded.0.fact?.bootChanged == .unanswered)
        let stored = storedStrings(discarded.0)
        #expect(stored.contains(forged) == false)
        #expect(stored.contains(other) == false)
        #expect(stored.contains(same) == false)

        let early = drive([
            .begin(systemSource: .done, lockScreen: .done, variant: .hold),
            .boot(previous: same, current: other),
            .continueAsked,
            .waited(milliseconds: 60_000),
        ])
        #expect(early.0.fact?.bootReads == .unanswered)
        #expect(early.0.fact?.bootChanged == .unanswered)
        #expect(storedStrings(early.0).contains(same) == false)
        #expect(storedStrings(early.0).contains(other) == false)

        let afterSkip = drive([
            .begin(systemSource: .done, lockScreen: .done, variant: .hold),
            .skip,
            .boot(previous: same, current: other),
        ])
        #expect(afterSkip.0.fact == nil)
        #expect(storedStrings(afterSkip.0).contains(same) == false)
    }

    @Test func zeroAndNegativeWaitsDoNotMoveTheClock() {
        let (state, effects) = drive([
            .begin(systemSource: .done, lockScreen: .done, variant: .selfKill),
            .continueAsked,
            .locked,
            .waited(milliseconds: 0),
            .waited(milliseconds: -5_000),
            .ownerQuit,
        ])
        #expect(effects == [.startChild, .askLock, .showCard, .writeJournal])
        #expect(state.phase == .holding)
        #expect(state.clockMs == 0)
        #expect(state.fact == nil)

        let hold = drive([
            .begin(systemSource: .done, lockScreen: .done, variant: .hold),
            .continueAsked,
            .waited(milliseconds: 0),
            .waited(milliseconds: -60_000),
        ])
        #expect(hold.0.phase == .holding)
        #expect(hold.0.clockMs == 0)
        #expect(hold.0.fact == nil)
        #expect(hold.1 == [.showCard, .writeJournal])
    }

    private var selfKillEnded: [KillTestSection.Event] {
        [
            .begin(systemSource: .done, lockScreen: .done, variant: .selfKill),
            .continueAsked,
            .locked,
            .waited(milliseconds: 5_000),
        ]
    }

    private var holdEnded: [KillTestSection.Event] {
        [
            .begin(systemSource: .done, lockScreen: .skipped, variant: .hold),
            .continueAsked,
            .waited(milliseconds: 60_000),
        ]
    }

    private var missedVendor: KillTestSection.OrphanSight {
        KillTestSection.OrphanSight(vendorInterpreter: false, parentIsOne: true, sameUser: true, libraryMatches: true)
    }

    private var missedParent: KillTestSection.OrphanSight {
        KillTestSection.OrphanSight(vendorInterpreter: true, parentIsOne: false, sameUser: true, libraryMatches: true)
    }

    private var missedUser: KillTestSection.OrphanSight {
        KillTestSection.OrphanSight(vendorInterpreter: true, parentIsOne: true, sameUser: false, libraryMatches: true)
    }

    private var missedLibrary: KillTestSection.OrphanSight {
        KillTestSection.OrphanSight(vendorInterpreter: true, parentIsOne: true, sameUser: true, libraryMatches: false)
    }

    private func drive(_ events: [KillTestSection.Event]) -> (KillTestSection.State, [KillTestSection.Effect]) {
        var state = KillTestSection.fresh()
        var effects: [KillTestSection.Effect] = []
        for event in events {
            let reduced = KillTestSection.reduce(state, event)
            state = reduced.state
            effects.append(contentsOf: reduced.effects)
        }
        return (state, effects)
    }

    private func storedStrings(_ state: KillTestSection.State) -> [String] {
        var found: [String] = []
        func walk(_ value: Any) {
            if let text = value as? String {
                found.append(text)
                return
            }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional {
                if let child = mirror.children.first {
                    walk(child.value)
                }
                return
            }
            for child in mirror.children {
                walk(child.value)
            }
        }
        walk(state)
        return found
    }
}
