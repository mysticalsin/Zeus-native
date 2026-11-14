import Foundation
import Testing
@testable import ZeusCore

/// Actions the key tap hands to the main actor wait here. A burst of focus repeats must not queue one window scan per
/// repeat behind a running scan: the newest focus request wins, and every other action is kept in order.
@Suite struct TileActionMailboxTests {
    /// `push` mutates, and `#expect` cannot call a mutating member in place, so the answer is read here first.
    private func asksForDrain(_ box: inout TileActionMailbox, _ action: TileAction) -> Bool { box.push(action) }

    private func drain(_ box: inout TileActionMailbox) -> [TileAction] {
        var out: [TileAction] = []
        while let next = box.pop() { out.append(next.action) }
        return out
    }

    @Test func theFirstPushAsksForOneDrainAndTheRestDoNot() {
        var box = TileActionMailbox()
        let ask1 = asksForDrain(&box, .retile); #expect(ask1)
        let ask2 = asksForDrain(&box, .flipSplit); #expect(!ask2, "a drain is already scheduled")
        let ask3 = asksForDrain(&box, .toggleFloat); #expect(!ask3)
    }

    @Test func actionsComeOutInTheOrderTheyWerePushed() {
        var box = TileActionMailbox()
        for action in [TileAction.swap(.left), .flipSplit, .toggleFloat, .retile, .nudge(.left)] { _ = box.push(action) }
        #expect(drain(&box) == [.swap(.left), .flipSplit, .toggleFloat, .retile, .nudge(.left)])
    }

    @Test func aBurstOfFocusRepeatsKeepsOnlyTheNewest() {
        var box = TileActionMailbox()
        for _ in 0..<1000 { _ = box.push(.focus(.left)) }
        #expect(box.pending == [.focus(.left)], "one scan at most, however long the key is held")
        _ = box.push(.focus(.right))
        #expect(box.pending == [.focus(.right)], "the newest request wins, even in another direction")
        #expect(drain(&box) == [.focus(.right)])
    }

    @Test func aFocusRequestDoesNotMergeAcrossAnotherAction() {
        var box = TileActionMailbox()
        _ = box.push(.focus(.left))
        _ = box.push(.swap(.left))
        _ = box.push(.focus(.right))
        _ = box.push(.focus(.up))
        #expect(drain(&box) == [.focus(.left), .swap(.left), .focus(.up)], "order is kept; only a run of focus requests collapses")
    }

    @Test func noOtherActionIsEverMerged() {
        let others: [TileAction] = [.swap(.right), .flipSplit, .toggleFloat, .togglePause, .retile, .nudge(.left), .showKeys, .maximizeToggle]
        for action in others {
            var box = TileActionMailbox()
            _ = box.push(action)
            _ = box.push(action)
            #expect(box.pending == [action, action], "\(action)")
        }
    }

    @Test func aPushWhileAScanRunsSchedulesOneDrainAndMergesTheRest() {
        var box = TileActionMailbox()
        let ask4 = asksForDrain(&box, .focus(.left)); #expect(ask4)
        let running = box.pop() // the scan for this one is running on the main actor now
        #expect(running?.action == .focus(.left) && running?.more == false)
        let ask5 = asksForDrain(&box, .focus(.left)); #expect(ask5, "the first repeat behind the scan schedules one drain")
        for _ in 0..<200 { let ask = asksForDrain(&box, .focus(.right)); #expect(!ask) }
        #expect(box.pending == [.focus(.right)], "nothing queues behind the running scan")
    }

    @Test func popSaysWhetherAnotherDrainIsNeeded() {
        var box = TileActionMailbox()
        _ = box.push(.swap(.left))
        _ = box.push(.retile)
        let first = box.pop()
        #expect(first?.action == .swap(.left) && first?.more == true)
        let second = box.pop()
        #expect(second?.action == .retile && second?.more == false)
        #expect(box.pop() == nil)
        let ask6 = asksForDrain(&box, .retile); #expect(ask6, "an empty mailbox is idle again, so the next push asks for a drain")
    }

    @Test func resetForgetsEverythingAndIsIdle() {
        var box = TileActionMailbox()
        _ = box.push(.retile)
        _ = box.push(.flipSplit)
        box.reset()
        #expect(box.pending.isEmpty)
        #expect(box.pop() == nil)
        let ask7 = asksForDrain(&box, .retile); #expect(ask7, "after a reset the next push asks for a drain")
    }

    @Test func aDrainThatArrivesAfterAResetFindsNothing() {
        var box = TileActionMailbox()
        _ = box.push(.focus(.left))
        box.reset()
        #expect(box.pop() == nil)
        let ask8 = asksForDrain(&box, .focus(.left)); #expect(ask8)
    }
}
