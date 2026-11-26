import Foundation
import Testing
@testable import Zeus

@Suite("Step zero output")
struct StepZeroOutputTests {
    private let room = "aabbccddeeff@LivingRoomSpeaker"
    private let longKey = String(repeating: "k", count: 65)

    @Test func transportCodesOutsideTheTableBecomeOther() {
        #expect(OutputSection.transport(code: "bltn") == .builtIn)
        #expect(OutputSection.transport(code: "usb ") == .wired)
        #expect(OutputSection.transport(code: "thun") == .wired)
        #expect(OutputSection.transport(code: "1394") == .wired)
        #expect(OutputSection.transport(code: "pci ") == .wired)
        #expect(OutputSection.transport(code: "eavb") == .wired)
        #expect(OutputSection.transport(code: "blue") == .bluetooth)
        #expect(OutputSection.transport(code: "blea") == .bluetooth)
        #expect(OutputSection.transport(code: "airp") == .wirelessSpeaker)
        #expect(OutputSection.transport(code: "hdmi") == .display)
        #expect(OutputSection.transport(code: "dprt") == .display)
        #expect(OutputSection.transport(code: "virt") == .virtual)
        #expect(OutputSection.transport(code: "grup") == .virtual)
        for code in ["ccwd", "ccwl", "rscr", "rstr", "usb", "AIRP", "airp ", "0", "", "not-a-code"] {
            #expect(OutputSection.transport(code: code) == .other, "\(code)")
        }
    }

    @Test func aWirelessCodeIsSeenAndTheRawCodeIsDropped() {
        let (state, effects) = drive([
            .begin,
            .continueAsked,
            .devices([
                OutputSection.DeviceSample(code: "bltn", connectedOutput: false),
                OutputSection.DeviceSample(code: "airp", connectedOutput: true),
                OutputSection.DeviceSample(code: "not-a-code", connectedOutput: false),
            ]),
        ])
        #expect(effects == [.readDevices])
        #expect(state.transports == [.builtIn, .wirelessSpeaker, .other])
        #expect(state.airpSeen)
        #expect(state.bluetoothConnected == false)
        #expect(state.marks[.devices] == .ran)
        #expect(state.phase == .gate)
        #expect(storedStrings(state).contains("not-a-code") == false)
        #expect(storedStrings(state).contains("airp") == false)
    }

    @Test func theDeviceCapDropsAConnectedOutputPastThirtyTwo() {
        var samples = Array(repeating: OutputSection.DeviceSample(code: "virt", connectedOutput: false), count: 32)
        samples.append(OutputSection.DeviceSample(code: "blue", connectedOutput: true))
        samples.append(OutputSection.DeviceSample(code: "airp", connectedOutput: false))
        let dropped = drive([.begin, .continueAsked, .devices(samples)]).0
        #expect(dropped.transports.count == 32)
        #expect(dropped.bluetoothConnected == false)
        #expect(dropped.airpSeen == false)

        var kept = Array(repeating: OutputSection.DeviceSample(code: "bltn", connectedOutput: false), count: 31)
        kept.append(OutputSection.DeviceSample(code: "blea", connectedOutput: true))
        let within = drive([.begin, .continueAsked, .devices(kept)]).0
        #expect(within.bluetoothConnected)
        #expect(within.transports.last == .bluetooth)
    }

    @Test func aHexPrefixIsCountedAndTheNameIsDropped() {
        #expect(OutputSection.hasRaopHexPrefix(room))
        #expect(OutputSection.hasRaopHexPrefix(String(repeating: "a", count: 16) + "@box"))
        #expect(OutputSection.hasRaopHexPrefix(String(repeating: "A", count: 12) + "@") )
        #expect(OutputSection.hasRaopHexPrefix(String(repeating: "b", count: 11) + "@box") == false)
        #expect(OutputSection.hasRaopHexPrefix(String(repeating: "c", count: 17) + "@box") == false)
        #expect(OutputSection.hasRaopHexPrefix(String(repeating: "d", count: 12)) == false)
        #expect(OutputSection.hasRaopHexPrefix("gggggggggggg@box") == false)

        let rows = [
            OutputSection.Sighting(service: .raop, name: room, keys: ["model", "serialNumber"]),
            OutputSection.Sighting(service: .raop, name: "Plain Speaker", keys: ["am"]),
            OutputSection.Sighting(service: .airplay, name: room, keys: ["model", longKey]),
            OutputSection.Sighting(service: .raop, name: String(repeating: "e", count: 11) + "@box", keys: ["Model"]),
        ]
        let state = drive([.begin, .continueAsked, .devices([]), .continueAsked, .sightings(rows)]).0
        #expect(state.raopCount == 3)
        #expect(state.airplayCount == 1)
        #expect(state.hexPrefixCount == 1)
        #expect(state.modelKey)
        #expect(state.amKey)
        #expect(state.sightingsTaken == 4)
        let stored = storedStrings(state)
        #expect(stored.contains(room) == false)
        #expect(stored.contains("Plain Speaker") == false)
        #expect(stored.contains("serialNumber") == false)
        #expect(stored.contains(longKey) == false)
        #expect(stored.contains("Model") == false)
    }

    @Test func recordKeysOutsideTheTwoAreIgnored() {
        let sixtyFour = String(repeating: "m", count: 64)
        let rows = [
            OutputSection.Sighting(service: .airplay, name: "box", keys: [sixtyFour, "deviceid", "am"]),
            OutputSection.Sighting(service: .raop, name: "other", keys: [longKey, "model"]),
        ]
        let state = drive([.begin, .continueAsked, .devices([]), .continueAsked, .sightings(rows)]).0
        #expect(state.modelKey)
        #expect(state.amKey)
        #expect(storedStrings(state).contains(sixtyFour) == false)
        #expect(storedStrings(state).contains("deviceid") == false)
    }

    @Test func theSightingCapStopsAtOneHundredTwentyEight() {
        let plain = (0..<127).map { _ in
            OutputSection.Sighting(service: .raop, name: "plain", keys: [])
        }
        let counted = OutputSection.Sighting(service: .raop, name: room, keys: ["model"])
        let dropped = OutputSection.Sighting(service: .airplay, name: room, keys: ["am"])
        let state = drive([
            .begin, .continueAsked, .devices([]), .continueAsked,
            .sightings(plain + [counted, dropped]),
        ]).0
        #expect(state.sightingsTaken == 128)
        #expect(state.raopCount == 128)
        #expect(state.airplayCount == 0)
        #expect(state.hexPrefixCount == 1)
        #expect(state.modelKey)
        #expect(state.amKey == false)
        #expect(storedStrings(state).contains(room) == false)
    }

    @Test func theBrowserCancelsAtTwentySecondsAndWhenThePartEnds() {
        let started = drive([.begin, .continueAsked, .devices([]), .continueAsked])
        #expect(started.1 == [.readDevices, .startBrowse(.airplay), .startBrowse(.raop)])
        #expect(started.0.phase == .browsing)

        let early = drive([
            .begin, .continueAsked, .devices([]), .continueAsked,
            .waited(milliseconds: 19_999),
            .browse(.ready),
            .endNetwork,
            .waited(milliseconds: 20_000),
        ])
        #expect(early.0.clockMs == 0)
        #expect(early.0.browseMarks == [.results])
        #expect(early.0.browseCancelled)
        #expect(early.0.marks[.network] == .ran)
        #expect(early.0.phase == .gate)
        #expect(early.1.filter { $0 == .cancelBrowse }.count == 1)
        #expect(OutputSection.browseMark(.ready) == .results)
        #expect(OutputSection.browseMark(.results) == .results)
        #expect(OutputSection.browseMark(.failed) == .failed)

        let limited = drive([
            .begin, .continueAsked, .devices([]), .continueAsked,
            .browse(.failed),
            .waited(milliseconds: 20_000),
            .endNetwork,
        ])
        #expect(limited.0.browseMarks == [.failed])
        #expect(limited.0.browseCancelled)
        #expect(limited.1.filter { $0 == .cancelBrowse }.count == 1)
        #expect(limited.0.phase == .gate)
    }

    @Test func waitingBeforeTheAnswerLeavesTheBrowserRunning() {
        let waiting = drive([
            .begin, .continueAsked, .devices([]), .continueAsked,
            .browse(.waiting),
            .waited(milliseconds: 1_000),
        ])
        #expect(waiting.0.waitingBeforeAnswer)
        #expect(waiting.0.browseCancelled == false)
        #expect(waiting.1.contains(.cancelBrowse) == false)
        #expect(waiting.0.phase == .browsing)

        let after = drive([
            .begin, .continueAsked, .devices([]), .continueAsked,
            .networkAnswered,
            .browse(.waiting),
        ])
        #expect(after.0.networkAnswered)
        #expect(after.0.waitingBeforeAnswer == false)
        #expect(after.0.browseMarks == [.waiting])
        #expect(after.1.contains(.cancelBrowse) == false)
    }

    @Test func theSwitchNeedsAConnectedBluetoothOutput() {
        let missing = drive([
            .begin,
            .continueAsked,
            .devices([
                OutputSection.DeviceSample(code: "blue", connectedOutput: false),
                OutputSection.DeviceSample(code: "airp", connectedOutput: true),
            ]),
            .skip,
            .continueAsked,
        ])
        #expect(missing.0.bluetoothConnected == false)
        #expect(missing.0.marks[.network] == .skipped)
        #expect(missing.0.marks[.switchOutput] == .notMeasured)
        #expect(missing.0.wrote == false)
        #expect(missing.0.restoreSent == false)
        #expect(missing.0.movedBack == nil)
        #expect(missing.0.msToReadBack == nil)
        #expect(missing.1.contains(.writeDefault) == false)
        #expect(missing.1.contains(.restoreDefault) == false)
        #expect(missing.1.contains(.readOutput) == false)
        #expect(missing.1.contains(.startBrowse(.airplay)) == false)

        let skippedDevices = drive([.begin, .skip, .skip, .continueAsked])
        #expect(skippedDevices.0.marks[.devices] == .skipped)
        #expect(skippedDevices.0.marks[.switchOutput] == .notMeasured)
        #expect(skippedDevices.1.isEmpty)
    }

    @Test func theSwitchWritesOnceAndPutsTheFirstDeviceBack() {
        var state = OutputSection.fresh()
        var effects: [OutputSection.Effect] = []
        func push(_ event: OutputSection.Event) {
            let reduced = OutputSection.reduce(state, event)
            state = reduced.state
            effects.append(contentsOf: reduced.effects)
        }

        push(.begin)
        push(.continueAsked)
        push(.devices([OutputSection.DeviceSample(code: "blue", connectedOutput: true)]))
        push(.skip)
        push(.continueAsked)
        push(.readBack(onTarget: true, onOriginal: false))
        #expect(state.msToReadBack == 0)
        push(.waited(milliseconds: 50))
        #expect(effects.filter { $0 == .readOutput }.count == 1)
        push(.waited(milliseconds: 50))
        #expect(effects.filter { $0 == .readOutput }.count == 2)
        push(.readBack(onTarget: false, onOriginal: true))
        #expect(state.movedBack == true)

        while state.phase == .switching {
            push(.waited(milliseconds: 100))
            if state.phase != .switching { break }
            push(.readBack(onTarget: false, onOriginal: true))
        }
        #expect(state.phase == .restoring)
        #expect(state.movedBack == true)
        #expect(state.msToReadBack == 0)
        let restoreAt = effects.firstIndex(of: .restoreDefault)
        #expect(restoreAt != nil)
        let before = effects[..<restoreAt!].filter { $0 == .readOutput }.count
        #expect(before == 50)
        #expect(effects.filter { $0 == .writeDefault }.count == 1)
        #expect(effects.filter { $0 == .restoreDefault }.count == 1)

        push(.readBack(onTarget: false, onOriginal: true))
        #expect(state.restored == .yes)
        #expect(state.marks[.switchOutput] == .ran)
        #expect(state.phase == .gate)
        #expect(effects.filter { $0 == .writeDefault }.count == 1)
        #expect(effects.filter { $0 == .restoreDefault }.count == 1)
        #expect(storedStrings(state).isEmpty)
    }

    @Test func aStalledCallStillRestoresOnce() {
        let stalled = drive([
            .begin,
            .continueAsked,
            .devices([OutputSection.DeviceSample(code: "blea", connectedOutput: true)]),
            .skip,
            .continueAsked,
            .waited(milliseconds: 2_000),
            .waited(milliseconds: 2_000),
        ])
        #expect(stalled.1.filter { $0 == .writeDefault }.count == 1)
        #expect(stalled.1.filter { $0 == .restoreDefault }.count == 1)
        #expect(stalled.0.restored == .unknown)
        #expect(stalled.0.movedBack == false)
        #expect(stalled.0.marks[.switchOutput] == .ran)
        #expect(stalled.0.phase == .gate)

        let stayed = drive([
            .begin,
            .continueAsked,
            .devices([OutputSection.DeviceSample(code: "blue", connectedOutput: true)]),
            .skip,
            .continueAsked,
            .readBack(onTarget: true, onOriginal: false),
            .waited(milliseconds: 5_000),
            .readBack(onTarget: true, onOriginal: true),
        ])
        #expect(stayed.0.movedBack == false)
        #expect(stayed.0.msToReadBack == 0)
        #expect(stayed.0.restored == .yes)
        #expect(stayed.1.filter { $0 == .restoreDefault }.count == 1)
    }

    @Test func theMenuRecordsTheOwnerAndReadsNothing() {
        let answered = drive([
            .begin, .skip, .skip, .skip, .continueAsked, .menu(.notTried),
        ])
        #expect(answered.1 == [.askMenu])
        #expect(answered.0.menu == .notTried)
        #expect(answered.0.marks[.menu] == .ran)
        #expect(answered.0.phase == .done)
        #expect(answered.1.contains(.readDevices) == false)
        #expect(answered.1.contains(.readOutput) == false)

        let skipped = drive([.begin, .skip, .skip, .skip, .skip])
        #expect(skipped.0.marks[.menu] == .skipped)
        #expect(skipped.0.menu == nil)
        #expect(skipped.0.phase == .done)
        #expect(skipped.1.isEmpty)

        let ignored = drive([.menu(.yes), .begin, .begin])
        #expect(ignored.0.phase == .gate)
        #expect(ignored.0.menu == nil)
        #expect(ignored.1.isEmpty)
    }

    private func drive(_ events: [OutputSection.Event]) -> (OutputSection.State, [OutputSection.Effect]) {
        var state = OutputSection.fresh()
        var effects: [OutputSection.Effect] = []
        for event in events {
            let reduced = OutputSection.reduce(state, event)
            state = reduced.state
            effects.append(contentsOf: reduced.effects)
        }
        return (state, effects)
    }

    private func storedStrings(_ state: OutputSection.State) -> [String] {
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
