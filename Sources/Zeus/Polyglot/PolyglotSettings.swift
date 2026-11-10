import Foundation
import Observation
import ZeusCore

/// Settings > Polyglot, saved in UserDefaults.
@MainActor
@Observable
final class PolyglotSettings {
    static let shared = PolyglotSettings()

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Control + Option + T: no clash with Zeus's Option + Command talk chord.
    static let defaultHotkey = Shortcut(keyCode: 17, modifiers: [.control, .option])

    var enabled: Bool { didSet { defaults.set(enabled, forKey: "polyglot.enabled"); onEnabledChange?(enabled) } }
    var source: PolyglotSource { didSet { defaults.set(source.rawValue, forKey: "polyglot.source") } }
    var target: String {
        didSet { defaults.set(target, forKey: "polyglot.target"); onTargetChange?(target) }
    }
    var showOriginal: Bool { didSet { defaults.set(showOriginal, forKey: "polyglot.showOriginal") } }
    var captionSize: PolyglotCaptionSize { didSet { defaults.set(captionSize.rawValue, forKey: "polyglot.size") } }
    var hotkey: Shortcut? {
        didSet { defaults.set(Shortcut.stored(hotkey), forKey: "polyglot.hotkey") }
    }
    @ObservationIgnored var onTargetChange: ((String) -> Void)?
    /// Told when the on/off switch flips, so turning Polyglot off also stops a run and closes the pop-out.
    @ObservationIgnored var onEnabledChange: ((Bool) -> Void)?

    private init() {
        enabled = defaults.object(forKey: "polyglot.enabled") as? Bool ?? true
        source = defaults.string(forKey: "polyglot.source").flatMap(PolyglotSource.init(rawValue:)) ?? .microphone
        target = PolyglotLanguage.base(defaults.string(forKey: "polyglot.target") ?? "en")
        showOriginal = defaults.object(forKey: "polyglot.showOriginal") as? Bool ?? true
        captionSize = defaults.string(forKey: "polyglot.size").flatMap(PolyglotCaptionSize.init(rawValue:)) ?? .medium
        if let text = defaults.string(forKey: "polyglot.hotkey") {
            hotkey = text == "off" ? nil : (Shortcut.parse(text) ?? Self.defaultHotkey)
        } else {
            hotkey = Self.defaultHotkey
        }
    }

    /// Polyglot.app (Tony's Python-engine app), when it is installed: Settings offers to open it.
    static var installedAppURL: URL? {
        for path in ["/Applications/Polyglot.app", NSHomeDirectory() + "/Applications/Polyglot.app"]
        where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
