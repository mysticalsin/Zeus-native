import CoreBluetooth
import Foundation
import ZeusCore

/// Reads Bluetooth authorization without asking. The manager, and the system prompt, exist only after `ask`.
enum BatteryBluetoothPrompt {
    static func current() -> BluetoothAccess {
        switch CBCentralManager.authorization {
        case .notDetermined: .notAsked
        case .allowedAlways: .allowed
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    static func ask(_ done: @escaping (BluetoothAccess) -> Void) {
        BatteryBluetoothAsker.shared.ask(done)
    }
}

private final class BatteryBluetoothAsker: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    static let shared = BatteryBluetoothAsker()
    private var manager: CBCentralManager?
    private var done: ((BluetoothAccess) -> Void)?

    func ask(_ done: @escaping (BluetoothAccess) -> Void) {
        let access = BatteryBluetoothPrompt.current()
        guard access == .notAsked else {
            done(access)
            return
        }
        self.done = done
        if manager == nil {
            manager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let access = BatteryBluetoothPrompt.current()
        guard access != .notAsked, let done else { return }
        self.done = nil
        done(access)
    }
}
