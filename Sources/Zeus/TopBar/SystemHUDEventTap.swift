import AppKit
import CoreAudio
import ZeusCore

/// Consumes media-key events when Accessibility is on so the macOS HUD can stay hidden while Zeus applies the change.
final class SystemHUDEventTap: @unchecked Sendable {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let volumeDevice: () -> AudioObjectID
    private let currentVolume: () -> Float32?
    private var onChange: () -> Void

    init(volumeDevice: @escaping () -> AudioObjectID, currentVolume: @escaping () -> Float32?, onChange: @escaping () -> Void) {
        self.volumeDevice = volumeDevice
        self.currentVolume = currentVolume
        self.onChange = onChange
    }

    func update(enabled: Bool) {
        stop()
        guard enabled else { return }
        let systemDefined = CGEventType(rawValue: 14)!
        let mask = CGEventMask(1 << systemDefined.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: Self.callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard type.rawValue == 14, let refcon else { return nil }
        let monitor = Unmanaged<SystemHUDEventTap>.fromOpaque(refcon).takeUnretainedValue()
        return monitor.handle(event)
    }

    private func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
        let data = ns.data1
        let key = (data & 0xFFFF0000) >> 16
        let down = ((data & 0xFF00) >> 8) == 0xA
        guard down else { return Unmanaged.passUnretained(event) }
        let flags = ns.modifierFlags
        let fine = flags.contains(.shift) && flags.contains(.option)
        switch SystemHUDKeys.action(for: Int(key), fine: fine) {
        case .volumeUp(let fine):
            if let vol = currentVolume() { SystemVolumeControl.step(device: volumeDevice(), direction: 1, fine: fine, current: vol) }
            onChange()
            return nil
        case .volumeDown(let fine):
            if let vol = currentVolume() { SystemVolumeControl.step(device: volumeDevice(), direction: -1, fine: fine, current: vol) }
            onChange()
            return nil
        case .toggleMute: // H4: actually toggle it, not just note the change
            SystemVolumeControl.toggleMute(device: volumeDevice())
            onChange()
            return nil
        case .brightnessUp(let fine): // H5: was backwards (key 2 is up)
            DisplayBrightness.step(direction: 1, fine: fine)
            onChange()
            return nil
        case .brightnessDown(let fine):
            DisplayBrightness.step(direction: -1, fine: fine)
            onChange()
            return nil
        case .illuminationUp(let fine): // H6: real NX_KEYTYPE_ILLUMINATION_UP is 21, not 4
            KeyboardBacklight.step(direction: 1, fine: fine)
            onChange()
            return nil
        case .illuminationDown(let fine): // H6: real NX_KEYTYPE_ILLUMINATION_DOWN is 22, not 5
            KeyboardBacklight.step(direction: -1, fine: fine)
            onChange()
            return nil
        case .illuminationToggle:
            KeyboardBacklight.toggle()
            onChange()
            return nil
        case .passThrough:
            // H6: keys 4 (Caps Lock) and 5 (Help) land here now, unconsumed, instead of being
            // eaten as "keyboard illumination".
            return Unmanaged.passUnretained(event)
        }
    }
}
