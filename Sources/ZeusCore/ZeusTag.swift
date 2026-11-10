import Foundation

/// A point in screenshot pixels (top-left origin) on a given screen.
public struct PointTarget: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let label: String?
    /// 1-based screen number from the screenshot labels; nil means the cursor's screen.
    public let screen: Int?

    public init(x: Int, y: Int, label: String? = nil, screen: Int? = nil) {
        self.x = x
        self.y = y
        self.label = label
        self.screen = screen
    }
}

public struct HighlightTarget: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let label: String?
    public let screen: Int?

    public init(x: Int, y: Int, width: Int, height: Int, label: String? = nil, screen: Int? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.label = label
        self.screen = screen
    }
}

public struct ZeusAction: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case browserRead = "browser.read"
        case browserOpen = "browser.open"
        case browserClick = "browser.click"
        case browserType = "browser.type"
        // Indexed browser actions: they act on the numbered elements of the active tab
        // (`page.elements`), or on tabs and history. Typed views live in `BrowserCommand`.
        case browserClickIndex = "browser.click_index"
        case browserTypeIndex = "browser.type_index"
        case browserSelect = "browser.select"
        case browserScroll = "browser.scroll"
        case browserBack = "browser.back"
        case browserForward = "browser.forward"
        case browserSwitchTab = "browser.switch_tab"
        case browserCloseTab = "browser.close_tab"
        case browserExtract = "browser.extract"
        /// A multi-step web task ("book…", "find the cheapest…") worked through by the browser
        /// agent, one checked step at a time (`BrowserAgentLoop`). Payload: `goal`.
        case browserAgent = "browser.agent"
        case panelOpen = "panel.open"
        case delegateChrome = "delegate.chrome"
        case delegateDust = "delegate.dust"
        /// Moves, clicks and types in Mac apps (Accessibility first, CGEvent fallback).
        case macDrive = "mac.drive"
        /// A guided, multi-step "do it yourself" tour: point, explain, wait for the click.
        case macWalkthrough = "mac.walkthrough"
        /// A visual answer card in the notch (steps, list, chart).
        case presentCard = "present.card"
        /// Starts a coding agent (Claude Code, Codex, Gemini, Cursor Agent) in Tony's terminal, in a
        /// project folder, with the task as its first prompt. Payload: `task`, `tool?`, `project?`, `dir?`.
        case terminalAgent = "terminal.agent"
        /// A plain terminal window in a project or folder. Payload: `project?`, `dir?`.
        case terminalOpen = "terminal.open"
        /// Runs a shell command in a terminal; anything destructive or networked asks Tony first.
        /// Payload: `command`, `dir?`.
        case terminalRun = "terminal.run"
        /// A web research turn: searches and reads pages, speaks a short answer, saves the report.
        /// Payload: `question`, `depth` ("quick" or "deep").
        case research = "research"
    }

    public let kind: Kind
    /// The whole action object as sent, including `type`.
    public let payload: [String: JSONValue]

    public init(kind: Kind, payload: [String: JSONValue]) {
        self.kind = kind
        self.payload = payload
    }

    /// Actions that always need the user's OK, regardless of site consent.
    public var alwaysNeedsConsent: Bool { kind == .delegateChrome }

    /// The tag a model writes for this action, e.g. `[ACTION:{"type":"browser.back"}]`.
    /// Keys are sorted and `type` always matches `kind`, so parsing it gives this action back.
    public var tagText: String {
        var object = payload
        object["type"] = .string(kind.rawValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = (try? encoder.encode(JSONValue.object(object))).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "[ACTION:\(json)]"
    }
}

public enum ZeusTag: Equatable, Sendable {
    /// nil target = `[POINT:none]`
    case point(PointTarget?)
    case highlight(HighlightTarget)
    case action(ZeusAction)

    /// The tag as a model would write it; `ZeusTagParser.parse` reads it back.
    /// Labels can't contain ":" or "]" (the tag syntax has no escaping).
    public var tagText: String {
        func fields(_ label: String?, _ screen: Int?) -> String {
            (label.map { ":\($0)" } ?? "") + (screen.map { ":screen\($0)" } ?? "")
        }
        switch self {
        case .point(nil):
            return "[POINT:none]"
        case .point(let target?):
            return "[POINT:\(target.x),\(target.y)\(fields(target.label, target.screen))]"
        case .highlight(let area):
            return "[HIGHLIGHT:\(area.x),\(area.y),\(area.width),\(area.height)\(fields(area.label, area.screen))]"
        case .action(let action):
            return action.tagText
        }
    }
}

/// Parses ZEUS reply tags. Tags are expected at the start of a reply; a trailing tag
/// (Clicky's old style) is also accepted so a model that ignores the instruction still works.
public enum ZeusTagParser {
    static let prefixes = ["[POINT:", "[HIGHLIGHT:", "[ACTION:"]

    public struct Result: Equatable, Sendable {
        public let tags: [ZeusTag]
        public let spokenText: String
    }

    public static func parse(_ reply: String) -> Result {
        var tags: [ZeusTag] = []
        var rest = Substring(reply)

        while true {
            rest = rest.drop(while: \.isWhitespace)
            switch matchTag(in: rest) {
            case .complete(let tag, let length):
                if let tag { tags.append(tag) }
                rest = rest.dropFirst(length)
            case .incomplete, .notATag:
                var spoken = String(rest)
                spoken = stripTrailingTags(from: spoken, into: &tags)
                return Result(tags: tags, spokenText: spoken.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    enum Match {
        /// `tag` is nil when the tag was well-delimited but malformed; it is still removed from speech.
        case complete(ZeusTag?, length: Int)
        case incomplete
        case notATag
    }

    static func matchTag(in text: Substring) -> Match {
        guard text.first == "[" else { return text.isEmpty ? .incomplete : .notATag }
        guard let prefix = prefixes.first(where: { text.hasPrefix($0) }) else {
            // Could still become a tag once more characters stream in.
            return prefixes.contains(where: { $0.hasPrefix(text) }) ? .incomplete : .notATag
        }
        let body = text.dropFirst(prefix.count)

        if prefix == "[ACTION:" {
            guard let jsonEnd = endOfJSONObject(in: body) else { return .incomplete }
            let afterJSON = body[jsonEnd...].drop(while: \.isWhitespace)
            guard let close = afterJSON.first else { return .incomplete }
            guard close == "]" else { return .notATag }
            let json = String(body[body.startIndex..<jsonEnd])
            let length = text.distance(from: text.startIndex, to: afterJSON.startIndex) + 1
            return .complete(parseAction(json), length: length)
        }

        guard let closeIndex = body.firstIndex(of: "]") else { return .incomplete }
        let inner = String(body[body.startIndex..<closeIndex])
        let length = text.distance(from: text.startIndex, to: closeIndex) + 1
        let tag = prefix == "[POINT:" ? parsePoint(inner) : parseHighlight(inner)
        return .complete(tag, length: length)
    }

    static func parsePoint(_ inner: String) -> ZeusTag? {
        let trimmed = inner.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased() == "none" { return .point(nil) }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let coords = parts[0].split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard coords.count == 2, let x = coords[0], let y = coords[1] else { return nil }
        let (label, screen) = labelAndScreen(Array(parts.dropFirst()))
        return .point(PointTarget(x: x, y: y, label: label, screen: screen))
    }

    static func parseHighlight(_ inner: String) -> ZeusTag? {
        let parts = inner.trimmingCharacters(in: .whitespaces)
            .split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let numbers = parts[0].split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4, let x = numbers[0], let y = numbers[1], let w = numbers[2], let h = numbers[3],
              w > 0, h > 0 else { return nil }
        let (label, screen) = labelAndScreen(Array(parts.dropFirst()))
        return .highlight(HighlightTarget(x: x, y: y, width: w, height: h, label: label, screen: screen))
    }

    /// Optional trailing fields: `label` and/or `screenN`, in that order.
    static func labelAndScreen(_ fields: [String]) -> (String?, Int?) {
        var label: String?
        var screen: Int?
        for field in fields {
            let value = field.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("screen"), let number = Int(value.dropFirst("screen".count)) {
                screen = number
            } else if !value.isEmpty, label == nil {
                label = value
            }
        }
        return (label, screen)
    }

    static func parseAction(_ json: String) -> ZeusTag? {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let object) = value,
              let type = object["type"]?.stringValue,
              let kind = ZeusAction.Kind(rawValue: type) else { return nil }
        return .action(ZeusAction(kind: kind, payload: object))
    }

    /// Index just past the closing brace of the JSON object starting at `text`, string-aware.
    static func endOfJSONObject(in text: Substring) -> Substring.Index? {
        let start = text.drop(while: \.isWhitespace)
        guard start.first == "{" else { return start.isEmpty ? nil : start.startIndex }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start.startIndex
        while index < start.endIndex {
            let character = start[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return start.index(after: index) }
            }
            index = start.index(after: index)
        }
        return nil
    }

    static func stripTrailingTags(from text: String, into tags: inout [ZeusTag]) -> String {
        var spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var trailing: [ZeusTag] = []
        while spoken.hasSuffix("]"), let open = spoken.lastIndex(of: "[") {
            let candidate = spoken[open...]
            guard case .complete(let tag, let length) = matchTag(in: candidate),
                  length == candidate.count else { break }
            if let tag { trailing.insert(tag, at: 0) }
            spoken = String(spoken[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        tags.append(contentsOf: trailing)
        return spoken
    }
}

/// Incremental version of `ZeusTagParser` for streamed replies: tags are emitted as soon as
/// they are complete, so the spark can start flying before any words are spoken.
public struct ZeusTagStreamParser: Sendable {
    public enum Output: Equatable, Sendable {
        case tag(ZeusTag)
        case text(String)
    }

    private var buffer = ""
    private var inLeadingTags = true

    public init() {}

    public mutating func feed(_ delta: String) -> [Output] {
        buffer += delta
        var outputs: [Output] = []

        while inLeadingTags {
            let trimmed = buffer.drop(while: \.isWhitespace)
            switch ZeusTagParser.matchTag(in: trimmed) {
            case .complete(let tag, let length):
                if let tag { outputs.append(.tag(tag)) }
                buffer = String(trimmed.dropFirst(length))
            case .incomplete:
                return outputs
            case .notATag:
                inLeadingTags = false
                buffer = String(trimmed)
            }
        }

        // Hold back anything from a "[" that might be the start of a trailing tag.
        if let open = buffer.lastIndex(of: "["),
           ZeusTagParser.prefixes.contains(where: { buffer[open...].hasPrefix($0) || $0.hasPrefix(buffer[open...]) }) {
            let ready = String(buffer[..<open])
            buffer = String(buffer[open...])
            if !ready.isEmpty { outputs.append(.text(ready)) }
        } else if !buffer.isEmpty {
            outputs.append(.text(buffer))
            buffer = ""
        }
        return outputs
    }

    /// Call once the reply has finished streaming.
    public mutating func finish() -> [Output] {
        defer { buffer = "" }
        guard !buffer.isEmpty else { return [] }
        let result = ZeusTagParser.parse(buffer)
        var outputs: [Output] = []
        if !result.spokenText.isEmpty { outputs.append(.text(result.spokenText)) }
        outputs.append(contentsOf: result.tags.map(Output.tag))
        return outputs
    }
}
