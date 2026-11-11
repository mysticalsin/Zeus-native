import Foundation

/// The Settings switches for the features that run in ZeusCore, read where they act. Settings
/// stores a catalog row `x.y` under the key `opt.x.y`, so this reads the same place. Every default
/// here equals the catalog's default (`scripts/gen-settings-catalog.py`).
public enum FeatureSettings {
    public static func key(_ id: String) -> String { "opt." + id }

    public static func string(_ id: String, default value: String, defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: key(id)) ?? value
    }

    public static func bool(_ id: String, default value: Bool, defaults: UserDefaults = .standard) -> Bool {
        guard let text = defaults.string(forKey: key(id)) else { return value }
        return text == "true"
    }

    // MARK: Fast path

    /// Instant commands: local rules, then Jev. Off sends every command to the LLM.
    public static func fastPathEnabled(defaults: UserDefaults = .standard) -> Bool { bool("fastPath.enabled", default: true, defaults: defaults) }

    // MARK: Desktop pointing

    /// The pointing keys the owner picked, Control and Option on a fresh install (`docs/FIRST-RUN-DEFAULTS.md`).
    public static let pointingShortcutDefault = "Control-Option"

    /// Desktop pointing is on from the first launch. Turning it on only installs the key listener the owner's own
    /// Input Monitoring or Accessibility grant allows; no capture happens until the keys are held.
    public static func pointingEnabled(defaults: UserDefaults = .standard) -> Bool { bool("pointing.enabled", default: true, defaults: defaults) }

    /// While the keys are held, drags are ink Zeus can see. Off leaves the pointer and clicks to the apps.
    public static func pointingDrawWhileHeld(defaults: UserDefaults = .standard) -> Bool { bool("pointing.drawWhileHeld", default: true, defaults: defaults) }

    /// A screenshot goes to the provider only with this separate consent, never by default.
    public static func pointingSendScreenshot(defaults: UserDefaults = .standard) -> Bool { bool("pointing.sendScreenshot", default: false, defaults: defaults) }

    public static func pointingShortcutName(defaults: UserDefaults = .standard) -> String { string("pointing.shortcut", default: pointingShortcutDefault, defaults: defaults) }

    // MARK: Browser agent

    public static let browserStepChoices = [10, 15, 25, 40, 60]

    public static func browserAgentEnabled(defaults: UserDefaults = .standard) -> Bool { bool("browserAgent.enabled", default: true, defaults: defaults) }

    /// How many steps one web task may take, 5 to 100.
    public static func browserAgentMaxSteps(defaults: UserDefaults = .standard) -> Int {
        min(max(Int(string("browserAgent.maxSteps", default: "25", defaults: defaults)) ?? 25, 5), 100)
    }

    /// Extra words that always send a click to the approval card, on top of the built-in list.
    public static func browserAgentAlwaysAsk(defaults: UserDefaults = .standard) -> [String] {
        words(string("browserAgent.alwaysAsk", default: "", defaults: defaults))
    }

    /// Which browser the agent drives: Tony's own Chrome (default) or the separate browser-use one.
    public static let browserBackendChoices = ["Your Chrome", "Separate browser (browser-use)"]

    public static func browserAgentBackend(defaults: UserDefaults = .standard) -> BrowserAgentBackendKind {
        BrowserAgentBackendKind.resolve(setting: string("browserAgent.backend", default: browserBackendChoices[0], defaults: defaults))
    }

    /// Sites the separate browser may open (comma separated). Empty means no limit.
    public static func browserAgentAllowedDomains(defaults: UserDefaults = .standard) -> [String] {
        BrowserUseAllowlist.parse(string("browserAgent.allowedDomains", default: "", defaults: defaults))
    }

    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    // MARK: Research

    public static let researchDepthChoices = ["Quick", "Deep"]

    /// The depth research takes when you don't say "deep research".
    public static func researchDepth(defaults: UserDefaults = .standard) -> ResearchDepth {
        string("research.depth", default: "Quick", defaults: defaults) == "Deep" ? .deep : .quick
    }

    /// Where reports are saved, or nil for the default (the second brain's ZEUS/Research, else Documents/Zeus Research).
    public static func researchFolder(defaults: UserDefaults = .standard) -> URL? {
        let path = string("research.folder", default: "", defaults: defaults).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}
