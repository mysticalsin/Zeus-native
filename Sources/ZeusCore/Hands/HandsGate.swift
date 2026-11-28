import Foundation

/// Why a hands action stops for a yes, or never runs.
public enum HandsRiskKind: String, Codable, Equatable, Sendable, CaseIterable {
    case send, delete, buy, change
}

/// What Zeus is about to do. Shell lines are judged by `HandsBlocklist` before anything else.
public enum HandsIntent: Equatable, Sendable {
    case act(String)
    case shell(String)
    case send(to: String, text: String)
    case delete(files: [String])
    case buy(item: String, price: String)
    case changeFile(path: String, summary: String)

    public var riskKind: HandsRiskKind? {
        switch self {
        case .send: .send
        case .delete: .delete
        case .buy: .buy
        case .changeFile: .change
        case .act, .shell: nil
        }
    }

    /// The exact ask, for the local log.
    public var command: String {
        switch self {
        case .act(let text): text
        case .shell(let text): text
        case .send(let to, let text): "send to \(to): \(text)"
        case .delete(let files): "trash \(files.joined(separator: " "))"
        case .buy(let item, let price): "buy \(item) \(price)"
        case .changeFile(let path, let summary): "change \(path): \(summary)"
        }
    }
}

/// The Allow card body: exactly what will change, and nothing else.
public struct HandsPreview: Equatable, Sendable {
    public var title: String
    public var lines: [String]

    public init(title: String, lines: [String]) {
        self.title = title
        self.lines = lines
    }

    public var card: String { ([title] + lines).joined(separator: "\n") }
}

public enum HandsVerdict: Equatable, Sendable {
    case allow
    case approve(HandsPreview)
    case block(String)
}

/// Files are moved to the Trash. The plan never names `rm`.
public struct TrashPlan: Equatable, Sendable {
    public var files: [String]
    public var command: String

    public init(files: [String]) {
        self.files = files
        self.command = "trash"
    }

    public var usesRemove: Bool { command.split(whereSeparator: \.isWhitespace).contains { $0 == "rm" } }
}

/// `rm`, `sudo`, `dd`, `diskutil`, `shutdown` and `git push` never run.
public enum HandsBlocklist {
    public static func reason(_ command: String) -> String? {
        for words in HandsShell.segments(of: command) {
            guard let (name, rest) = HandsShell.command(words) else { continue }
            if let reason = reason(name: name, rest: rest) { return reason }
        }
        return nil
    }

    static func reason(name: String, rest: [String]) -> String? {
        switch name {
        case "rm": return "rm is blocked"
        case "sudo": return "sudo is blocked"
        case "dd": return "dd is blocked"
        case "diskutil": return "diskutil is blocked"
        case "shutdown": return "shutdown is blocked"
        case "git": return isPush(rest) ? "git push is blocked" : nil
        default: return nil
        }
    }

    /// `git`, then optional global flags, then `push`.
    static func isPush(_ arguments: [String]) -> Bool {
        var rest = arguments[...]
        while let first = rest.first, first.hasPrefix("-") {
            rest = rest.dropFirst()
            if ["-C", "-c", "--git-dir", "--work-tree", "--namespace"].contains(first) {
                rest = rest.dropFirst()
            }
        }
        return rest.first?.lowercased() == "push"
    }
}

enum HandsShell {
    static let wrappers: Set<String> = ["env", "nohup", "time", "nice", "command", "exec", "builtin"]

    static func segments(of command: String) -> [[String]] {
        var segments: [[String]] = [[]]
        var word = ""
        var quote: Character?
        var escaping = false
        let chars = Array(command)
        var index = 0

        func endWord() {
            if !word.isEmpty {
                segments[segments.count - 1].append(word)
                word = ""
            }
        }
        func endSegment() {
            endWord()
            if !(segments.last?.isEmpty ?? true) { segments.append([]) }
        }

        while index < chars.count {
            let character = chars[index]
            if escaping {
                word.append(character)
                escaping = false
                index += 1
                continue
            }
            if character == "\\", quote != "'" {
                escaping = true
                index += 1
                continue
            }
            if let open = quote {
                if character == open { quote = nil } else { word.append(character) }
                index += 1
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                index += 1
                continue
            }
            if character == " " || character == "\t" || character == "\n" {
                endWord()
                index += 1
                continue
            }
            if character == ";" {
                endSegment()
                index += 1
                continue
            }
            if character == "|" {
                endSegment()
                if index + 1 < chars.count, chars[index + 1] == "|" { index += 1 }
                index += 1
                continue
            }
            if character == "&", index + 1 < chars.count, chars[index + 1] == "&" {
                endSegment()
                index += 2
                continue
            }
            word.append(character)
            index += 1
        }
        endWord()
        return segments.filter { !$0.isEmpty }
    }

    static func command(_ words: [String]) -> (name: String, rest: [String])? {
        var index = 0
        while index < words.count {
            let word = words[index]
            if isAssignment(word) {
                index += 1
                continue
            }
            let base = URL(fileURLWithPath: word).lastPathComponent.lowercased()
            if wrappers.contains(base) {
                index += 1
                while index < words.count, words[index].hasPrefix("-") || isAssignment(words[index]) {
                    index += 1
                }
                continue
            }
            return (base, Array(words[(index + 1)...]))
        }
        return nil
    }

    static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        return word[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

public enum HandsGate {
    public static func judge(_ intent: HandsIntent, allowed: Set<HandsRiskKind> = []) -> HandsVerdict {
        switch intent {
        case .shell(let command):
            if let reason = HandsBlocklist.reason(command) { return .block(reason) }
            return .allow
        case .act:
            return .allow
        case .send(let to, let text):
            if allowed.contains(.send) { return .allow }
            return .approve(HandsPreview(title: "Send", lines: ["To \(to)", text]))
        case .delete(let files):
            if allowed.contains(.delete) { return .allow }
            return .approve(HandsPreview(title: "Trash", lines: files))
        case .buy(let item, let price):
            if allowed.contains(.buy) { return .allow }
            return .approve(HandsPreview(title: "Buy", lines: [item, price]))
        case .changeFile(let path, let summary):
            if allowed.contains(.change) { return .allow }
            return .approve(HandsPreview(title: "Change", lines: [path, summary]))
        }
    }

    public static func trash(_ files: [String]) -> TrashPlan { TrashPlan(files: files) }

    /// A button named Send, Delete or Buy waits for the same card as the matching intent.
    public static func intent(clicking label: String) -> HandsIntent? {
        switch HandsClickLabelBox.trimmedLabel(label).lowercased() {
        case "send": return .send(to: "the open draft", text: "Send")
        case "delete": return .delete(files: [label])
        case "buy", "purchase": return .buy(item: label, price: "the shown price")
        default: return nil
        }
    }
}

/// One local line per command, including the ones that were blocked.
public struct HandsCommandLog: Equatable, Sendable {
    public private(set) var lines: [String] = []

    public init() {}

    public mutating func record(command: String, verdict: String, outcome: String, at: Date = Date()) {
        let stamp = ISO8601DateFormatter().string(from: at)
        let flat = Self.redacted(command.replacingOccurrences(of: "\n", with: " "))
        lines.append("\(stamp)\t\(flat)\t\(verdict)\t\(outcome)")
    }

    /// Drops bearer tokens, password-like arguments, env assignments and URL credentials.
    /// Ordinary arguments stay so the log still says what ran.
    static func redacted(_ command: String) -> String {
        var text = replace(command, #"(?i)([a-z][a-z0-9+.-]*://)[^\s/:@]+:[^\s/@]+@"#, "$1[redacted]@")
        text = redactArguments(text)
        text = replace(text, #"(?i)\bBearer\s+(?!\[redacted\])\S+"#, "Bearer [redacted]")
        text = replace(text, #"(?i)\bX-Api-Key:\s*\S+"#, "X-Api-Key: [redacted]")
        text = replace(text, #"(?i)\bAuthorization:\s+Basic\s+\S+"#, "Authorization: Basic [redacted]")
        text = replace(text, #"(?i)\bCookie:\s*\S+"#, "Cookie: [redacted]")
        return text
    }

    private static let secretFlagNames: Set<String> = [
        "password", "passwd", "token", "api-key", "apikey", "api_key", "secret",
        "access-token", "access_token", "authorization", "bearer", "client-secret",
        "client_secret", "private-key", "private_key", "pwd", "p",
    ]

    /// An env name, or a name that is itself a secret (`API_KEY`, `TOKEN`). `if` and `of` are not.
    private static func isSecretName(_ name: String) -> Bool {
        let key = name.lowercased().replacingOccurrences(of: "-", with: "_")
        if key == "key" || key.hasSuffix("_key") { return true }
        return ["token", "secret", "password", "passwd", "apikey", "api_key", "bearer", "credential"].contains { key.contains($0) }
    }

    private static func flagName(_ word: String) -> String? {
        guard word.hasPrefix("-"), !HandsShell.isAssignment(word) else { return nil }
        let bare = word.drop { $0 == "-" }.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
        let name = bare.lowercased()
        return secretFlagNames.contains(name) ? name : nil
    }

    /// Env assignments sit before each command, including one after `;`. A secret-named assignment is removed wherever it sits.
    private static func redactArguments(_ command: String) -> String {
        let segments = commandSegments(command)
        guard !segments.isEmpty else { return command }
        var replacements: [(start: String.Index, end: String.Index, text: String)] = []
        for segment in segments {
            let commandAt = commandWord(segment[...])
            var cursor = 0
            while cursor < segment.count {
                let word = segment[cursor]
                if let equals = word.text.firstIndex(of: "="), HandsShell.isAssignment(word.text) {
                    let name = String(word.text[..<equals])
                    if cursor < commandAt || isSecretName(name) {
                        let value = command.index(word.start, offsetBy: name.count + 1)
                        replacements.append((value, word.end, "[redacted]"))
                    }
                } else if flagName(word.text) != nil, let equals = word.text.firstIndex(of: "=") {
                    let value = command.index(word.start, offsetBy: word.text.distance(from: word.text.startIndex, to: word.text.index(after: equals)))
                    replacements.append((value, word.end, "[redacted]"))
                } else if flagName(word.text) != nil, cursor + 1 < segment.count, flagName(segment[cursor + 1].text) == nil {
                    let next = segment[cursor + 1]
                    replacements.append((next.start, next.end, "[redacted]"))
                    cursor += 1
                }
                cursor += 1
            }
        }
        var text = command
        for item in replacements.sorted(by: { $0.start > $1.start }) {
            text.replaceSubrange(item.start..<item.end, with: item.text)
        }
        return text
    }

    private struct CommandWord {
        var start: String.Index
        var end: String.Index
        var text: String
    }

    private static func commandSegments(_ command: String) -> [[CommandWord]] {
        var segments: [[CommandWord]] = [[]]
        var index = command.startIndex
        while index < command.endIndex {
            while index < command.endIndex, command[index] == " " || command[index] == "\t" { index = command.index(after: index) }
            guard index < command.endIndex else { break }
            if command[index] == ";" || command[index] == "|" || command[index] == "&" {
                if !(segments.last?.isEmpty ?? true) { segments.append([]) }
                index = command.index(after: index)
                continue
            }
            let start = index
            var quote: Character?
            while index < command.endIndex {
                let character = command[index]
                if let open = quote {
                    index = command.index(after: index)
                    if character == open { quote = nil }
                    continue
                }
                if character == "'" || character == "\"" { quote = character; index = command.index(after: index); continue }
                if character == " " || character == "\t" || character == ";" || character == "|" || character == "&" { break }
                index = command.index(after: index)
            }
            segments[segments.count - 1].append(CommandWord(start: start, end: index, text: String(command[start..<index])))
        }
        return segments.filter { !$0.isEmpty }
    }

    /// How many leading words are the env prefix and wrappers, using the same skip as the blocklist.
    private static func commandWord(_ words: ArraySlice<CommandWord>) -> Int {
        let list = Array(words)
        var index = 0
        while index < list.count {
            let word = list[index].text
            if HandsShell.isAssignment(word) { index += 1; continue }
            let base = URL(fileURLWithPath: word).lastPathComponent.lowercased()
            if HandsShell.wrappers.contains(base) {
                index += 1
                while index < list.count, list[index].text.hasPrefix("-") || HandsShell.isAssignment(list[index].text) {
                    index += 1
                }
                continue
            }
            return index
        }
        return index
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    public func contains(command: String) -> Bool {
        lines.contains { $0.split(separator: "\t", omittingEmptySubsequences: false).dropFirst().first.map(String.init) == command }
    }

    public var text: String { lines.joined(separator: "\n") }

    public func write(to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = (text + (lines.isEmpty ? "" : "\n")).data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: url.path), let handle = FileHandle(forWritingAtPath: url.path) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else if !FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum HandsCommandLogger {
    public static func append(command: String, verdict: String, outcome: String, url: URL = ZeusPaths.handsLog) {
        var log = HandsCommandLog()
        log.record(command: command, verdict: verdict, outcome: outcome)
        try? log.write(to: url)
    }

    public static func append(raw: String, url: URL = ZeusPaths.handsLog) {
        guard !raw.isEmpty else { return }
        let body = raw.hasSuffix("\n") ? raw : raw + "\n"
        guard let data = body.data(using: .utf8) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path), let handle = FileHandle(forWritingAtPath: url.path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Side effects stay at zero until Allow. "Always allow for this task" dies with the task.
public struct HandsGateSession: Equatable, Sendable {
    public var taskID: String
    public private(set) var effects = 0
    public private(set) var pending: HandsIntent?
    public private(set) var allowed: Set<HandsRiskKind> = []

    public init(taskID: String) {
        self.taskID = taskID
    }

    @discardableResult
    public mutating func propose(_ intent: HandsIntent, log: inout HandsCommandLog, at: Date = Date()) -> HandsVerdict {
        let verdict = HandsGate.judge(intent, allowed: allowed)
        switch verdict {
        case .allow:
            effects += 1
            pending = nil
            log.record(command: intent.command, verdict: "allow", outcome: "ran", at: at)
        case .approve(let preview):
            pending = intent
            log.record(command: intent.command, verdict: "approve", outcome: preview.card.replacingOccurrences(of: "\n", with: " | "), at: at)
        case .block(let reason):
            pending = nil
            log.record(command: intent.command, verdict: "blocked", outcome: reason, at: at)
        }
        return verdict
    }

    /// Allow or deny the card that is up. A block never becomes pending, so Allow cannot revive it.
    @discardableResult
    public mutating func decide(allow: Bool, forTask: Bool = false, log: inout HandsCommandLog, at: Date = Date()) -> Bool {
        guard let pending else { return false }
        let command = pending.command
        if allow {
            if forTask, let kind = pending.riskKind { allowed.insert(kind) }
            effects += 1
            self.pending = nil
            log.record(command: command, verdict: forTask ? "allow-task" : "allow", outcome: "ran", at: at)
            return true
        }
        self.pending = nil
        log.record(command: command, verdict: "deny", outcome: "stopped", at: at)
        return false
    }
}
