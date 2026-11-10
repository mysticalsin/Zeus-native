import Foundation

// browser-use's page state, mapped onto the browser agent's indexed elements, and the loop's ops
// mapped onto browser_* tools. Pure, so the whole mapping is tested without a browser.
//
// browser_get_state lists interactive elements with browser-use's own sparse, unordered indexes
// (35, then 4, 18...). The loop wants 1...N. The snapshot keeps both: the brain sees 1...N, the
// tool call gets the real index, and the page-state id covers the real indexes so a page whose
// numbering moved is a stale page.

public struct BrowserUseElement: Equatable, Sendable {
    public let index: Int
    public let tag: String
    public let text: String
    public let placeholder: String?
    public let href: String?

    public init(index: Int, tag: String, text: String, placeholder: String? = nil, href: String? = nil) {
        self.index = index
        self.tag = tag
        self.text = text
        self.placeholder = placeholder
        self.href = href
    }
}

public struct BrowserUseTab: Equatable, Sendable {
    public let url: String
    public let title: String

    public init(url: String, title: String) {
        self.url = url
        self.title = title
    }
}

/// `browser_get_state`'s JSON text.
public struct BrowserUseState: Equatable, Sendable {
    public let url: String
    public let title: String
    public let tabs: [BrowserUseTab]
    public let elements: [BrowserUseElement]

    public init(url: String, title: String, tabs: [BrowserUseTab] = [], elements: [BrowserUseElement] = []) {
        self.url = url
        self.title = title
        self.tabs = tabs
        self.elements = elements
    }

    public static func parse(_ text: String) -> BrowserUseState? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), case .object = value,
              let url = value["url"]?.stringValue else { return nil }
        let tabs = value["tabs"]?.arrayValue?.map {
            BrowserUseTab(url: $0["url"]?.stringValue ?? "", title: $0["title"]?.stringValue ?? "")
        } ?? []
        let elements: [BrowserUseElement] = value["interactive_elements"]?.arrayValue?.compactMap { item in
            guard let index = item["index"]?.numberValue.map({ Int($0) }), let tag = item["tag"]?.stringValue else { return nil }
            return BrowserUseElement(index: index, tag: tag.lowercased(), text: item["text"]?.stringValue ?? "",
                                     placeholder: item["placeholder"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 },
                                     href: item["href"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 })
        } ?? []
        return BrowserUseState(url: url, title: value["title"]?.stringValue ?? "", tabs: tabs, elements: elements)
    }
}

/// The agent's view of the page, and how to get back to browser-use's numbering.
public struct BrowserUseSnapshot: Equatable, Sendable {
    public let page: BrowserAgentPage
    /// Loop index (1...N) to browser-use's index.
    public let realIndex: [Int: Int]
    /// The loop's elements in list order, with browser-use's raw element beside each.
    public let raw: [BrowserUseElement]

    public init(page: BrowserAgentPage, realIndex: [Int: Int], raw: [BrowserUseElement]) {
        self.page = page
        self.realIndex = realIndex
        self.raw = raw
    }

    /// Before the first look: nothing to point at, so any indexed step is a stale page.
    public static let empty = BrowserUseSnapshot(page: BrowserAgentPage(url: "", title: ""), realIndex: [:], raw: [])

    public func real(_ index: Int) -> Int? { realIndex[index] }
}

/// One thing the backend does for a loop action. Composite ones (type then submit, tab and extract
/// steps that read first) are carried out by the backend with this as the plan.
public enum BrowserUseCall: Equatable, Sendable {
    case tool(String, [String: JSONValue])
    case type(realIndex: Int, text: String, submit: Bool)
    case switchTab(BrowserCommand.TabMatch)
    case closeTab(BrowserCommand.TabMatch?)
    case extract(limit: Int)
    case pause(milliseconds: Int)
    /// Nothing to do (browser-use scrolls an element into view when it clicks it).
    case none
    /// browser-use has no tool for it; the message goes back to the brain.
    case unsupported(String)
}

public enum BrowserUseMapping {
    // MARK: State

    public static let stateIDPrefix = "bu-"

    /// A page-state id that is the same for the same page and different when the address or any
    /// element (browser-use index, kind, label, link) differs. FNV-1a, not `Hasher`, so it is the
    /// same in every run. Scroll position and the viewport are left out on purpose.
    public static func stateID(url: String, elements: [BrowserUseElement]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ text: String) {
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
            hash ^= 0x1f
            hash = hash &* 0x0000_0100_0000_01b3
        }
        mix(url)
        for element in elements {
            mix("\(element.index)|\(element.tag)|\(element.text)|\(element.placeholder ?? "")|\(element.href ?? "")")
        }
        let hex = String(hash, radix: 16)
        return stateIDPrefix + String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }

    public static func snapshot(from state: BrowserUseState, title: String? = nil) -> BrowserUseSnapshot {
        var page: [PageElement] = []
        var map: [Int: Int] = [:]
        var raw: [BrowserUseElement] = []
        let source = state.elements
        for (position, element) in source.enumerated() {
            let isField = Self.fieldTags.contains(element.tag)
            // A label that sits right before its field is folded into the field's name.
            if element.tag == "label", position + 1 < source.count, Self.fieldTags.contains(source[position + 1].tag) { continue }
            var name = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if isField {
                var parts: [String] = []
                if position > 0, source[position - 1].tag == "label" {
                    let label = source[position - 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !label.isEmpty { parts.append(label) }
                }
                if element.tag != "select", !name.isEmpty { parts.append(name) }
                if let placeholder = element.placeholder, !placeholder.isEmpty, !parts.contains(placeholder) {
                    parts.append(parts.isEmpty ? placeholder : "(\(placeholder))")
                }
                name = parts.joined(separator: " ")
            }
            name = String(name.replacingOccurrences(of: "\n", with: " ").prefix(100))
            let loopIndex = page.count + 1
            var options: [String]?
            if element.tag == "select" {
                let list = element.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                options = list.isEmpty ? nil : Array(list.prefix(8))
                name = ""
            }
            page.append(PageElement(index: loopIndex, role: role(for: element.tag), text: name,
                                    href: element.href.map { String($0.prefix(120)) }, inViewport: true, options: options))
            map[loopIndex] = element.index
            raw.append(element)
        }
        let id = stateID(url: state.url, elements: source)
        let shownTitle = [title, state.title].compactMap { $0 }.first { !$0.isEmpty } ?? state.url
        return BrowserUseSnapshot(page: BrowserAgentPage(url: state.url, title: shownTitle, state: id, elements: page),
                                  realIndex: map, raw: raw)
    }

    static let fieldTags: Set<String> = ["input", "textarea", "select"]

    public static func role(for tag: String) -> String {
        switch tag {
        case "a": "link"
        case "button": "button"
        case "input", "textarea": "textbox"
        case "select": "select"
        default: tag
        }
    }

    // MARK: Ops

    /// Words on a control that sends the typed text on (typing here has no Enter key).
    static let submitWords = ["search", "go", "find", "submit", "continue", "next", "sign in", "log in", "login", "apply", "send"]

    /// The plan for one loop action on the page it was chosen on. `state` freshness is checked by
    /// the backend, which looks again right before it acts.
    public static func call(for action: BrowserAgentAction, snapshot: BrowserUseSnapshot) throws -> BrowserUseCall {
        func real(_ index: Int) throws -> Int {
            guard let value = snapshot.real(index) else { throw BridgeError(code: BridgeError.staleElements) }
            return value
        }
        switch action {
        case .open(let url):
            return .tool(BrowserUseTool.navigate, ["url": .string(url)])
        case .wait(let ms):
            return .pause(milliseconds: min(max(ms, 0), BrowserAgentOp.maxWait))
        case .command(let command):
            switch command {
            case .clickIndex(let index, _):
                return .tool(BrowserUseTool.click, ["index": .number(Double(try real(index)))])
            case .typeIndex(let index, let text, let submit, _):
                return .type(realIndex: try real(index), text: text, submit: submit)
            case .selectOption:
                return .unsupported("This browser can't pick from a dropdown. Click the dropdown and the option instead, or ask Tony.")
            case .scroll(.up, _):
                return .tool(BrowserUseTool.scroll, ["direction": .string("up")])
            case .scroll(.down, _):
                return .tool(BrowserUseTool.scroll, ["direction": .string("down")])
            case .scroll(.toElement(let index), _):
                _ = try real(index)
                return .none
            case .back:
                return .tool(BrowserUseTool.goBack, [:])
            case .forward:
                return .unsupported("This browser has no forward button. Open the page address instead.")
            case .switchTab(let match):
                return .switchTab(match)
            case .closeTab(let match):
                return .closeTab(match)
            case .extract(let limit):
                return .extract(limit: limit)
            }
        }
    }

    /// The real index of the control that submits what was typed into `typed`: the next button or
    /// input after it whose label says search, go, submit, sign in and the like.
    public static func submitControl(after typed: Int, in elements: [BrowserUseElement]) -> Int? {
        guard let position = elements.firstIndex(where: { $0.index == typed }) else { return nil }
        for element in elements[(position + 1)...] {
            guard element.tag == "button" || element.tag == "input" else { continue }
            let label = BrowserAgentSafety.normalized(element.text + " " + (element.placeholder ?? ""))
            if submitWords.contains(where: { BrowserAgentSafety.has(label, $0) }) { return element.index }
        }
        return nil
    }

    /// A password, card or one-time-code input that the state list can't name (browser-use does not
    /// report the input type). The backend asks the page; this decides with the answer.
    public static func isUnnamedField(_ element: BrowserUseElement?) -> Bool {
        guard let element, element.tag == "input" else { return false }
        return element.text.trimmingCharacters(in: .whitespaces).isEmpty && (element.placeholder ?? "").isEmpty
    }

    /// The selector that finds sensitive inputs on a page.
    public static let sensitiveSelector = "input[type=\"password\"], input[autocomplete^=\"cc-\"], input[autocomplete=\"one-time-code\"]"

    /// A tab to switch to, by the title or address it contains (browser-use's own tab titles are
    /// often just the address).
    public static func tabID(matching match: BrowserCommand.TabMatch?, in listing: String) -> String? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(listing.utf8)), case .array(let tabs) = value else { return nil }
        struct Tab { let id: String, title: String, url: String }
        let all = tabs.compactMap { tab -> Tab? in
            guard let id = tab["tab_id"]?.stringValue else { return nil }
            return Tab(id: id, title: tab["title"]?.stringValue ?? "", url: tab["url"]?.stringValue ?? "")
        }
        switch match {
        case nil: return nil
        case .id(let number)?: return all.indices.contains(number - 1) ? all[number - 1].id : nil
        case .title(let wanted)?:
            let needle = wanted.lowercased()
            return all.first { $0.title.lowercased() == needle }?.id
                ?? all.first { $0.title.lowercased().contains(needle) }?.id
                ?? all.first { $0.url.lowercased().contains(needle) }?.id
        }
    }

    // MARK: Page text

    /// `<title>` text from `browser_get_html` with selector "title".
    public static func title(fromHTML html: String) -> String? {
        guard let start = html.range(of: "<title", options: .caseInsensitive),
              let open = html.range(of: ">", range: start.upperBound..<html.endIndex),
              let close = html.range(of: "</title>", options: .caseInsensitive, range: open.upperBound..<html.endIndex) else { return nil }
        let text = decodeEntities(String(html[open.upperBound..<close.lowerBound])).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Readable text from page HTML: no scripts, styles or markup, one block per line.
    public static func plainText(fromHTML html: String, limit: Int) -> String {
        var text = html
        for tag in ["script", "style", "svg", "noscript", "head"] {
            text = replace("<\(tag)\\b[^>]*>.*?</\(tag)>", in: text, with: " ")
        }
        text = replace("<!--.*?-->", in: text, with: " ")
        text = replace("<(br|/p|/div|/li|/tr|/h[1-6]|/section|/article|/ul|/ol|/table)\\b[^>]*>", in: text, with: "\n")
        text = replace("<[^>]+>", in: text, with: " ")
        text = decodeEntities(text)
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        }.filter { !$0.isEmpty }
        return PageText.truncate(lines.joined(separator: "\n"), to: limit)
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }

    // MARK: Results

    /// browser-use reports some failures as ordinary text. The stale-page ones become a stale error
    /// (nothing was touched), the rest a failure the brain reads.
    public static func failure(in result: MCPToolResult, tool: String) -> BridgeError? {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: "Element with index \\d+ not found", options: .regularExpression) != nil {
            return BridgeError(code: BridgeError.staleElements)
        }
        if result.isError || text.hasPrefix("Error:") {
            return BridgeError(code: "failed", message: String(text.replacingOccurrences(of: "Error: ", with: "").prefix(200)))
        }
        if text.hasPrefix("Provide either index") { return BridgeError(code: "failed", message: text) }
        return nil
    }
}

// MARK: Allowed domains

/// The "Allowed domains" setting: a comma or line separated list. Empty means no limit.
public enum BrowserUseAllowlist {
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" || $0 == " " }).compactMap { raw -> String? in
            var item = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if let scheme = item.range(of: "://") { item = String(item[scheme.upperBound...]) }
            if let slash = item.firstIndex(of: "/") { item = String(item[..<slash]) }
            guard !item.isEmpty, seen.insert(item).inserted else { return nil }
            return item
        }
    }

    /// `example.com` allows itself and its subdomains; `*.example.com` the same.
    public static func allows(url: String, domains: [String]) -> Bool {
        guard !domains.isEmpty else { return true }
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        return domains.contains { domain in
            let bare = domain.hasPrefix("*.") ? String(domain.dropFirst(2)) : domain
            return host == bare || host.hasSuffix("." + bare)
        }
    }

    /// The value for browser-use's own `BROWSER_USE_ALLOWED_DOMAINS`.
    public static func environmentValue(_ domains: [String]) -> String? {
        domains.isEmpty ? nil : domains.joined(separator: ",")
    }
}

// MARK: Config

/// The config.json Zeus hands browser-use (via BROWSER_USE_CONFIG_PATH), so its own
/// ~/.config/browseruse is never read or written. One browser profile, no LLM key.
public enum BrowserUseConfig {
    public static func json(profileDirectory: String, downloadsDirectory: String, headless: Bool) -> Data {
        func entry(_ id: String, _ fields: [String: JSONValue]) -> JSONValue {
            var object = fields
            object["id"] = .string(id)
            object["default"] = .bool(true)
            object["created_at"] = .string("2026-01-01T00:00:00")
            return .object(object)
        }
        let root: JSONValue = .object([
            "browser_profile": .object(["zeus": entry("zeus", [
                "headless": .bool(headless),
                "user_data_dir": .string(profileDirectory),
                "downloads_path": .string(downloadsDirectory),
            ])]),
            // No api_key on purpose: browser-use then starts no LLM, and Zeus never calls its AI tools.
            "llm": .object(["zeus": entry("zeus", ["model": .string("none")])]),
            "agent": .object(["zeus": entry("zeus", [:])]),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(root)) ?? Data()
    }
}

// MARK: Backend choice

public enum BrowserAgentBackendKind: String, Equatable, Sendable {
    /// Tony's own Chrome through the ZEUS extension.
    case chrome
    /// browser-use's own Chromium, driven through its MCP browser_* tools.
    case separate

    /// `zeus browse --separate` wins; otherwise the Settings choice (anything unknown is Chrome).
    public static func resolve(setting: String, forceSeparate: Bool = false) -> BrowserAgentBackendKind {
        if forceSeparate { return .separate }
        return setting.lowercased().contains("separate") || setting.lowercased().contains("browser-use") ? .separate : .chrome
    }
}

// MARK: Launch environment

extension BrowserUseConfig {
    /// The pinned browser-use release the MCP tools below were recorded from. Another release may
    /// name or shape its tools differently, so Zeus never runs an unpinned one.
    public static let pinnedVersion = "0.13.14"

    /// The environment for `uvx browser-use --mcp`: telemetry off, no version or cloud pings, no AI
    /// provider keys passed through (Zeus's brain decides every step; browser-use must not call a
    /// model), its config and profile under Zeus's folder, and the allowlist when Tony set one.
    public static func environment(base: [String: String], searchPath: [String], configPath: String, configDirectory: String,
                                   allowedDomains: [String], headless: Bool? = nil) -> [String: String] {
        var environment = base.filter { key, _ in
            let upper = key.uppercased()
            return !(upper.hasSuffix("_API_KEY") || upper.hasSuffix("_API_TOKEN") || upper.hasSuffix("_AUTH_TOKEN")
                || upper.hasPrefix("BROWSER_USE_"))
        }
        environment["PATH"] = searchPath.joined(separator: ":")
        environment["ANONYMIZED_TELEMETRY"] = "False"
        environment["BROWSER_USE_CLOUD_SYNC"] = "false"
        environment["BROWSER_USE_VERSION_CHECK"] = "false"
        environment["BROWSER_USE_CLOUD_HINTS"] = "false"
        environment["BROWSER_USE_LOGGING_LEVEL"] = "critical"
        environment["BROWSER_USE_CONFIG_PATH"] = configPath
        environment["BROWSER_USE_CONFIG_DIR"] = configDirectory
        if let value = BrowserUseAllowlist.environmentValue(allowedDomains) { environment["BROWSER_USE_ALLOWED_DOMAINS"] = value }
        if let headless { environment["BROWSER_USE_HEADLESS"] = headless ? "true" : "false" }
        return environment
    }

    /// `uvx browser-use@<version> <arguments>`
    public static func uvxArguments(_ arguments: [String]) -> [String] { ["browser-use@" + pinnedVersion] + arguments }
}
