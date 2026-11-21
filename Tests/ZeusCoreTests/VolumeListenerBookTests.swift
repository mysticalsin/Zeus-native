import Foundation
import Testing
@testable import ZeusCore

@Suite struct VolumeListenerBookTests {
    @Test func aNewDeviceDropsTheOldListeners() {
        var book = VolumeListenerBook()
        let first = ids(device: 1)
        let second = ids(device: 2)
        _ = book.replace(with: first)
        let change = book.replace(with: second)
        #expect(book.installed == second)
        #expect(Set(change.remove) == Set(first))
        #expect(change.add == second)
    }

    @Test func theSameDeviceDoesNotDuplicate() {
        var book = VolumeListenerBook()
        let set = ids(device: 4)
        _ = book.replace(with: set)
        let again = book.replace(with: set)
        #expect(again.remove.isEmpty)
        #expect(again.add.isEmpty)
        #expect(book.installed == set)
    }

    @Test func randomDeviceChangesKeepOnlyTheLatestSet() {
        var rng = VolumeSplitMix(state: 0xA01)
        var book = VolumeListenerBook()
        for _ in 0..<200 {
            let device = UInt32(rng.next() % 6) + 1
            let count = Int(rng.next() % 4) + 1
            var next: [VolumeListenerID] = []
            for index in 0..<count {
                next.append(VolumeListenerID(device: device, selector: UInt32(index + 1), element: UInt32(rng.next() % 3)))
            }
            let change = book.replace(with: next)
            var unique: [VolumeListenerID] = []
            for id in next where !unique.contains(id) { unique.append(id) }
            #expect(book.installed == unique)
            for id in change.remove {
                #expect(unique.contains(id) == false)
            }
            for id in change.add {
                #expect(unique.contains(id))
            }
        }
    }

    @Test func stressSwitchingHeadphonesNeverAccumulates() {
        var book = VolumeListenerBook()
        for device in 1...100 {
            let next = ids(device: UInt32(device))
            _ = book.replace(with: next)
            #expect(book.installed.count == next.count)
            #expect(book.installed.allSatisfy { $0.device == UInt32(device) })
        }
    }

    private func ids(device: UInt32) -> [VolumeListenerID] {
        [
            VolumeListenerID(device: device, selector: 1, element: 0),
            VolumeListenerID(device: device, selector: 2, element: 1),
            VolumeListenerID(device: device, selector: 2, element: 2),
        ]
    }
}

struct VolumeSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
