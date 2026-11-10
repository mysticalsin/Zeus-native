import Foundation

/// The one admin rule lid-closed mode needs, and the scripts that install and remove it.
/// The sudoers and backstop ideas come from Insomnia (MIT); the text and scripts are ours.
public enum InsomniaSudoers {
    public static let path = "/etc/sudoers.d/zeus-insomnia"

    /// Exactly these four command lines, nothing else, no wildcards.
    public static let commands = [
        "/usr/bin/pmset -a disablesleep 1",
        "/usr/bin/pmset -a disablesleep 0",
        "/usr/bin/pmset -a lowpowermode 1",
        "/usr/bin/pmset -a lowpowermode 0",
    ]

    public enum RuleError: Error, Equatable {
        /// Not a plain macOS short name, so it is never written into sudoers.
        case invalidUser(String)
    }

    /// macOS short names: letters, digits, `_`, `.` and `-`, not starting with `-` or `.`.
    public static func isValidUser(_ user: String) -> Bool {
        guard let first = user.unicodeScalars.first, user.count <= 64, user != "root", user != "ALL" else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard user.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        return CharacterSet.letters.contains(first) || first == "_"
    }

    /// The file's text, for this user only. Ends with a newline, as sudoers requires.
    public static func rule(user: String) throws -> String {
        guard isValidUser(user) else { throw RuleError.invalidUser(user) }
        return """
        # Zeus lid-closed mode (Insomnia). Lets \(user) run these four pmset commands without a password.
        # Remove it in Zeus > Settings > Insomnia, or: sudo rm \(path)
        \(user) ALL=(root) NOPASSWD: \(commands.joined(separator: ", "))

        """
    }
}

/// The backstop LaunchAgent: `zeus insomnia-guard` every 60 s.
public enum InsomniaBackstop {
    public static let label = "com.zeus.insomnia.backstop"
    public static let interval = 60

    public static func plistURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// The agent's property list. Output goes to a log in Zeus's support folder.
    public static func plist(cliPath: String, logPath: String) throws -> Data {
        let dictionary: [String: Any] = [
            "Label": label,
            "ProgramArguments": [cliPath, "insomnia-guard"],
            "StartInterval": interval,
            "RunAtLoad": true,
            "ProcessType": "Background",
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
}

/// The single `do shell script … with administrator privileges` that installs or removes the rule.
/// macOS shows its own password prompt; Zeus never sees the password.
public enum InsomniaAdminScript {
    /// `'it'\''s'`: one shell word, whatever is inside.
    public static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// An AppleScript string literal's inside: backslashes and double quotes escaped.
    public static func appleScriptEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Validate with visudo, install root:wheel 0440, then (re)load the backstop agent.
    public static func install(ruleFile: String, plist: String, uid: UInt32) -> String {
        let rule = shellQuote(ruleFile), target = shellQuote(InsomniaSudoers.path), agent = shellQuote(plist)
        return [
            "\(InsomniaCommand.visudo) -cf \(rule)",
            "/usr/bin/install -m 0440 -o root -g wheel \(rule) \(target)",
            "\(InsomniaCommand.visudo) -cf \(target)",
            "(\(InsomniaCommand.launchctl) bootout gui/\(uid)/\(InsomniaBackstop.label) 2>/dev/null || true)",
            "\(InsomniaCommand.launchctl) bootstrap gui/\(uid) \(agent)",
        ].joined(separator: " && ")
    }

    /// Unload the agent, remove its plist and the rule. Each step runs even if one before failed.
    public static func uninstall(plist: String, uid: UInt32) -> String {
        [
            "\(InsomniaCommand.launchctl) bootout gui/\(uid)/\(InsomniaBackstop.label) 2>/dev/null",
            "/bin/rm -f \(shellQuote(plist))",
            "/bin/rm -f \(shellQuote(InsomniaSudoers.path))",
        ].joined(separator: "; ")
    }

    /// The osascript arguments for one admin prompt.
    public static func osascriptArguments(_ script: String, prompt: String) -> [String] {
        ["-e", "do shell script \"\(appleScriptEscape(script))\" with prompt \"\(appleScriptEscape(prompt))\" with administrator privileges"]
    }
}
