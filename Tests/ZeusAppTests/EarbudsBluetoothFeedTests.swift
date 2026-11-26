import Foundation
import Testing
@testable import Zeus

@Suite("Earbuds Bluetooth feed")
struct EarbudsBluetoothFeedTests {
    private let feed = EarbudsBluetoothFeed.self

    @Test func theAudioClassIsTheThreeEarbudMinors() {
        #expect(feed.AudioClass.major == 0x04)
        #expect(feed.AudioClass.headset == 0x01)
        #expect(feed.AudioClass.handsFree == 0x02)
        #expect(feed.AudioClass.headphones == 0x06)
        let minors: Set<UInt8> = [0x01, 0x02, 0x06]
        #expect(minors.count == 3)
    }

    @Test func accessThatIsNotAllowedRegistersNothing() {
        let tally = Tally()
        let (start, book) = feed.start(.empty, gate(tally, allowed: false, connect: true, devices: [earbuds("aa")]))
        #expect(start == .refused)
        #expect(book == .empty)
        #expect(tally.kinds == ["allowed"])
        #expect(tally.disconnects.isEmpty)
        #expect(tally.unregisters.isEmpty)
        #expect(tally.connectReleases == 0)
    }

    @Test func aNilConnectRegistrationHoldsNothing() {
        let tally = Tally()
        let (start, book) = feed.start(.empty, gate(tally, allowed: true, connect: false, devices: [earbuds("aa")]))
        #expect(start == .failed)
        #expect(book == .empty)
        #expect(tally.kinds == ["allowed", "connect"])
        #expect(tally.disconnects.isEmpty)
        #expect(tally.unregisters.isEmpty)
        #expect(tally.connectReleases == 0)
    }

    @Test func startHoldsOneConnectAndOneDisconnectPerDevice() {
        let tally = Tally()
        let first = earbuds("AA:BB:CC:DD:EE:FF", name: "Left", minor: feed.AudioClass.headset)
        let second = earbuds("11", name: "Right", minor: feed.AudioClass.handsFree)
        let third = earbuds("22", name: "Case", minor: feed.AudioClass.headphones)
        let (start, book) = feed.start(.empty, gate(tally, devices: [first, second, third]))
        let expected = feed.Book(connectHeld: true, disconnects: [first.address, second.address, third.address])
        #expect(start == .started(expected, devices: [first, second, third]))
        #expect(book == expected)
        #expect(tally.kinds == ["allowed", "connect", "devices", "disconnect", "disconnect", "disconnect"])
        #expect(tally.disconnects == [first.address, second.address, third.address])
        #expect(tally.unregisters.isEmpty)
    }

    @Test func aDeviceThatIsNotEarbudsIsLeftOut() {
        let kept = earbuds("kept")
        let rejected = [
            earbuds(""),
            earbuds(" \n\t"),
            earbuds("unpaired", paired: false),
            earbuds("away", connected: false),
            earbuds("phone", major: 0x02),
            earbuds("speaker", minor: 0x05),
            earbuds("mic", minor: 0x04),
            earbuds("car", minor: 0x08),
            earbuds("loose", minor: 0x00),
        ]
        for record in rejected {
            #expect(feed.qualifies(record) == false)
        }
        #expect(feed.qualifies(kept))
        let tally = Tally()
        let (start, book) = feed.start(.empty, gate(tally, devices: rejected + [kept]))
        let expected = feed.Book(connectHeld: true, disconnects: ["kept"])
        #expect(start == .started(expected, devices: [kept]))
        #expect(book == expected)
        #expect(tally.disconnects == ["kept"])
    }

    @Test func aRepeatedAddressRegistersOnce() {
        let upper = earbuds("AA:BB", name: "One")
        let again = earbuds("AA:BB", name: "Two")
        let other = earbuds("aa:bb", name: "Other")
        let tally = Tally()
        let (start, book) = feed.start(.empty, gate(tally, devices: [upper, again, other]))
        #expect(book.disconnects == ["AA:BB", "aa:bb"])
        if case .started(_, let devices) = start {
            #expect(devices.map(\.name) == ["One", "Other"])
            #expect(devices.map(\.address) == ["AA:BB", "aa:bb"])
        } else {
            Issue.record("start did not hold the two addresses")
        }
        #expect(tally.disconnects == ["AA:BB", "aa:bb"])
    }

    @Test func aSecondStartWhileWatchingRegistersNothing() {
        let tally = Tally()
        let first = feed.start(.empty, gate(tally, devices: [earbuds("aa")]))
        let watching = first.1
        let again = feed.start(watching, gate(tally, devices: [earbuds("bb")]))
        #expect(again.0 == .already(watching))
        #expect(again.1 == watching)
        #expect(tally.kinds == ["allowed", "connect", "devices", "disconnect"])
    }

    @Test func aDisconnectWithoutAConnectRegistrationRefusesStart() {
        let tally = Tally()
        let stale = feed.Book(connectHeld: false, disconnects: ["aa"])
        let (start, book) = feed.start(stale, gate(tally, devices: [earbuds("bb")]))
        #expect(start == .refused)
        #expect(book == stale)
        #expect(tally.kinds.isEmpty)
    }

    @Test func noConnectedDeviceStillHoldsTheConnectRegistration() {
        let tally = Tally()
        let (start, book) = feed.start(.empty, gate(tally, devices: []))
        #expect(start == .started(.init(connectHeld: true), devices: []))
        #expect(book == feed.Book(connectHeld: true))
        #expect(tally.kinds == ["allowed", "connect", "devices"])
        #expect(tally.disconnects.isEmpty)
    }

    @Test func aNilDisconnectRegistrationSkipsThatDeviceOnly() {
        let tally = Tally()
        tally.refuseDisconnect = ["bad"]
        let (start, book) = feed.start(
            .empty,
            gate(tally, devices: [earbuds("bad", name: "First"), earbuds("bad", name: "Second"), earbuds("good")])
        )
        let expected = feed.Book(connectHeld: true, disconnects: ["good"])
        #expect(start == .started(expected, devices: [earbuds("good")]))
        #expect(book == expected)
        #expect(tally.disconnects == ["bad", "good"])
    }

    @Test func watchDisconnectHoldsOneAndASecondCallDoesNot() {
        let tally = Tally()
        let watching = feed.Book(connectHeld: true)
        let (first, held) = feed.watchDisconnect(watching, address: "AA:BB", gate(tally))
        #expect(first == .held)
        #expect(held.disconnects == ["AA:BB"])
        let (second, still) = feed.watchDisconnect(held, address: "AA:BB", gate(tally))
        #expect(second == .ignored)
        #expect(still == held)
        let (otherCase, both) = feed.watchDisconnect(still, address: "aa:bb", gate(tally))
        #expect(otherCase == .held)
        #expect(both.disconnects == ["AA:BB", "aa:bb"])
        #expect(tally.kinds == ["disconnect", "disconnect"])
        #expect(tally.disconnects == ["AA:BB", "aa:bb"])
    }

    @Test func watchDisconnectWhileStoppedOrBlankRegistersNothing() {
        let tally = Tally()
        let stopped = feed.watchDisconnect(.empty, address: "aa", gate(tally))
        #expect(stopped.0 == .ignored)
        #expect(stopped.1 == .empty)
        let watching = feed.Book(connectHeld: true, disconnects: ["aa"])
        let blank = feed.watchDisconnect(watching, address: " \n", gate(tally))
        #expect(blank.0 == .ignored)
        #expect(blank.1 == watching)
        #expect(tally.kinds.isEmpty)
    }

    @Test func aNilWatchDoesNotHoldTheAddress() {
        let tally = Tally()
        tally.refuseDisconnect = ["aa"]
        let watching = feed.Book(connectHeld: true)
        let (watch, book) = feed.watchDisconnect(watching, address: "aa", gate(tally))
        #expect(watch == .missed)
        #expect(book == watching)
        #expect(tally.disconnects == ["aa"])
        let (later, held) = feed.watchDisconnect(book, address: "aa", gate(tally, refuseCleared: true))
        #expect(later == .held)
        #expect(held.disconnects == ["aa"])
    }

    @Test func unwatchDropsOneAndLeavesTheConnectRegistration() {
        let tally = Tally()
        let watching = feed.Book(connectHeld: true, disconnects: ["aa", "bb", "cc"])
        let unknown = feed.unwatch(watching, address: "zz", gate(tally))
        #expect(unknown == watching)
        #expect(tally.kinds.isEmpty)
        let dropped = feed.unwatch(unknown, address: "bb", gate(tally))
        #expect(dropped == feed.Book(connectHeld: true, disconnects: ["aa", "cc"]))
        #expect(tally.kinds == ["unregister"])
        #expect(tally.unregisters == ["bb"])
        #expect(tally.connectReleases == 0)
        let again = feed.watchDisconnect(dropped, address: "bb", gate(tally))
        #expect(again.0 == .held)
        #expect(again.1.disconnects == ["aa", "cc", "bb"])
    }

    @Test func stopUnregistersEverythingAndASecondStopDoesNothing() {
        let tally = Tally()
        let watching = feed.Book(connectHeld: true, disconnects: ["aa", "bb"])
        let stopped = feed.stop(watching, gate(tally))
        #expect(stopped == .empty)
        #expect(tally.kinds == ["release", "unregister", "unregister"])
        #expect(tally.connectReleases == 1)
        #expect(tally.unregisters == ["aa", "bb"])
        let again = feed.stop(stopped, gate(tally))
        #expect(again == .empty)
        #expect(tally.kinds == ["release", "unregister", "unregister"])
        let after = feed.watchDisconnect(again, address: "aa", gate(tally))
        #expect(after.0 == .ignored)
        #expect(tally.disconnects.isEmpty)
    }

    @Test func stopDropsLeftoverDisconnectsWithoutAConnectRegistration() {
        let tally = Tally()
        let stale = feed.Book(connectHeld: false, disconnects: ["aa"])
        let stopped = feed.stop(stale, gate(tally))
        #expect(stopped == .empty)
        #expect(tally.kinds == ["unregister"])
        #expect(tally.connectReleases == 0)
        #expect(tally.unregisters == ["aa"])
    }

    @Test func copyKeepsThePlainFieldsAfterTheSourceChanges() {
        let box = RecordBox(earbuds("aa", name: "Secret\nBuds"))
        let copied = feed.copy(box.record)
        box.record = earbuds("zz", name: "Other", paired: false, connected: false, major: 0, minor: 0)
        #expect(copied == earbuds("aa", name: "Secret\nBuds"))
        #expect(copied.name == "Secret\nBuds")
        #expect(copied.address == "aa")
        #expect(box.record.address == "zz")
    }

    private func earbuds(
        _ address: String,
        name: String = "Buds",
        paired: Bool = true,
        connected: Bool = true,
        major: UInt8 = EarbudsBluetoothFeed.AudioClass.major,
        minor: UInt8 = EarbudsBluetoothFeed.AudioClass.headset
    ) -> EarbudsBluetoothFeed.Record {
        feed.Record(
            address: address, name: name, paired: paired,
            major: major, minor: minor, connected: connected
        )
    }

    private func gate(
        _ tally: Tally,
        allowed: Bool = true,
        connect: Bool = true,
        devices: [EarbudsBluetoothFeed.Record] = [],
        refuseCleared: Bool = false
    ) -> EarbudsBluetoothFeed.Gate {
        feed.Gate(
            allowed: {
                tally.kinds.append("allowed")
                return allowed
            },
            registerConnect: {
                tally.kinds.append("connect")
                return connect
            },
            devices: {
                tally.kinds.append("devices")
                return devices
            },
            registerDisconnect: { address in
                tally.kinds.append("disconnect")
                tally.disconnects.append(address)
                if refuseCleared { return true }
                return !tally.refuseDisconnect.contains(address)
            },
            unregisterDisconnect: { address in
                tally.kinds.append("unregister")
                tally.unregisters.append(address)
            },
            unregisterConnect: {
                tally.kinds.append("release")
                tally.connectReleases += 1
            }
        )
    }
}

private final class RecordBox: @unchecked Sendable {
    var record: EarbudsBluetoothFeed.Record
    init(_ record: EarbudsBluetoothFeed.Record) { self.record = record }
}

private final class Tally: @unchecked Sendable {
    var kinds: [String] = []
    var disconnects: [String] = []
    var unregisters: [String] = []
    var connectReleases = 0
    var refuseDisconnect: Set<String> = []
}
