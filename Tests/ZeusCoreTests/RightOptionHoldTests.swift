import Foundation
import Testing
@testable import ZeusCore

@Suite("Right Option hold")
struct RightOptionHoldTests {
    private let right = RightOptionHold.rightKeyCode
    private let left = UInt16(58)
    private let letter = UInt16(0)

    @Test func holdingRightOptionShowsTheBarAtTheKeyDown() {
        var hold = RightOptionHold()
        let actions = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: 0)
        #expect(actions == [.showBar])
        #expect(hold.phase == .shown(since: 0))
        #expect(RightOptionHold.appearLatency == 0)
        #expect(RightOptionHold.appearLatency < RightOptionHold.listenConfirm)
        #expect(!actions.contains(.listen))
    }

    @Test func aHeldRightOptionListensAfterTheBarIsAlreadyUp() {
        var hold = RightOptionHold()
        _ = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: 0)
        let early = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: RightOptionHold.listenConfirm - 0.05)
        #expect(early.isEmpty)
        #expect(hold.phase == .shown(since: 0))
        let listen = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: RightOptionHold.listenConfirm)
        #expect(listen == [.listen])
        #expect(hold.phase == .listening(since: 0))
        #expect(RightOptionHold.listenConfirm == VoiceKey.secondKeyConfirm)
    }

    @Test func aLetterInsideTheTypingWindowHidesTheBarAndDoesNotListen() {
        var hold = RightOptionHold()
        _ = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: 0)
        let actions = hold.observe(deviceKeys: [right], ordinaryKeys: [letter], at: 0.1)
        #expect(actions == [.hideBar])
        #expect(hold.phase == .idle)
        #expect(!actions.contains(.listen))
    }

    @Test func releasingInsideTheTypingWindowHidesTheBarAndDoesNotListen() {
        var hold = RightOptionHold()
        _ = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: 0)
        let actions = hold.observe(deviceKeys: [], ordinaryKeys: [], at: 0.1)
        #expect(actions == [.hideBar])
        #expect(hold.phase == .idle)
    }

    @Test func leftOptionShowsNothingAndDoesNotListen() {
        var hold = RightOptionHold()
        let actions = hold.observe(deviceKeys: [left], ordinaryKeys: [], at: 0)
        #expect(actions.isEmpty)
        #expect(hold.phase == .idle)
        let both = hold.observe(deviceKeys: [left, right], ordinaryKeys: [], at: 0)
        #expect(both.isEmpty)
        #expect(hold.phase == .idle)
    }

    @Test func releasingAfterListenStopsListening() {
        var hold = RightOptionHold()
        _ = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: 0)
        _ = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: RightOptionHold.listenConfirm)
        let actions = hold.observe(deviceKeys: [], ordinaryKeys: [], at: RightOptionHold.listenConfirm + 0.4)
        #expect(actions == [.stopListening])
        #expect(hold.phase == .idle)
    }

    @Test func aLetterAfterListenStopsListening() {
        var hold = RightOptionHold()
        _ = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: 0)
        _ = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: 0.25)
        let actions = hold.observe(deviceKeys: [right], ordinaryKeys: [letter], at: 0.4)
        #expect(actions == [.stopListening])
        #expect(hold.phase == .idle)
    }

    @Test func aRepeatWhileTheBarIsUpDoesNotShowItAgain() {
        var hold = RightOptionHold()
        _ = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: 0)
        let again = hold.observe(deviceKeys: [right], ordinaryKeys: [], at: 0.05)
        #expect(again.isEmpty)
        #expect(hold.phase == .shown(since: 0))
    }
}
