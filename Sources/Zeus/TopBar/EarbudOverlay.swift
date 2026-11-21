import Foundation
import SwiftUI
import ZeusCore
#if canImport(IOBluetooth)
import IOBluetooth
#endif

/// Connected audio devices from Bluetooth. The public device API exposes the connection and the
/// audio class. It does not expose a battery percentage, so those fields stay empty here.
enum EarbudBluetoothScan {
    static func reading() -> EarbudReading? {
        #if canImport(IOBluetooth)
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        for device in devices {
            guard device.isConnected() else { continue }
            // Audio/Video is major class 0x04. The public API exposes that class, not a battery percentage.
            guard Int(device.deviceClassMajor) == 0x04 else { continue }
            if let reading = EarbudOverlayRule.reading(name: device.name ?? "", audio: true, connected: true,
                                                       left: nil, right: nil, casePercent: nil) {
                return reading
            }
        }
        return nil
        #else
        return nil
        #endif
    }
}

/// Shows one reading inside the notch model, then clears it. Turning the setting off clears it at once.
@MainActor
final class EarbudOverlayController {
    private let model: TopBarModel
    private let scan: () -> EarbudReading?
    private var timer: Timer?

    init(model: TopBarModel, scan: @escaping () -> EarbudReading? = { EarbudBluetoothScan.reading() }) {
        self.model = model
        self.scan = scan
    }

    func setEnabled(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on, let reading = scan() else {
            model.earbud = nil
            model.earbudShownAt = nil
            return
        }
        model.earbud = reading
        model.earbudShownAt = Date()
        let timer = Timer(timeInterval: EarbudOverlayRule.visibleFor, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() { setEnabled(false) }

    private func clear() {
        timer = nil
        model.earbud = nil
        model.earbudShownAt = nil
    }
}

struct EarbudOverlayView: View {
    var reading: EarbudReading

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "headphones")
            Text(reading.name)
            if let left = reading.left { Text("L \(left)%") }
            if let right = reading.right { Text("R \(right)%") }
            if let casePercent = reading.casePercent { Text("Case \(casePercent)%") }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .allowsHitTesting(false)
    }

    private var label: String {
        var parts = [reading.name]
        if let left = reading.left { parts.append("left \(left) percent") }
        if let right = reading.right { parts.append("right \(right) percent") }
        if let casePercent = reading.casePercent { parts.append("case \(casePercent) percent") }
        return parts.joined(separator: ", ")
    }
}
