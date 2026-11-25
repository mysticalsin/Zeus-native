import Testing
@testable import ZeusCore

@Suite struct DuckLeaseTests {
    private func device(_ id: String, volume: Float = 0.8, muted: Bool = false) -> DuckDevice {
        DuckDevice(id: id, volume: volume, muted: muted)
    }

    @Test func theDuckStaysUntilTheLastHolderEnds() {
        var lease = DuckLease()
        let first = lease.begin(device("speakers"))
        let second = lease.begin(device("speakers"))
        let ducked = AudioQuiet.duckTarget(snapshotVolume: 0.8, snapshotMuted: false)
        #expect(first.commands.map(\.volume) == [ducked].compactMap { $0 })
        #expect(second.commands.isEmpty)
        #expect(lease.end(token: first.token).isEmpty)
        let restored = lease.end(token: second.token)
        #expect(restored.map(\.volume) == [0.8])
        #expect(lease.isHolding == false)
    }

    @Test func aStaleEndDoesNotRestoreOverANewerHold() {
        var lease = DuckLease()
        let listen = lease.begin(device("speakers"))
        let barge = lease.begin(device("speakers"))
        #expect(lease.end(token: listen.token).isEmpty)
        #expect(lease.isHolding)
        #expect(lease.end(token: barge.token).map(\.volume) == [0.8])
    }

    @Test func aDeviceChangeMovesTheDuckAndRestoresTheOldOutput() {
        var lease = DuckLease()
        _ = lease.begin(device("speakers", volume: 0.8))
        let moved = lease.follow(device("headset", volume: 0.5))
        #expect(moved.contains(DuckVolumeCommand(device: "speakers", volume: 0.8)))
        let headset = AudioQuiet.duckTarget(snapshotVolume: 0.5, snapshotMuted: false)
        #expect(moved.contains(DuckVolumeCommand(device: "headset", volume: headset ?? -1)))
        #expect(lease.deviceID == "headset")
    }

    @Test func speechStopForAnOlderSessionDoesNotTouchTheCurrentOne() {
        #expect(SpeechSessionStop.affectsCurrent(stopSession: 4, current: 4))
        #expect(!SpeechSessionStop.affectsCurrent(stopSession: 4, current: 5))
    }

    @Test func anUnknownEndAndAnIdleLeaseStayEmpty() {
        var idle = DuckLease()
        #expect(idle.end(token: 1).isEmpty)
        #expect(idle.endAll().isEmpty)
        #expect(idle.follow(device("speakers")).isEmpty)
        #expect(idle.isHolding == false)

        var lease = DuckLease()
        let held = lease.begin(device("speakers", volume: 0.8))
        #expect(lease.end(token: held.token + 50).isEmpty)
        #expect(lease.isHolding)
        #expect(lease.deviceID == "speakers")
        #expect(lease.follow(device("speakers")).isEmpty)
        let restored = lease.end(token: held.token)
        #expect(restored == [DuckVolumeCommand(device: "speakers", volume: 0.8)])
    }

    @Test func aMutedOrSilentOutputBeginsWithNoVolumeCommand() {
        var muted = DuckLease()
        let muteBegin = muted.begin(device("speakers", volume: 0.8, muted: true))
        #expect(muteBegin.commands.isEmpty)
        #expect(muted.isHolding)
        #expect(muted.end(token: muteBegin.token).isEmpty)
        #expect(muted.isHolding == false)

        var silent = DuckLease()
        let silentBegin = silent.begin(device("speakers", volume: 0))
        #expect(silentBegin.commands.isEmpty)
        #expect(silent.isHolding)
        #expect(silent.endAll().isEmpty)
        #expect(silent.isHolding == false)
    }

    @Test func endingEveryHolderRestoresTheOutputOnce() {
        var lease = DuckLease()
        #expect(lease.endAll().isEmpty)
        let first = lease.begin(device("speakers", volume: 0.8))
        _ = lease.begin(device("speakers"))
        let restored = lease.endAll()
        #expect(restored == [DuckVolumeCommand(device: "speakers", volume: 0.8)])
        #expect(lease.isHolding == false)
        #expect(lease.end(token: first.token).isEmpty)
        #expect(lease.endAll().isEmpty)
    }
}
