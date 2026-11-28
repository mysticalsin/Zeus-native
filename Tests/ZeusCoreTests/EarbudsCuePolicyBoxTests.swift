import Foundation
import Testing
@testable import ZeusCore

@Suite("Earbuds cue policy box")
struct EarbudsCuePolicyBoxTests {
    private func show(_ kind: EarbudsCueShow.Kind, id: String) -> EarbudsCueShow {
        EarbudsCueShow(id: id, name: "Left Bud", kind: kind)
    }

    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(EarbudsCuePolicyBox.blankScalars.contains(" "))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\t"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\n"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{000B}"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{000C}"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\r"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{0085}"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{00A0}"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{1680}"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{2000}"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{200A}"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{2028}"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{2029}"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{202F}"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{205F}"))
        #expect(EarbudsCuePolicyBox.blankScalars.contains("\u{3000}"))
        #expect(!EarbudsCuePolicyBox.blankScalars.contains("\u{200B}"))
        #expect(EarbudsCuePolicyBox.trimmedID("\u{200B}") == "\u{200B}")
        #expect(EarbudsCuePolicyBox.trimmedID(" \u{200B} ") == "\u{200B}")
        #expect(EarbudsCuePolicyBox.trimmedID(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aZeroWidthIdStaysAndNamedBlanksAreRefused() {
        #expect(EarbudsCuePolicyBox.mayShow(show(.connected, id: "\u{200B}"), over: .none) == true)
        #expect(EarbudsCuePolicyBox.mayShow(show(.connected, id: " \u{200B} "), over: .none) == true)
        #expect(EarbudsCuePolicyBox.mayShow(show(.connected, id: "\u{00A0}"), over: .none) == false)
        #expect(EarbudsCuePolicyBox.mayShow(show(.connected, id: " \t\n"), over: .none) == false)
        #expect(EarbudsCuePolicyBox.mayShow(show(.disconnected, id: "\u{1680}\u{2028}"), over: .other) == false)
        let same = EarbudsCueOccupant.earbuds(id: "device-1", name: "Left Bud", connected: true)
        #expect(EarbudsCuePolicyBox.mayShow(show(.levels, id: " device-1 "), over: same) == true)
        let padded = EarbudsCueOccupant.earbuds(id: " device-1 ", name: "Left Bud", connected: true)
        #expect(EarbudsCuePolicyBox.mayShow(show(.levels, id: "device-1"), over: padded) == true)
        #expect(EarbudsCuePolicy.mayShow(show(.levels, id: "device-1"), over: padded) == true)
        #expect(EarbudsCuePolicyBox.mayShow(show(.levels, id: "\u{200B}device-1"), over: same) == false)
        let zero = EarbudsCueOccupant.earbuds(id: "\u{200B}", name: "Left Bud", connected: true)
        #expect(EarbudsCuePolicyBox.mayShow(show(.levels, id: "\u{200B}"), over: zero) == true)
    }

    @Test func protectedCuesAndLevelsFollowTheSameRules() {
        let connect = show(.connected, id: "device-1")
        for cue in EarbudsProtectedCue.allCases {
            #expect(EarbudsCuePolicyBox.mayShow(connect, over: .protected(cue)) == false)
        }
        #expect(EarbudsProtectedCue.allCases.count == 9)
        #expect(EarbudsCuePolicyBox.mayShow(connect, over: .none) == true)
        #expect(EarbudsCuePolicyBox.mayShow(show(.disconnected, id: "device-1"), over: .other) == true)
        let same = EarbudsCueOccupant.earbuds(id: "device-1", name: "Left Bud", connected: true)
        let other = EarbudsCueOccupant.earbuds(id: "device-2", name: "Left Bud", connected: true)
        let down = EarbudsCueOccupant.earbuds(id: "device-1", name: "Left Bud", connected: false)
        #expect(EarbudsCuePolicyBox.mayShow(show(.levels, id: "device-1"), over: same) == true)
        #expect(EarbudsCuePolicyBox.mayShow(show(.levels, id: "device-1"), over: other) == false)
        #expect(EarbudsCuePolicyBox.mayShow(show(.levels, id: "device-1"), over: down) == false)
        #expect(EarbudsCuePolicyBox.mayShow(show(.levels, id: "device-1"), over: .none) == false)
        #expect(EarbudsCuePolicyBox.mayShow(show(.connected, id: "device-1"), over: other) == true)
        #expect(EarbudsCuePolicyBox.mayShow(show(.levels, id: "device-1"), over: other) == false)
    }

    @Test func durationsAreFourSecondsConnectedAndThreeDisconnected() {
        #expect(EarbudsCuePolicyBox.duration(.connected) == 4)
        #expect(EarbudsCuePolicyBox.duration(.levels) == 4)
        #expect(EarbudsCuePolicyBox.duration(.disconnected) == 3)
        #expect(EarbudsCuePolicyBox.connectedDuration == 4)
        #expect(EarbudsCuePolicyBox.disconnectedDuration == 3)
    }

    @Test func thePolicyReadsEachAnswerFromTheBox() {
        let zero = show(.connected, id: "\u{200B}")
        #expect(EarbudsCuePolicy.duration(.connected) == EarbudsCuePolicyBox.duration(.connected))
        #expect(EarbudsCuePolicy.duration(.levels) == EarbudsCuePolicyBox.duration(.levels))
        #expect(EarbudsCuePolicy.duration(.disconnected) == EarbudsCuePolicyBox.duration(.disconnected))
        #expect(EarbudsCuePolicy.connectedDuration == EarbudsCuePolicyBox.connectedDuration)
        #expect(EarbudsCuePolicy.disconnectedDuration == EarbudsCuePolicyBox.disconnectedDuration)
        #expect(EarbudsCuePolicy.mayShow(zero, over: .none) == true)
        #expect(EarbudsCuePolicyBox.mayShow(zero, over: .none) == true)
        #expect(EarbudsCuePolicy.mayShow(zero, over: .protected(.permission)) == false)
        #expect(EarbudsCuePolicyBox.mayShow(zero, over: .protected(.permission)) == false)
    }
}
