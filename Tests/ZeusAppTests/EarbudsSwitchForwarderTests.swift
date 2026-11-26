import Foundation
import Testing
@testable import Zeus

@MainActor
@Suite("Earbuds switch forwarder")
struct EarbudsSwitchForwarderTests {
    @Test func presenceOnWhileNotAskedCallsTheSwitchAndNeverAllow() {
        let presence = SwitchFake(access: "notAsked")
        let mode = SwitchFake(access: "notAsked")
        EarbudsSwitchForwarder.forward(
            id: EarbudsSwitchForwarder.presenceID,
            value: true,
            presence: presence,
            mode: mode)
        #expect(presence.access == "notAsked")
        #expect(presence.switches == [true])
        #expect(presence.allows == 0)
        #expect(mode.switches.isEmpty)
        #expect(mode.allows == 0)
    }

    @Test func presenceOffCallsTheSwitchOff() {
        let presence = SwitchFake(access: "allowed")
        let mode = SwitchFake(access: "notAsked")
        EarbudsSwitchForwarder.forward(
            id: "lights.earbuds",
            value: false,
            presence: presence,
            mode: mode)
        #expect(presence.switches == [false])
        #expect(presence.allows == 0)
        #expect(mode.switches.isEmpty)
        #expect(mode.allows == 0)
    }

    @Test func listeningModeOnCallsOnlyTheMode() {
        let presence = SwitchFake(access: "notAsked")
        let mode = SwitchFake(access: "notAsked")
        EarbudsSwitchForwarder.forward(
            id: EarbudsSwitchForwarder.modeID,
            value: true,
            presence: presence,
            mode: mode)
        #expect(mode.switches == [true])
        #expect(mode.allows == 0)
        #expect(presence.switches.isEmpty)
        #expect(presence.allows == 0)
    }

    @Test func listeningModeOffCallsTheModeOff() {
        let presence = SwitchFake(access: "denied")
        let mode = SwitchFake(access: "allowed")
        EarbudsSwitchForwarder.forward(
            id: "earbuds.listeningMode",
            value: false,
            presence: presence,
            mode: mode)
        #expect(mode.switches == [false])
        #expect(mode.allows == 0)
        #expect(presence.switches.isEmpty)
        #expect(presence.allows == 0)
    }

    @Test func anUnknownIdCallsNothing() {
        let ids = [
            "",
            " ",
            "lights.earbud",
            "lights.earbuds ",
            "LIGHTS.EBUDS",
            "earbuds.listeningmode",
            "earbuds.listeningMode ",
            "perm.bluetooth",
            "lights.earbuds.extra",
        ]
        for id in ids {
            let presence = SwitchFake(access: "notAsked")
            let mode = SwitchFake(access: "notAsked")
            EarbudsSwitchForwarder.forward(id: id, value: true, presence: presence, mode: mode)
            #expect(presence.switches.isEmpty)
            #expect(mode.switches.isEmpty)
            #expect(presence.allows == 0)
            #expect(mode.allows == 0)
            #expect(presence.access == "notAsked")
        }
    }

    @Test func aMissingControllerDoesNotCallTheOther() {
        let mode = SwitchFake(access: "notAsked")
        EarbudsSwitchForwarder.forward(
            id: EarbudsSwitchForwarder.presenceID,
            value: true,
            presence: nil,
            mode: mode)
        #expect(mode.switches.isEmpty)
        #expect(mode.allows == 0)

        let presence = SwitchFake(access: "notAsked")
        EarbudsSwitchForwarder.forward(
            id: EarbudsSwitchForwarder.modeID,
            value: true,
            presence: presence,
            mode: nil)
        #expect(presence.switches.isEmpty)
        #expect(presence.allows == 0)
    }

    @Test func eachStoredValueReachesOnlyItsController() {
        let cases: [(String, Bool)] = [
            (EarbudsSwitchForwarder.presenceID, true),
            (EarbudsSwitchForwarder.presenceID, false),
            (EarbudsSwitchForwarder.modeID, true),
            (EarbudsSwitchForwarder.modeID, false),
        ]
        for (id, value) in cases {
            let presence = SwitchFake(access: "notAsked")
            let mode = SwitchFake(access: "notAsked")
            EarbudsSwitchForwarder.forward(id: id, value: value, presence: presence, mode: mode)
            if id == EarbudsSwitchForwarder.presenceID {
                #expect(presence.switches == [value])
                #expect(mode.switches.isEmpty)
            } else {
                #expect(mode.switches == [value])
                #expect(presence.switches.isEmpty)
            }
            #expect(presence.allows == 0)
            #expect(mode.allows == 0)
        }
    }

    @Test func aSecondChangeSendsASecondCall() {
        let presence = SwitchFake(access: "notAsked")
        EarbudsSwitchForwarder.forward(
            id: EarbudsSwitchForwarder.presenceID, value: true, presence: presence, mode: nil)
        EarbudsSwitchForwarder.forward(
            id: EarbudsSwitchForwarder.presenceID, value: false, presence: presence, mode: nil)
        #expect(presence.switches == [true, false])
        #expect(presence.allows == 0)
    }

    @Test func theForwarderNamesNoBluetoothCall() throws {
        let source = try String(contentsOf: sourceURL(), encoding: .utf8)
        let banned = [
            "CBCentralManager",
            "IOBluetooth",
            "scanForPeripherals",
            "batteryPercent",
            "NSBluetooth",
            "URLSession",
            "DispatchQueue.main.sync",
        ]
        for token in banned {
            #expect(!source.contains(token))
        }
        // The prompt door is named once, as a requirement the forwarder does not call.
        #expect(source.components(separatedBy: "ownerPressedAllow").count - 1 == 1)
    }
}

@MainActor
private final class SwitchFake: EarbudsSwitchReceiving {
    var access: String
    var switches: [Bool] = []
    var allows = 0

    init(access: String) {
        self.access = access
    }

    func switchChanged(on: Bool) {
        switches.append(on)
    }

    func ownerPressedAllow() {
        allows += 1
    }
}

private func sourceURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Zeus/Earbuds/EarbudsSwitchForwarder.swift")
}
