import AppKit
import AudioToolbox
import CoreAudio
import ZeusCore

enum DisplayBrightness {
    private typealias Getter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (UInt32, Float) -> Int32

    private nonisolated(unsafe) static let getter: Getter? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: Getter.self)
    }()

    private nonisolated(unsafe) static let setter: Setter? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: Setter.self)
    }()

    static func main() -> Double? {
        guard let getter else { return nil }
        var value: Float = 0
        guard getter(CGMainDisplayID(), &value) == 0 else { return nil }
        return Double(value)
    }

    static func set(_ value: Double) {
        guard let setter else { return }
        _ = setter(CGMainDisplayID(), Float(max(0, min(1, value))))
    }

    static func step(direction: Int, fine: Bool) {
        guard let current = main() else { return }
        DisplayBrightness.set(SystemHUDMath.steppedValue(current, direction: direction, fine: fine))
    }
}

enum KeyboardBacklight {
    private typealias Getter = @convention(c) (UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (Float, Int32, Int32, Int32, Int32) -> Int32

    private nonisolated(unsafe) static let client: UnsafeMutableRawPointer? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY),
              let symbol = dlsym(handle, "KeyboardBrightnessClientCreate") else { return nil }
        let create = unsafeBitCast(symbol, to: (@convention(c) () -> UnsafeMutableRawPointer?).self)
        return create()
    }()

    private nonisolated(unsafe) static let getter: Getter? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY),
              let symbol = dlsym(handle, "KeyboardBrightnessClientGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: Getter.self)
    }()

    private nonisolated(unsafe) static let setter: Setter? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY),
              let symbol = dlsym(handle, "KeyboardBrightnessClientSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: Setter.self)
    }()

    static func level() -> Double? {
        guard client != nil, let getter else { return nil }
        var value: Float = 0
        guard getter(&value) == 0 else { return nil }
        return Double(value)
    }

    static func set(_ value: Double) {
        guard let client, let setter else { return }
        _ = setter(Float(max(0, min(1, value))), 0, 0, 0, 0)
        _ = client
    }

    static func step(direction: Int, fine: Bool) {
        guard let current = level() else { return }
        set(SystemHUDMath.steppedValue(current, direction: direction, fine: fine))
    }

    /// NX_KEYTYPE_ILLUMINATION_TOGGLE (H6): toggles between off and the last non-zero level.
    private nonisolated(unsafe) static var lastNonZero: Double = 0.5
    static func toggle() {
        guard let current = level() else { return }
        if current > 0.001 {
            lastNonZero = current
            set(0)
        } else {
            set(lastNonZero)
        }
    }
}

enum SystemVolumeControl {
    static func setScalar(_ value: Float, device: AudioObjectID) {
        var volume = max(0, min(1, value))
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        let size = UInt32(MemoryLayout<Float32>.size)
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)
    }

    static func step(device: AudioObjectID, direction: Int, fine: Bool, current: Float) {
        let next = Float(SystemHUDMath.steppedValue(Double(current), direction: direction, fine: fine))
        setScalar(next, device: device)
    }

    static func isMuted(device: AudioObjectID) -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return false }
        return muted != 0
    }

    /// H4: the mute media key only called `onChange()` before, never actually muting anything.
    static func toggleMute(device: AudioObjectID) {
        var muted: UInt32 = isMuted(device: device) ? 0 : 1
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        let size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &muted)
    }
}
