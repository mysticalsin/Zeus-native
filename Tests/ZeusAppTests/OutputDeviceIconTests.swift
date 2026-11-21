import CoreAudio
import Testing
import ZeusCore
@testable import Zeus

@Suite("Output device icons")
struct OutputDeviceIconTests {
    @Test func theMenuRowsUseTheTransportTheDeviceReports() {
        let devices = [
            OutputDevices.Device(id: 1, name: "Built-in", isDefault: true, transport: 0x626C746E),
            OutputDevices.Device(id: 2, name: "Headset", isDefault: false, transport: 0x626C7565),
            OutputDevices.Device(id: 3, name: "Room", isDefault: false, transport: 0x61697270),
        ]
        let rows = OutputDeviceMenuRows.make(devices)
        #expect(rows.map(\.symbol) == ["speaker.wave.2.fill", "headphones", "airplayaudio"])
        #expect(rows.map(\.name) == ["Built-in", "Headset", "Room"])
        #expect(rows[0].isDefault)
    }
}
