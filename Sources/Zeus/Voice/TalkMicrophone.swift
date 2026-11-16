import Foundation
import ZeusCore

/// Which microphone talk turns listen on. Its own setting: Dictation keeps its own choice (`DictationSettings.microphoneUID`).
/// Stored under the catalog row `talk.microphone` as the text below, so a settings export carries Automatic and This Mac's
/// microphone, and never a device id from another Mac.
enum TalkMicrophoneChoice: Equatable {
    /// The system input, where a connected headset wins. The default.
    case automatic
    /// The Mac's own microphone, so a Bluetooth headset never switches profile for a talk turn.
    case builtIn
    /// One connected input, by UID.
    case device(String)

    static let settingID = "talk.microphone"
    static let defaultsKey = "opt." + settingID
    static let automaticTitle = "Automatic"
    static let builtInTitle = "This Mac\u{2019}s microphone"
    static let unavailableTitle = "Unavailable microphone"
    private static let devicePrefix = "device:"

    init(stored: String?) {
        switch stored {
        case Self.builtInTitle: self = .builtIn
        case let text? where text.hasPrefix(Self.devicePrefix) && text.count > Self.devicePrefix.count:
            self = .device(String(text.dropFirst(Self.devicePrefix.count)))
        default: self = .automatic
        }
    }

    var stored: String {
        switch self {
        case .automatic: Self.automaticTitle
        case .builtIn: Self.builtInTitle
        case .device(let uid): Self.devicePrefix + uid
        }
    }

    static func load(_ defaults: UserDefaults = .standard) -> TalkMicrophoneChoice {
        TalkMicrophoneChoice(stored: defaults.string(forKey: defaultsKey))
    }

    /// The device UID the turn starts with, or nil for the system input. Built-in is the built-in device found now, a specific
    /// device is itself while it is connected. Anything that cannot be found is Automatic, never an error.
    func resolvedUID(devices: [MicrophoneDevice], builtInUID: String?) -> String? {
        switch self {
        case .automatic: return nil
        case .builtIn: return builtInUID.flatMap { uid in devices.contains { $0.uid == uid } ? uid : nil }
        case .device(let uid): return devices.contains { $0.uid == uid } ? uid : nil
        }
    }

    /// One label per device, in device order, like the Dictation page: two microphones with one name stay apart.
    static func labels(for devices: [MicrophoneDevice]) -> [String] {
        devices.enumerated().map { index, device in
            devices.filter { $0.name == device.name }.count > 1 ? "\(device.name) (\(index + 1))" : device.name
        }
    }

    /// The pop-up entries: Automatic, this Mac's microphone, every connected input, and a stand-in for a chosen one that is gone.
    func options(devices: [MicrophoneDevice]) -> [String] {
        var options = [Self.automaticTitle, Self.builtInTitle] + Self.labels(for: devices)
        if case .device(let uid) = self, !devices.contains(where: { $0.uid == uid }) { options.append(Self.unavailableTitle) }
        return options
    }

    func title(devices: [MicrophoneDevice]) -> String {
        switch self {
        case .automatic: return Self.automaticTitle
        case .builtIn: return Self.builtInTitle
        case .device(let uid):
            guard let index = devices.firstIndex(where: { $0.uid == uid }) else { return Self.unavailableTitle }
            return Self.labels(for: devices)[index]
        }
    }

    /// The choice a pop-up entry stands for; nil for the stand-in, which is not a choice to make.
    static func choice(forTitle title: String, devices: [MicrophoneDevice]) -> TalkMicrophoneChoice? {
        if title == automaticTitle { return .automatic }
        if title == builtInTitle { return .builtIn }
        guard let index = labels(for: devices).firstIndex(of: title) else { return nil }
        return .device(devices[index].uid)
    }
}
