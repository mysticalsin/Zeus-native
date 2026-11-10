import Foundation

/// The only list of `zeus debug` hooks.
///
/// `CommandCenter` and `ZeusCLI.usage` both render this. A second handwritten
/// sentence is what conflicted at devon/takeover b8a3b06: each lane edited the
/// same line, and both copies had already drifted from the switch
/// (`present-timeline` ran and was unnamed). Add a hook here and a matching
/// `case` in CommandCenter. Do not paste the names into another string.
public enum DebugSubcommandCatalog {
    public static let names: [String] = [
        "open-settings",
        "onboarding",
        "screenshot",
        "tab",
        "animate",
        "hud-state",
        "presence",
        "dictate-file",
        "wake-file",
        "brain-route",
        "second-brain-lookup",
        "present",
        "present-timeline",
        "update",
        "screen-share",
        "engine-logos",
        "import-assistant-key",
        "wake-false-triggers",
        "hands",
        "hands-live",
        "learn",
        "selection",
        "clean-room",
        "on-device-speech",
        "permissions",
        "record",
    ]

    public static var list: String { names.joined(separator: ", ") }

    public static func unknownMessage(_ subcommand: String) -> String {
        "Unknown debug subcommand: \(subcommand). Use \(list)."
    }
}
