import Foundation

/// What an approval would touch, read before Allow once on the hub decision row.
/// Paths only. The text of a secret is never copied into the preview.
public struct HubApprovalImpact: Equatable, Sendable {
    public var files: [String]
    public var deletes: [String]
    public var hosts: [String]
    public var installs: [String]
    public var forcePush: [String]
    public var secretPaths: [String]

    /// The allow control keeps this name. It is not renamed.
    public static let allowOnceTitle = "Allow once"
    public static let denyTitle = "Deny"

    public var isEmpty: Bool {
        files.isEmpty && deletes.isEmpty && hosts.isEmpty && installs.isEmpty && forcePush.isEmpty && secretPaths.isEmpty
    }

    public struct Line: Equatable, Sendable {
        public var title: String
        public var detail: String
    }

    public init(files: [String] = [], deletes: [String] = [], hosts: [String] = [], installs: [String] = [],
                forcePush: [String] = [], secretPaths: [String] = []) {
        self.files = files
        self.deletes = deletes
        self.hosts = hosts
        self.installs = installs
        self.forcePush = forcePush
        self.secretPaths = secretPaths
    }

    /// The same agent and project as the hub session, or the approval's own session id.
    public static func matchesSession(approvalSession: String?, approvalAgent: String, approvalProject: String,
                                      sessionID: String, sessionAgent: String, sessionProject: String) -> Bool {
        if let approvalSession { return approvalSession == sessionID }
        guard approvalAgent == sessionAgent else { return false }
        if approvalProject == sessionProject { return true }
        let approvalName = URL(fileURLWithPath: approvalProject).lastPathComponent
        let sessionName = URL(fileURLWithPath: sessionProject).lastPathComponent
        return !approvalName.isEmpty && approvalName == sessionName
    }

    /// Tool input wins over the one-line card text, which is cut short for display.
    public static func preview(tool: String?, command: String?, input: JSONValue?) -> HubApprovalImpact {
        _ = tool
        var found = Found()
        if let path = input?["file_path"]?.stringValue ?? input?["path"]?.stringValue {
            found.file(path)
        }
        if let url = input?["url"]?.stringValue {
            found.noteWord(url)
        }
        let full = input?["command"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = command?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let full, !full.isEmpty {
            found.consume(full)
        } else if let shown, !shown.isEmpty {
            found.consume(shown)
        }
        return found.impact
    }

    public func lines(detailsHidden: Bool) -> [Line] {
        if detailsHidden { return isEmpty ? [] : [Line(title: "Details hidden", detail: "")] }
        var rows: [Line] = []
        func add(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            rows.append(Line(title: title, detail: Self.joined(items)))
        }
        add("Files", files)
        add("Deletes", deletes)
        add("Hosts", hosts)
        add("Installs", installs)
        add("Force-push", forcePush)
        add("Secret paths", secretPaths)
        return rows
    }

    /// Spoken before the allow control. Hidden details name no path.
    public func accessibilitySummary(detailsHidden: Bool) -> String {
        if detailsHidden { return isEmpty ? "" : "Details hidden" }
        let rows = lines(detailsHidden: false)
        guard !rows.isEmpty else { return "" }
        return "Before allow. " + rows.map { "\($0.title) \($0.detail)" }.joined(separator: ". ")
    }

    private static func joined(_ items: [String]) -> String {
        let shown = items.prefix(8)
        var text = shown.joined(separator: ", ")
        let extra = items.count - shown.count
        if extra > 0 { text += ", and \(extra) more" }
        return text
    }
}

private struct Found {
    private var files: [String] = []
    private var deletes: [String] = []
    private var hosts: [String] = []
    private var installs: [String] = []
    private var forcePush: [String] = []
    private var secretPaths: [String] = []

    var impact: HubApprovalImpact {
        HubApprovalImpact(files: files, deletes: deletes, hosts: hosts, installs: installs,
                          forcePush: forcePush, secretPaths: secretPaths)
    }

    private static let wrappers: Set<String> = ["env", "nohup", "time", "nice", "command", "exec", "sudo", "doas", "caffeinate", "builtin"]
    private static let secretStems: Set<String> = [
        "credentials", "credential", "secrets", "secret", "password", "passwords",
        "token", "tokens", "apikey", "api_key", "service-account", "serviceaccount",
    ]
    private static let secretExtensions: Set<String> = ["pem", "p12", "pfx", "key", "keystore", "jks"]
    private static let keyNames: Set<String> = ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"]

    mutating func consume(_ text: String) {
        let parsed = ShellRiskClassifier.parse(text)
        for redirect in parsed.redirects where redirect.target != "/dev/null" && !redirect.target.hasPrefix("&") {
            file(redirect.target)
        }
        for segment in parsed.segments {
            consume(words: segment.words)
        }
    }

    private mutating func consume(words: [String]) {
        guard let command = split(words) else { return }
        noteSecrets(command.args)
        noteHosts(command.args)
        switch command.name {
        case "rm", "rmdir", "unlink", "shred", "srm":
            for path in operands(command.args) { delete(path) }
        case "curl", "wget":
            takeOutput(command.args)
        case "git":
            takeGit(command.args)
        case "npm", "pnpm", "yarn", "bun", "brew", "pip", "pip3", "cargo", "gem", "pod":
            takeInstall(name: command.name, args: command.args)
        case "cp", "mv", "ln", "tee", "install":
            for path in operands(command.args) { file(path) }
        case "sed":
            if command.args.contains(where: { $0 == "-i" || $0.hasPrefix("-i") }) {
                for path in operands(command.args) where Self.looksLikePath(path) { file(path) }
            }
        case "find":
            if command.args.contains("-delete") { delete("matched files") }
        default:
            break
        }
    }

    private mutating func takeOutput(_ args: [String]) {
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "-o" || arg == "--output" || arg == "--output-document", index + 1 < args.count {
                index += 1
                file(args[index])
            }
            index += 1
        }
    }

    private mutating func takeGit(_ args: [String]) {
        let rest = skipGitGlobals(args)
        guard let sub = rest.first?.lowercased() else { return }
        let tail = Array(rest.dropFirst())
        let flags = tail.filter { $0.hasPrefix("-") && $0 != "-" }
        let paths = operands(tail)
        switch sub {
        case "push":
            let forced = flags.contains { flag in
                let name = String(flag.split(separator: "=", maxSplits: 1).first ?? Substring(flag))
                return name == "-f" || name == "--force" || name == "--mirror" || name.hasPrefix("--force")
            }
            if forced { force(paths.isEmpty ? "this remote" : paths.joined(separator: " ")) }
            if flags.contains(where: { $0 == "--delete" || $0 == "-d" }) {
                if paths.isEmpty { delete("a remote ref") } else { for path in paths { delete(path) } }
            }
        case "rm":
            for path in paths { delete(path) }
        case "clean":
            if paths.isEmpty { delete("untracked files") } else { for path in paths { delete(path) } }
        case "add":
            for path in paths { file(path) }
        default:
            break
        }
    }

    private mutating func takeInstall(name: String, args: [String]) {
        switch name {
        case "npm", "pnpm", "yarn", "bun":
            guard let verb = args.first?.lowercased(), ["install", "i", "add", "ci", "update", "upgrade"].contains(verb) else { return }
            if verb == "ci" { install("the lockfile"); return }
            place(operands(Array(args.dropFirst())), empty: "dependencies")
        case "brew":
            guard args.first?.lowercased() == "install" else { return }
            place(operands(Array(args.dropFirst())), empty: "a formula")
        case "pip", "pip3":
            guard args.first?.lowercased() == "install" else { return }
            place(operands(Array(args.dropFirst())), empty: "packages")
        case "cargo":
            guard args.first?.lowercased() == "install" else { return }
            place(operands(Array(args.dropFirst())), empty: "a crate")
        case "gem":
            guard args.first?.lowercased() == "install" else { return }
            place(operands(Array(args.dropFirst())), empty: "a gem")
        case "pod":
            guard args.first?.lowercased() == "install" else { return }
            place(operands(Array(args.dropFirst())), empty: "CocoaPods")
        default:
            break
        }
    }

    private mutating func place(_ names: [String], empty: String) {
        if names.isEmpty { install(empty); return }
        for name in names {
            if Self.looksLikePath(name) { file(name) } else { install(name) }
        }
    }

    mutating func noteWord(_ word: String) {
        if let host = Self.host(of: word) { self.host(host) }
        if Self.isSecret(word) { secret(word) }
    }

    private mutating func noteHosts(_ words: [String]) {
        for word in words { if let host = Self.host(of: word) { self.host(host) } }
    }

    private mutating func noteSecrets(_ words: [String]) {
        for word in operands(words) where Self.isSecret(word) { secret(word) }
    }

    mutating func file(_ path: String) {
        guard let cleaned = clean(path), cleaned != "/dev/null" else { return }
        let current = files
        files = Self.stored(cleaned, in: current)
        if Self.isSecret(cleaned) { secret(cleaned) }
    }

    private mutating func delete(_ path: String) {
        guard let cleaned = clean(path) else { return }
        let current = deletes
        deletes = Self.stored(cleaned, in: current)
        if Self.isSecret(cleaned) { secret(cleaned) }
    }

    private mutating func host(_ name: String) {
        let current = hosts
        hosts = Self.stored(name, in: current)
    }

    private mutating func install(_ name: String) {
        let current = installs
        installs = Self.stored(name, in: current)
    }

    private mutating func force(_ name: String) {
        let current = forcePush
        forcePush = Self.stored(name, in: current)
    }

    private mutating func secret(_ path: String) {
        guard let cleaned = clean(path) else { return }
        let current = secretPaths
        secretPaths = Self.stored(cleaned, in: current)
    }

    private func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return nil }
        return trimmed
    }

    /// A copy, then a write. Passing `&files` into a method on self is an overlapping access.
    private static func stored(_ item: String, in list: [String]) -> [String] {
        guard !list.contains(item), list.count < 32 else { return list }
        var next = list
        next.append(item)
        return next
    }

    private func split(_ words: [String]) -> (name: String, args: [String])? {
        var index = 0
        while index < words.count {
            let word = words[index]
            if isAssignment(word) || Self.wrappers.contains(base(word)) {
                index += 1
                continue
            }
            return (base(word), Array(words.dropFirst(index + 1)))
        }
        return nil
    }

    private func base(_ word: String) -> String { URL(fileURLWithPath: word).lastPathComponent.lowercased() }

    private func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        return word[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private func operands(_ args: [String]) -> [String] {
        var ended = false
        var result: [String] = []
        for arg in args {
            if arg == "--" { ended = true; continue }
            if !ended, arg.hasPrefix("-"), arg != "-" { continue }
            result.append(arg)
        }
        return result
    }

    private func skipGitGlobals(_ args: [String]) -> [String] {
        var rest = args[...]
        while let first = rest.first, first.hasPrefix("-") {
            rest = rest.dropFirst()
            let name = String(first.split(separator: "=", maxSplits: 1).first ?? Substring(first))
            if ["-C", "-c", "--git-dir", "--work-tree", "--namespace"].contains(name), !first.contains("=") {
                rest = rest.dropFirst()
            }
        }
        return Array(rest)
    }

    private static func looksLikePath(_ word: String) -> Bool {
        if word.contains("://") || word.hasPrefix("-") { return false }
        if word.hasPrefix("/") || word.hasPrefix("./") || word.hasPrefix("../") || word.hasPrefix("~/") || word.hasPrefix(".") {
            return true
        }
        if word.contains("/") { return true }
        let ext = URL(fileURLWithPath: word).pathExtension
        return !ext.isEmpty && ext.count <= 8 && word.contains(".")
    }

    static func host(of word: String) -> String? {
        if word.contains("://"), let host = URL(string: word)?.host, !host.isEmpty {
            return host.lowercased()
        }
        if word.lowercased().hasPrefix("git@") {
            let rest = word.dropFirst(4)
            if let host = rest.split(separator: ":", maxSplits: 1).first, host.contains(".") {
                return String(host).lowercased()
            }
        }
        if !word.hasPrefix("-"), let at = word.firstIndex(of: "@"), at != word.startIndex {
            let after = word[word.index(after: at)...]
            let host = after.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
            if host.contains("."), !host.contains("/") { return host.lowercased() }
        }
        return nil
    }

    static func isSecret(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/dev/null" else { return false }
        let url = URL(fileURLWithPath: trimmed)
        let base = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        let lowered = trimmed.lowercased()
        if base == ".env" || base.hasPrefix(".env.") || base == ".npmrc" || base == ".netrc" || base == ".pypirc" || base == ".pgpass" {
            return true
        }
        if secretExtensions.contains(ext) || keyNames.contains(base) { return true }
        if base.hasPrefix("id_rsa") || base.hasPrefix("id_ed25519") { return true }
        let stem = base.split(separator: ".").first.map(String.init) ?? base
        if secretStems.contains(stem) || secretStems.contains(base) { return true }
        if lowered.contains(".ssh/") || lowered.contains(".aws/") || lowered.contains(".gnupg/")
            || lowered.contains(".kube/") || lowered.contains("/secrets/") || lowered.hasPrefix("secrets/") {
            return true
        }
        return lowered.contains("service-account") || lowered.contains("serviceaccount")
    }
}
