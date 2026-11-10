import Foundation

/// How careful Zeus must be before it runs a shell command for Tony (`terminal.run`).
/// Nothing that deletes, overwrites, installs, uses the network, escalates, or that Zeus does not
/// recognise runs without Tony's yes on a notch card. Only plainly read-only and local build
/// commands (ls, cat, git status, swift build, ...) go straight to the terminal, and even those
/// run in a terminal window Tony can see.
public enum ShellRisk: Int, Comparable, Sendable {
    case safe, unfamiliar, network, destructive

    public static func < (a: ShellRisk, b: ShellRisk) -> Bool { a.rawValue < b.rawValue }
}

public struct ShellAssessment: Equatable, Sendable {
    public let risk: ShellRisk
    /// Plain reasons for the approval card ("deletes files (rm)").
    public let reasons: [String]

    public var needsApproval: Bool { risk != .safe }

    /// The notch card's risk badge.
    public var cardRisk: HookEvent.Risk {
        switch risk {
        case .safe: .low
        case .unfamiliar, .network: .medium
        case .destructive: .high
        }
    }

    public var summary: String { reasons.isEmpty ? "read-only" : reasons.joined(separator: "; ") }
}

public enum ShellRiskClassifier {
    public static func assess(_ command: String) -> ShellAssessment {
        let parsed = parse(command)
        var risk = ShellRisk.safe
        var reasons: [String] = []
        func raise(_ level: ShellRisk, _ reason: String) {
            risk = max(risk, level)
            if !reasons.contains(reason) { reasons.append(reason) }
        }

        if parsed.segments.isEmpty && parsed.redirects.isEmpty { raise(.unfamiliar, "an empty command") }
        if parsed.substitution { raise(.unfamiliar, "runs commands inside the command") }
        for redirect in parsed.redirects where redirect.target != "/dev/null" && !redirect.target.hasPrefix("&") {
            raise(redirect.append ? .unfamiliar : .destructive, redirect.append ? "appends to a file" : "overwrites a file")
        }

        var previousWasNetwork = false
        for segment in parsed.segments {
            let verdict = classify(segment.words)
            if verdict.risk > .safe { raise(verdict.risk, verdict.reason) }
            // "curl ... | sh": whatever the internet sends runs.
            if segment.afterPipe, previousWasNetwork, let name = commandName(segment.words), shells.contains(name) {
                raise(.destructive, "runs a download as a program")
            }
            previousWasNetwork = verdict.risk == .network || (segment.afterPipe && previousWasNetwork && verdict.risk == .safe)
        }
        return ShellAssessment(risk: risk, reasons: reasons)
    }

    // MARK: Classifying one command

    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "python", "python3", "ruby", "perl", "node", "osascript"]

    private static let wrappers: Set<String> = ["env", "nohup", "time", "nice", "command", "exec", "caffeinate", "builtin"]

    private static let alwaysDestructive: [String: String] = [
        "rm": "deletes files", "rmdir": "deletes folders", "unlink": "deletes files", "mv": "moves or overwrites files",
        "dd": "writes raw data", "mkfs": "formats a disk", "shred": "destroys files", "truncate": "empties files",
        "chmod": "changes permissions", "chown": "changes owners", "chgrp": "changes owners",
        "kill": "stops processes", "killall": "stops processes", "pkill": "stops processes",
        "shutdown": "shuts down the Mac", "reboot": "restarts the Mac", "halt": "shuts down the Mac",
        "launchctl": "changes background services", "diskutil": "changes disks", "hdiutil": "changes disk images",
        "crontab": "changes scheduled jobs", "tmutil": "changes Time Machine", "csrutil": "changes system protection",
        "spctl": "changes system security", "networksetup": "changes network settings", "pmset": "changes power settings",
        "scutil": "changes system settings", "dscl": "changes accounts", "security": "touches the keychain",
        "su": "switches user", "sudo": "runs as administrator", "doas": "runs as administrator",
        "eval": "runs text as a command", "mkswap": "formats a disk", "srm": "destroys files",
    ]

    private static let network: [String: String] = [
        "curl": "uses the network", "wget": "uses the network", "ssh": "connects to another computer", "scp": "copies over the network",
        "sftp": "copies over the network", "rsync": "may copy over the network", "nc": "uses the network", "ncat": "uses the network",
        "netcat": "uses the network", "telnet": "uses the network", "ftp": "uses the network", "ping": "uses the network",
        "traceroute": "uses the network", "nslookup": "uses the network", "dig": "uses the network", "mosh": "connects to another computer",
        "gh": "uses GitHub", "kubectl": "talks to a cluster", "aws": "talks to a cloud", "gcloud": "talks to a cloud", "az": "talks to a cloud",
        "terraform": "changes infrastructure", "vercel": "deploys", "netlify": "deploys", "fly": "deploys", "flyctl": "deploys",
        "heroku": "talks to a cloud", "firebase": "talks to a cloud", "npx": "downloads and runs a package", "bunx": "downloads and runs a package",
        "pnpx": "downloads and runs a package", "uvx": "downloads and runs a package", "pipx": "downloads and runs a package",
    ]

    private static let safe: Set<String> = [
        "ls", "ll", "la", "pwd", "cd", "echo", "printf", "cat", "head", "tail", "less", "more", "wc", "grep", "egrep", "fgrep", "rg", "fd",
        "tree", "du", "df", "which", "whereis", "type", "file", "stat", "date", "cal", "uname", "whoami", "id", "printenv", "ps", "uptime",
        "sw_vers", "sort", "uniq", "cut", "tr", "diff", "cmp", "basename", "dirname", "realpath", "readlink", "true", "false", "test", "[",
        "mkdir", "touch", "clear", "history", "jq", "xxd", "hexdump", "md5", "shasum", "sha256sum", "man", "say", "pbcopy", "pbpaste",
        "ifconfig", "lsof", "netstat", "code", "cursor", "xcodebuild", "xcrun", "tput", "hostname", "nproc", "sysctl", "locale", "open",
        "swiftc", "swiftformat", "swiftlint", "tsc", "eslint", "prettier", "pytest", "ruff", "black", "mypy", "rustfmt",
    ]

    private static func commandName(_ words: [String]) -> String? {
        var index = 0
        while index < words.count {
            let word = words[index]
            if isAssignment(word) || wrappers.contains(URL(fileURLWithPath: word).lastPathComponent) {
                index += 1
                continue
            }
            return URL(fileURLWithPath: word).lastPathComponent.lowercased()
        }
        return nil
    }

    private static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        return word[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static func classify(_ words: [String]) -> (risk: ShellRisk, reason: String) {
        var words = words[...]
        var elevated = false
        while let first = words.first {
            let name = URL(fileURLWithPath: first).lastPathComponent
            if isAssignment(first) { words = words.dropFirst(); continue }
            if wrappers.contains(name) {
                words = words.dropFirst()
                // env/nice/time options and their values: skip dashed words.
                while let next = words.first, next.hasPrefix("-") || isAssignment(next) { words = words.dropFirst() }
                continue
            }
            if name == "xargs" {
                words = words.dropFirst()
                while let next = words.first, next.hasPrefix("-") { words = words.dropFirst() }
                let inner = classify(Array(words))
                return (max(inner.risk, .unfamiliar), inner.risk > .unfamiliar ? inner.reason : "runs commands from input")
            }
            if name == "sudo" || name == "doas" { elevated = true; words = words.dropFirst(); continue }
            break
        }
        guard let first = words.first else {
            return elevated ? (.destructive, "runs as administrator") : (.safe, "")
        }
        let name = URL(fileURLWithPath: first).lastPathComponent.lowercased()
        let arguments = Array(words.dropFirst())
        var result = classifyNamed(name, arguments)
        if elevated { result = (.destructive, "runs as administrator (" + name + ")") }
        return result
    }

    private static func classifyNamed(_ name: String, _ arguments: [String]) -> (risk: ShellRisk, reason: String) {
        if let reason = alwaysDestructive[name] { return (.destructive, "\(reason) (\(name))") }
        if let reason = network[name] { return (.network, "\(reason) (\(name))") }
        let positional = arguments.filter { !$0.hasPrefix("-") }
        let sub = positional.first?.lowercased() ?? ""
        func has(_ flags: [String]) -> Bool { arguments.contains { flags.contains($0) } }

        switch name {
        case "git": return git(arguments)
        case "npm", "pnpm", "yarn", "bun", "deno":
            switch sub {
            case "test", "t", "build", "lint", "ls", "list", "outdated", "view", "why", "version", "-v", "": return (.safe, "")
            case "install", "i", "add", "ci", "update", "upgrade", "up", "create", "init", "dlx", "exec", "link", "fetch":
                return (.network, "installs packages (\(name))")
            case "uninstall", "remove", "rm", "unlink", "prune": return (.destructive, "removes packages (\(name))")
            case "publish", "deprecate", "unpublish": return (.destructive, "publishes or retracts a package (\(name))")
            default: return (.unfamiliar, "runs a project script (\(name))")
            }
        case "pip", "pip3", "uv", "poetry", "conda":
            switch sub {
            case "list", "show", "freeze", "check", "": return (.safe, "")
            case "uninstall", "remove": return (.destructive, "removes packages (\(name))")
            default: return (.network, "installs packages (\(name))")
            }
        case "brew":
            switch sub {
            case "list", "info", "search", "doctor", "--prefix", "--version", "outdated", "deps", "leaves", "": return (.safe, "")
            case "uninstall", "remove", "rm", "cleanup", "autoremove", "untap", "reinstall": return (.destructive, "removes software (brew)")
            default: return (.network, "installs software (brew)")
            }
        case "cargo":
            switch sub {
            case "build", "test", "check", "fmt", "clippy", "doc", "tree", "metadata", "bench", "run", "": return (sub == "run" ? .unfamiliar : .safe, sub == "run" ? "runs a program (cargo run)" : "")
            case "clean", "uninstall": return (.destructive, "deletes build output or tools (cargo)")
            case "publish", "yank": return (.destructive, "publishes or retracts a crate (cargo)")
            default: return (.network, "installs or fetches crates (cargo)")
            }
        case "swift":
            switch sub {
            case "build", "test", "--version", "-version", "format", "": return (.safe, "")
            case "package":
                let second = positional.dropFirst().first ?? ""
                if ["resolve", "update", "fetch"].contains(second) { return (.network, "fetches packages (swift package)") }
                if ["clean", "reset"].contains(second) { return (.destructive, "deletes build output (swift package)") }
                return (.safe, "")
            default: return (.unfamiliar, "runs a program (swift \(sub))")
            }
        case "go":
            switch sub {
            case "build", "test", "vet", "fmt", "version", "list", "env", "": return (.safe, "")
            case "get", "install", "mod": return (.network, "fetches modules (go)")
            case "clean": return (.destructive, "deletes build output (go)")
            default: return (.unfamiliar, "runs a program (go \(sub))")
            }
        case "docker", "podman":
            switch sub {
            case "ps", "images", "logs", "inspect", "version", "info", "stats", "top", "": return (.safe, "")
            case "rm", "rmi", "prune", "kill", "stop", "system", "volume", "network": return (.destructive, "removes containers or images (\(name))")
            default: return (.network, "runs or pulls containers (\(name))")
            }
        case "find":
            if has(["-delete"]) { return (.destructive, "deletes files (find -delete)") }
            if has(["-exec", "-execdir", "-ok", "-okdir"]) { return (.unfamiliar, "runs a command on each match (find -exec)") }
            return (.safe, "")
        case "sed":
            // -i, -i.bak, -ni, -Ei and --in-place all edit the file itself.
            let inPlace = arguments.contains { argument in
                if argument.hasPrefix("--") { return argument.hasPrefix("--in-place") }
                return argument.hasPrefix("-i") || (argument.hasPrefix("-") && argument.count <= 4 && argument.dropFirst().contains("i"))
            }
            return inPlace ? (.destructive, "edits files in place (sed -i)") : (.safe, "")
        case "defaults":
            return ["read", "read-type", "domains", "find"].contains(sub) ? (.safe, "") : (.destructive, "changes app settings (defaults)")
        case "open":
            let remote = arguments.contains { $0.contains("://") }
            return remote ? (.network, "opens a web address (open)") : (.safe, "")
        case "cp", "ln", "rename", "install":
            return (.unfamiliar, "copies or links files (\(name))")
        case "make", "just", "task", "rake", "gradle", "gradlew", "mvn", "ant", "cmake", "ninja", "bazel":
            return (.unfamiliar, "runs build targets (\(name))")
        case "python", "python3", "ruby", "perl", "node", "php", "lua", "osascript", "awk", "gawk", "bash", "sh", "zsh", "fish", "source", ".":
            return (.unfamiliar, "runs a program or script (\(name))")
        default:
            if safe.contains(name) { return (.safe, "") }
            return (.unfamiliar, "isn't a command Zeus knows (\(name))")
        }
    }

    private static func git(_ arguments: [String]) -> (risk: ShellRisk, reason: String) {
        // Skip global options: -C <dir>, -c k=v, --git-dir=…, --no-pager.
        var rest = arguments[...]
        while let first = rest.first, first.hasPrefix("-") {
            rest = rest.dropFirst()
            if ["-C", "-c", "--git-dir", "--work-tree", "--namespace"].contains(first) { rest = rest.dropFirst() }
        }
        guard let sub = rest.first?.lowercased() else { return (.safe, "") }
        let flags = rest.dropFirst().filter { $0.hasPrefix("-") }
        switch sub {
        case "status", "log", "diff", "show", "blame", "rev-parse", "describe", "ls-files", "ls-tree", "shortlog", "grep", "reflog",
             "remote", "config", "add", "commit", "init", "switch", "stash", "branch", "tag", "worktree", "merge", "cherry-pick",
             "apply", "mv", "bisect", "show-ref", "cat-file", "for-each-ref", "name-rev", "stage", "notes", "version":
            if sub == "stash", rest.dropFirst().first.map({ ["drop", "clear"].contains($0) }) == true { return (.destructive, "drops stashed work (git stash)") }
            if sub == "branch", flags.contains(where: { ["-d", "-D", "--delete", "-M", "-m"].contains($0) }) {
                return (.destructive, "deletes or renames a branch (git branch)")
            }
            if sub == "tag", flags.contains(where: { ["-d", "--delete"].contains($0) }) { return (.destructive, "deletes a tag (git tag)") }
            if sub == "remote", rest.dropFirst().first.map({ ["add", "set-url", "remove", "rm", "update"].contains($0) }) == true {
                return (.network, "changes remotes (git remote)")
            }
            if sub == "worktree", rest.dropFirst().first.map({ ["remove", "prune"].contains($0) }) == true { return (.destructive, "removes a worktree (git worktree)") }
            if sub == "apply" || sub == "mv" { return (.unfamiliar, "changes files (git \(sub))") }
            return (.safe, "")
        case "push":
            let forced = flags.contains { ["-f", "--force", "--force-with-lease", "--delete", "-d", "--mirror"].contains($0) || $0.hasPrefix("--force") }
            return forced ? (.destructive, "force-pushes or deletes remote work (git push)") : (.network, "publishes commits (git push)")
        case "clone", "fetch", "pull", "ls-remote", "submodule":
            return (.network, "uses the network (git \(sub))")
        case "reset", "clean", "restore", "checkout", "rebase", "filter-branch", "filter-repo", "gc", "prune", "revert":
            return (.destructive, "can discard work (git \(sub))")
        default:
            return (.unfamiliar, "isn't a git command Zeus knows (git \(sub))")
        }
    }

    // MARK: Parsing

    struct Segment: Equatable { var words: [String]; var afterPipe: Bool }
    struct Redirect: Equatable { var target: String; var append: Bool }
    struct Parsed {
        var segments: [Segment] = []
        var redirects: [Redirect] = []
        var substitution = false
    }

    /// Quote-aware split of a command line into simple commands. Not a full shell parser: anything
    /// it cannot tell apart is read as the more dangerous thing.
    static func parse(_ text: String) -> Parsed {
        var parsed = Parsed()
        var words: [String] = []
        var word = ""
        var hasWord = false
        var singleQuoted = false, doubleQuoted = false, escaped = false
        var pendingRedirect: Bool?          // append?, while waiting for the target word
        var nextAfterPipe = false
        let characters = Array(text)
        var index = 0

        func endWord() {
            guard hasWord else { return }
            if let append = pendingRedirect {
                parsed.redirects.append(Redirect(target: word, append: append))
                pendingRedirect = nil
            } else {
                words.append(word)
            }
            word = ""; hasWord = false
        }
        func endSegment(pipe: Bool) {
            endWord()
            if !words.isEmpty { parsed.segments.append(Segment(words: words, afterPipe: nextAfterPipe)) }
            words = []
            nextAfterPipe = pipe
        }

        while index < characters.count {
            let c = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if escaped { word.append(c); hasWord = true; escaped = false; index += 1; continue }
            if singleQuoted {
                if c == "'" { singleQuoted = false } else { word.append(c) }
                index += 1; continue
            }
            if c == "\\" { escaped = true; index += 1; continue }
            if doubleQuoted {
                if c == "\"" { doubleQuoted = false }
                else {
                    if c == "`" || (c == "$" && next == "(") { parsed.substitution = true }
                    word.append(c)
                }
                index += 1; continue
            }
            switch c {
            case "'": singleQuoted = true; hasWord = true
            case "\"": doubleQuoted = true; hasWord = true
            case "`": parsed.substitution = true; endWord()
            case "$" where next == "(": parsed.substitution = true; word.append(c); hasWord = true
            case " ", "\t": endWord()
            case ";", "\n": endSegment(pipe: false)
            case "|":
                if next == "|" { index += 1 }
                endSegment(pipe: next != "|")
            case "&":
                let previous: Character? = index > 0 ? characters[index - 1] : nil
                if previous == ">" || previous == "<" { word.append(c); hasWord = true }
                else { if next == "&" { index += 1 }; endSegment(pipe: false) }
            case ">":
                // "2>file": the digit is the file descriptor, not an argument.
                if hasWord, word.allSatisfy(\.isNumber) { word = ""; hasWord = false } else { endWord() }
                var append = false
                if next == ">" { append = true; index += 1 }
                if index + 1 < characters.count, characters[index + 1] == "&" {
                    // 2>&1 : a descriptor, nothing written to a file.
                    index += 1
                    word = "&"; hasWord = true
                    pendingRedirect = append
                } else {
                    pendingRedirect = append
                }
            default: word.append(c); hasWord = true
            }
            index += 1
        }
        endSegment(pipe: false)
        return parsed
    }
}
