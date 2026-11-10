import Foundation
import IOKit.ps
import Observation
import ZeusCore

/// Battery and heat for keep-awake rules. Event-driven: IOKit tells us when a power source
/// changes and ProcessInfo when the thermal state does, so nothing polls.
@MainActor @Observable
final class PowerMonitor {
    static let shared = PowerMonitor()

    private(set) var power = KeepAwakeRules.Power()
    /// Called after every change, on the main thread.
    @ObservationIgnored var onChange: () -> Void = {}

    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var thermalObserver: NSObjectProtocol?

    var isRunning: Bool { source != nil || thermalObserver != nil }

    func start() {
        guard !isRunning else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let made = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            // Added to the main run loop below, so this runs on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
            }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), made, .defaultMode)
            source = made
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Last, so a listener that stops us from inside onChange leaves nothing registered.
        refresh()
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        thermalObserver = nil
    }

    func refresh() {
        var next = Self.battery()
        next.thermal = Self.thermal(ProcessInfo.processInfo.thermalState)
        guard next != power else { return }
        power = next
        onChange()
    }

    /// The internal battery, if there is one. A desktop Mac reads as on AC with no percent.
    private static func battery() -> KeepAwakeRules.Power {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return .init() }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return .init(batteryPercent: current * 100 / max,
                         isCharging: info[kIOPSIsChargingKey] as? Bool ?? false,
                         onBattery: (info[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue)
        }
        return .init()
    }

    private static func thermal(_ state: ProcessInfo.ThermalState) -> KeepAwakeRules.Thermal {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }
}
