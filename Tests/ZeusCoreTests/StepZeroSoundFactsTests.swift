import Foundation
import Testing
@testable import ZeusCore

@Suite("Step zero sound facts")
struct StepZeroSoundFactsTests {
    private let room = "aabbccddeeff@LivingRoomSpeaker"
    private let longKey = String(repeating: "k", count: 65)
    private let airplay = StepZeroSoundFacts.airplayType
    private let raop = StepZeroSoundFacts.raopType

    @Test func transportCodesOutsideTheTableBecomeOther() {
        #expect(StepZeroSoundFacts.transport(code: "bltn") == .builtIn)
        #expect(StepZeroSoundFacts.transport(code: "usb ") == .wired)
        #expect(StepZeroSoundFacts.transport(code: "thun") == .wired)
        #expect(StepZeroSoundFacts.transport(code: "1394") == .wired)
        #expect(StepZeroSoundFacts.transport(code: "pci ") == .wired)
        #expect(StepZeroSoundFacts.transport(code: "eavb") == .wired)
        #expect(StepZeroSoundFacts.transport(code: "blue") == .bluetooth)
        #expect(StepZeroSoundFacts.transport(code: "blea") == .bluetooth)
        #expect(StepZeroSoundFacts.transport(code: "airp") == .wirelessSpeaker)
        #expect(StepZeroSoundFacts.transport(code: "hdmi") == .display)
        #expect(StepZeroSoundFacts.transport(code: "dprt") == .display)
        #expect(StepZeroSoundFacts.transport(code: "virt") == .virtual)
        #expect(StepZeroSoundFacts.transport(code: "grup") == .virtual)
        for code in ["ccwd", "ccwl", "rscr", "rstr", "usb", "AIRP", "airp ", "0", "", "not-a-code"] {
            #expect(StepZeroSoundFacts.transport(code: code) == .other)
        }
        let invented = "not-a-code"
        #expect(String(describing: StepZeroSoundFacts.transport(code: invented)).contains(invented) == false)
        #expect(StepZeroSoundFacts.transport(code: nil) == .other)
    }

    @Test func aWirelessCodeIsSeenAndTheRawCodeIsDropped() {
        let tally = StepZeroSoundFacts.read(
            devices: [
                StepZeroSoundFacts.DeviceReading(code: "bltn", connectedOutput: false),
                StepZeroSoundFacts.DeviceReading(code: "airp", connectedOutput: true),
                StepZeroSoundFacts.DeviceReading(code: "not-a-code", connectedOutput: false),
                StepZeroSoundFacts.DeviceReading(code: nil, connectedOutput: true),
            ],
            announcements: []
        )
        #expect(tally.transports == [.builtIn, .wirelessSpeaker, .other, .other])
        #expect(tally.airpSeen)
        #expect(tally.bluetoothConnected == false)
        #expect(tally.sightingsTaken == 0)
        let stored = storedStrings(tally)
        #expect(stored.contains("airp") == false)
        #expect(stored.contains("not-a-code") == false)
        #expect(stored.contains("bltn") == false)
    }

    @Test func theDeviceCapDropsAConnectedOutputPastThirtyTwo() {
        var samples = Array(
            repeating: StepZeroSoundFacts.DeviceReading(code: "virt", connectedOutput: false),
            count: 32
        )
        samples.append(StepZeroSoundFacts.DeviceReading(code: "blue", connectedOutput: true))
        samples.append(StepZeroSoundFacts.DeviceReading(code: "airp", connectedOutput: false))
        let dropped = StepZeroSoundFacts.read(devices: samples, announcements: [])
        #expect(dropped.transports.count == 32)
        #expect(dropped.transports.allSatisfy { $0 == .virtual })
        #expect(dropped.bluetoothConnected == false)
        #expect(dropped.airpSeen == false)

        var kept = Array(
            repeating: StepZeroSoundFacts.DeviceReading(code: "bltn", connectedOutput: false),
            count: 31
        )
        kept.append(StepZeroSoundFacts.DeviceReading(code: "blea", connectedOutput: true))
        let within = StepZeroSoundFacts.read(devices: kept, announcements: [])
        #expect(within.bluetoothConnected)
        #expect(within.transports.last == .bluetooth)
        #expect(within.airpSeen == false)

        let quiet = StepZeroSoundFacts.read(
            devices: [StepZeroSoundFacts.DeviceReading(code: "blue", connectedOutput: false)],
            announcements: []
        )
        #expect(quiet.transports == [.bluetooth])
        #expect(quiet.bluetoothConnected == false)
    }

    @Test func aNameWithThe12HexPrefixIsCountedAndNeverKept() {
        let wide = String(repeating: "a", count: 16) + "@box"
        let exact = String(repeating: "A", count: 12) + "@"
        let short = String(repeating: "b", count: 11) + "@box"
        let over = String(repeating: "c", count: 17) + "@box"
        let bare = String(repeating: "d", count: 12)
        let bad = "gggggggggggg@box"
        let later = "room-" + room
        let rows = [
            StepZeroSoundFacts.Announcement(type: raop, name: room, keys: []),
            StepZeroSoundFacts.Announcement(type: raop, name: wide, keys: []),
            StepZeroSoundFacts.Announcement(type: raop, name: exact, keys: []),
            StepZeroSoundFacts.Announcement(type: raop, name: short, keys: []),
            StepZeroSoundFacts.Announcement(type: raop, name: over, keys: []),
            StepZeroSoundFacts.Announcement(type: raop, name: bare, keys: []),
            StepZeroSoundFacts.Announcement(type: raop, name: bad, keys: []),
            StepZeroSoundFacts.Announcement(type: raop, name: later, keys: []),
            StepZeroSoundFacts.Announcement(type: raop, name: "Plain Speaker", keys: []),
        ]
        let tally = StepZeroSoundFacts.read(devices: [], announcements: rows)
        #expect(tally.raopCount == 9)
        #expect(tally.airplayCount == 0)
        #expect(tally.hexPrefixCount == 3)
        #expect(tally.sightingsTaken == 9)
        let stored = storedStrings(tally)
        for name in [room, wide, exact, short, over, bare, bad, later, "Plain Speaker"] {
            #expect(stored.contains(name) == false)
        }
    }

    @Test func anAirplayNameWithThatShapeDoesNotIncrementThePrefixCount() {
        let tally = StepZeroSoundFacts.read(
            devices: [],
            announcements: [
                StepZeroSoundFacts.Announcement(type: airplay, name: room, keys: ["model"]),
                StepZeroSoundFacts.Announcement(type: raop, name: "Plain Speaker", keys: ["am"]),
            ]
        )
        #expect(tally.airplayCount == 1)
        #expect(tally.raopCount == 1)
        #expect(tally.hexPrefixCount == 0)
        #expect(tally.modelKey)
        #expect(tally.amKey)
        let stored = storedStrings(tally)
        #expect(stored.contains(room) == false)
        #expect(stored.contains("Plain Speaker") == false)
        #expect(stored.contains(airplay) == false)
        #expect(stored.contains(raop) == false)
    }

    @Test func recordKeysOutsideTheTwoAreIgnored() {
        let sixtyFour = String(repeating: "m", count: 64)
        let tally = StepZeroSoundFacts.read(
            devices: [],
            announcements: [
                StepZeroSoundFacts.Announcement(type: airplay, name: "box", keys: [sixtyFour, "deviceid", "am", "AM"]),
                StepZeroSoundFacts.Announcement(type: raop, name: "other", keys: [longKey, "model", "Model", " model"]),
            ]
        )
        #expect(tally.modelKey)
        #expect(tally.amKey)
        #expect(tally.sightingsTaken == 2)
        let stored = storedStrings(tally)
        #expect(stored.contains(sixtyFour) == false)
        #expect(stored.contains(longKey) == false)
        #expect(stored.contains("deviceid") == false)
        #expect(stored.contains("Model") == false)
        #expect(stored.contains("box") == false)
        #expect(stored.contains("other") == false)

        let onlyLong = StepZeroSoundFacts.read(
            devices: [],
            announcements: [
                StepZeroSoundFacts.Announcement(type: raop, name: room, keys: [longKey, sixtyFour]),
            ]
        )
        #expect(onlyLong.modelKey == false)
        #expect(onlyLong.amKey == false)
        #expect(onlyLong.hexPrefixCount == 1)
        #expect(storedStrings(onlyLong).contains(longKey) == false)
        #expect(storedStrings(onlyLong).contains(sixtyFour) == false)
    }

    @Test func theAnnouncementCapStopsAtOneHundredTwentyEight() {
        let plain = (0..<127).map { _ in
            StepZeroSoundFacts.Announcement(type: raop, name: "plain", keys: [])
        }
        let counted = StepZeroSoundFacts.Announcement(type: raop, name: room, keys: ["model"])
        let dropped = StepZeroSoundFacts.Announcement(type: airplay, name: room, keys: ["am"])
        let tally = StepZeroSoundFacts.read(devices: [], announcements: plain + [counted, dropped])
        #expect(tally.sightingsTaken == 128)
        #expect(tally.raopCount == 128)
        #expect(tally.airplayCount == 0)
        #expect(tally.hexPrefixCount == 1)
        #expect(tally.modelKey)
        #expect(tally.amKey == false)
        #expect(storedStrings(tally).contains(room) == false)
        #expect(storedStrings(tally).contains("plain") == false)
    }

    @Test func anUnknownTypeUsesASlotAndSetsNoFlag() {
        #expect(StepZeroSoundFacts.declaredTypes == [airplay, raop])
        let junk = StepZeroSoundFacts.Announcement(type: "_raop._udp", name: room, keys: ["model", "am"])
        let blocked = Array(repeating: junk, count: 128)
        let late = StepZeroSoundFacts.Announcement(type: raop, name: room, keys: ["model"])
        let tally = StepZeroSoundFacts.read(devices: [], announcements: blocked + [late])
        #expect(tally.sightingsTaken == 128)
        #expect(tally.raopCount == 0)
        #expect(tally.airplayCount == 0)
        #expect(tally.hexPrefixCount == 0)
        #expect(tally.modelKey == false)
        #expect(tally.amKey == false)
        let stored = storedStrings(tally)
        #expect(stored.contains(room) == false)
        #expect(stored.contains("_raop._udp") == false)
        #expect(stored.contains("model") == false)
    }

    @Test func aSecondReadStartsEmpty() {
        let first = StepZeroSoundFacts.read(
            devices: [StepZeroSoundFacts.DeviceReading(code: "airp", connectedOutput: true)],
            announcements: [StepZeroSoundFacts.Announcement(type: raop, name: room, keys: ["model"])]
        )
        #expect(first.airpSeen)
        #expect(first.hexPrefixCount == 1)
        #expect(first.modelKey)
        let second = StepZeroSoundFacts.read(devices: [], announcements: [])
        #expect(second == StepZeroSoundFacts.Tally())
        #expect(storedStrings(first).isEmpty)
        #expect(storedStrings(second).isEmpty)
    }

    private func storedStrings(_ tally: StepZeroSoundFacts.Tally) -> [String] {
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
        walk(tally)
        return found
    }
}
