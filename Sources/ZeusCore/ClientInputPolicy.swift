import Foundation

/// Fields of a hook event come from whatever process wrote to the socket. These checks decide
/// what the app may believe or act on. Nothing here chooses a command or a path to run: the app
/// only displays hook text and, for "jump to terminal", activates an app by bundle ID.
public enum HookClientInput {
    /// A well-formed reverse-DNS bundle ID: letters, digits, dot, hyphen, 3 to 155 characters,
    /// at least one dot. Anything else is dropped.
    public static func wellFormedBundleID(_ value: String?) -> String? {
        guard let value, (3...155).contains(value.utf8.count), value.contains(".") else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard value.unicodeScalars.allSatisfy(allowed.contains), !value.hasPrefix("."), !value.hasSuffix(".") else { return nil }
        return value
    }

    /// Apps Zeus may LAUNCH when a card asks to jump to a terminal that is not running. A running app
    /// may be brought forward whatever its ID; launching needs the ID to be a known terminal or editor.
    public static let launchableTerminalBundles: Set<String> = {
        var ids = Set(TerminalInfo.programBundles.values)
        ids.insert("com.todesktop.230313mzl4w4u92") // Cursor
        ids.insert("com.microsoft.VSCodeInsiders")
        ids.insert("com.vscodium")
        ids.insert("com.apple.Terminal")
        return ids
    }()

    public static func mayLaunch(bundleID: String) -> Bool { launchableTerminalBundles.contains(bundleID) }

    /// The risk used for decisions: never lower than what the app computes from the tool and its
    /// input itself, whatever the client claimed.
    public static func effectiveRisk(claimed: HookEvent.Risk?, tool: String?, input: JSONValue?) -> HookEvent.Risk {
        let own = CommandRisk.assess(tool: tool, input: input)
        // No claim means medium, as the approval card always assumed.
        let claim = claimed ?? .medium
        return rank(claim) >= rank(own) ? claim : own
    }

    private static func rank(_ risk: HookEvent.Risk) -> Int {
        switch risk {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
}
