import Foundation
import Testing
@testable import ZeusCore

@Suite("Earbuds cue policy")
struct EarbudsCuePolicyTests {
    private func show(_ kind: EarbudsCueShow.Kind, id: String = "device-1", name: String = "Left Bud") -> EarbudsCueShow {
        EarbudsCueShow(id: id, name: name, kind: kind)
    }

    @Test func aConnectIsRefusedOverEachProtectedCueAndAllowedOverNone() {
        let connect = show(.connected)
        for cue in EarbudsProtectedCue.allCases {
            #expect(EarbudsCuePolicy.mayShow(connect, over: .protected(cue)) == false)
        }
        #expect(EarbudsProtectedCue.allCases.count == 9)
        #expect(EarbudsCuePolicy.mayShow(connect, over: .none) == true)
    }

    @Test func aDisconnectIsRefusedOverEachProtectedCueAndAllowedOverAnotherCue() {
        let disconnect = show(.disconnected)
        for cue in EarbudsProtectedCue.allCases {
            #expect(EarbudsCuePolicy.mayShow(disconnect, over: .protected(cue)) == false)
        }
        #expect(EarbudsCuePolicy.mayShow(disconnect, over: .other) == true)
    }

    @Test func aLevelsUpdateIsRefusedOverProtectedCuesAndAllowedOnTheSameConnectedId() {
        let levels = show(.levels)
        for cue in EarbudsProtectedCue.allCases {
            #expect(EarbudsCuePolicy.mayShow(levels, over: .protected(cue)) == false)
        }
        let same = EarbudsCueOccupant.earbuds(id: "device-1", name: "Left Bud", connected: true)
        #expect(EarbudsCuePolicy.mayShow(levels, over: same) == true)
    }

    @Test func aLevelsUpdateDoesNotJumpToTheSameNameWithAnotherId() {
        let levels = show(.levels, id: "device-2", name: "Left Bud")
        let otherDevice = EarbudsCueOccupant.earbuds(id: "device-1", name: "Left Bud", connected: true)
        let sameDevice = EarbudsCueOccupant.earbuds(id: "device-2", name: "Renamed", connected: true)
        #expect(EarbudsCuePolicy.mayShow(levels, over: otherDevice) == false)
        #expect(EarbudsCuePolicy.mayShow(levels, over: sameDevice) == true)
    }

    @Test func aLevelsUpdateStaysOffUntilThatDeviceIsAlreadyConnected() {
        let levels = show(.levels)
        let disconnected = EarbudsCueOccupant.earbuds(id: "device-1", name: "Left Bud", connected: false)
        #expect(EarbudsCuePolicy.mayShow(levels, over: .none) == false)
        #expect(EarbudsCuePolicy.mayShow(levels, over: .other) == false)
        #expect(EarbudsCuePolicy.mayShow(levels, over: disconnected) == false)
        let connected = EarbudsCueOccupant.earbuds(id: "device-1", name: "Left Bud", connected: true)
        #expect(EarbudsCuePolicy.mayShow(levels, over: connected) == true)
    }

    @Test func aConnectMayReplaceAnotherEarbudCueAndALevelsUpdateMayNot() {
        let occupant = EarbudsCueOccupant.earbuds(id: "device-9", name: "Case", connected: true)
        #expect(EarbudsCuePolicy.mayShow(show(.connected), over: occupant) == true)
        #expect(EarbudsCuePolicy.mayShow(show(.disconnected), over: occupant) == true)
        #expect(EarbudsCuePolicy.mayShow(show(.levels), over: occupant) == false)
    }

    @Test func aBlankIdIsRefusedEvenWhenTheNotchIsClear() {
        #expect(EarbudsCuePolicy.mayShow(show(.connected, id: "  "), over: .none) == false)
        #expect(EarbudsCuePolicy.mayShow(show(.disconnected, id: ""), over: .other) == false)
        #expect(EarbudsCuePolicy.mayShow(show(.levels, id: "\n"), over: .earbuds(id: "\n", name: "Left Bud", connected: true)) == false)
        #expect(EarbudsCuePolicy.mayShow(show(.connected, id: "device-1"), over: .none) == true)
    }

    @Test func durationsAreFourSecondsConnectedAndThreeDisconnected() {
        #expect(EarbudsCuePolicy.duration(.connected) == 4)
        #expect(EarbudsCuePolicy.duration(.levels) == 4)
        #expect(EarbudsCuePolicy.duration(.disconnected) == 3)
    }

    @Test func theShownTextOmitsTheNameAndTheDeviceId() {
        let cue = show(.connected, id: "AA:BB:CC:DD:EE:FF", name: "Secret Bud")
        #expect(String(describing: cue).contains("Secret Bud") == false)
        #expect(String(describing: cue).contains("AA:BB:CC:DD:EE:FF") == false)
        #expect(String(reflecting: cue).contains("Secret Bud") == false)
        #expect(String(reflecting: cue).contains("AA:BB:CC:DD:EE:FF") == false)
    }
}
