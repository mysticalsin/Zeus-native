import Foundation

// Indexed browser actions. The idea comes from browser-use (MIT, Gregor Zunic): the page lists
// its interactive elements with numbers, the model acts by number, and a page-state id makes a
// number from an older list fail instead of hitting the wrong thing. No browser-use code is used.

/// One interactive element of the active tab, numbered for the current page state.
public struct PageElement: Codable, Equatable, Sendable {
    /// 1-based, stable while the page state stays the same.
    public let index: Int
    /// "link", "button", "textbox", "select", "checkbox", or the element's own ARIA role.
    public let role: String
    /// Visible text or accessible label, trimmed.
    public let text: String
    /// Links only: a short form of the target (path on the same site, host and path elsewhere).
    public let href: String?
    /// Whether any of it is inside the visible part of the page right now.
    public let inViewport: Bool
    /// Selects only: the first few option labels.
    public let options: [String]?

    public init(index: Int, role: String, text: String, href: String? = nil, inViewport: Bool = true, options: [String]? = nil) {
        self.index = index
        self.role = role
        self.text = text
        self.href = href
        self.inViewport = inViewport
        self.options = options
    }

    /// One line of the list the brain sees, e.g. `[3] link "Pricing" -> /pricing`.
    public var promptLine: String {
        var line = "[\(index)] \(role)"
        if !text.isEmpty { line += " \"\(text)\"" }
        if let href, !href.isEmpty { line += " -> \(href)" }
        if let options, !options.isEmpty { line += " options: " + options.joined(separator: " | ") }
        if !inViewport { line += " (off screen)" }
        return line
    }
}

/// Page text handed to the brain.
public enum PageText {
    public static let defaultExtractLimit = 4_000
    public static let extractLimits = 200...20_000

    /// At most `limit` characters. A cut ends with "…", at a word break when one is close.
    public static func truncate(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        guard limit > 1 else { return "…" }
        var cut = String(text.prefix(limit - 1))
        if let space = cut.lastIndex(where: \.isWhitespace),
           cut.distance(from: cut.startIndex, to: space) >= limit * 4 / 5 {
            cut = String(cut[..<space])
        }
        while cut.last?.isWhitespace == true { cut.removeLast() }
        return cut + "…"
    }

    /// Visible words from HTML. Scripts and tags are dropped so a read is text, not a picture of the page.
    public static func plain(_ html: String) -> String {
        var text = html
        for pattern in ["(?is)<script[^>]*>.*?</script>", "(?is)<style[^>]*>.*?</style>"] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, mark) in entities { text = text.replacingOccurrences(of: entity, with: mark) }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A typed `browser.*` indexed action, read from an `[ACTION:{…}]` tag and turned into an
/// extension request.
public enum BrowserCommand: Equatable, Sendable {
    public enum Scroll: Equatable, Sendable {
        case up(pages: Double)
        case down(pages: Double)
        /// Brings element N into view.
        case toElement(index: Int)
    }

    public enum TabMatch: Equatable, Sendable {
        case id(Int)
        /// Case-insensitive: exact title, then title containing it, then URL containing it.
        case title(String)
    }

    case clickIndex(index: Int, state: String?)
    case typeIndex(index: Int, text: String, submit: Bool, state: String?)
    case selectOption(index: Int, option: String, state: String?)
    case scroll(Scroll, state: String?)
    case back
    case forward
    case switchTab(TabMatch)
    /// nil closes the active tab.
    case closeTab(TabMatch?)
    case extract(limit: Int)

    public init?(_ action: ZeusAction) {
        let payload = action.payload
        let state = payload["state"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        let index = Self.index(payload["index"])
        switch action.kind {
        case .browserClickIndex:
            guard let index else { return nil }
            self = .clickIndex(index: index, state: state)
        case .browserTypeIndex:
            guard let index, let text = payload["text"]?.stringValue else { return nil }
            self = .typeIndex(index: index, text: text, submit: payload["submit"]?.boolValue ?? false, state: state)
        case .browserSelect:
            guard let index, let option = payload["option"]?.stringValue, !option.isEmpty else { return nil }
            self = .selectOption(index: index, option: option, state: state)
        case .browserScroll:
            if payload["index"] != nil {
                guard let index else { return nil }
                self = .scroll(.toElement(index: index), state: state)
            } else {
                let pages = min(max(payload["pages"]?.numberValue ?? 1, 0.1), 10)
                switch payload["direction"]?.stringValue?.lowercased() ?? "down" {
                case "up": self = .scroll(.up(pages: pages), state: nil)
                case "down": self = .scroll(.down(pages: pages), state: nil)
                default: return nil
                }
            }
        case .browserBack:
            self = .back
        case .browserForward:
            self = .forward
        case .browserSwitchTab:
            guard let match = Self.tabMatch(payload) else { return nil }
            self = .switchTab(match)
        case .browserCloseTab:
            if payload["tabId"] != nil || payload["title"] != nil {
                guard let match = Self.tabMatch(payload) else { return nil }
                self = .closeTab(match)
            } else {
                self = .closeTab(nil)
            }
        case .browserExtract:
            let limit = payload["limit"]?.numberValue.map { Int($0) } ?? PageText.defaultExtractLimit
            self = .extract(limit: min(max(limit, PageText.extractLimits.lowerBound), PageText.extractLimits.upperBound))
        default:
            return nil
        }
    }

    /// The action tag for this command (`init?(_:)` reads it back).
    public var action: ZeusAction {
        var payload: [String: JSONValue] = [:]
        func put(_ state: String?) { if let state { payload["state"] = .string(state) } }
        let kind: ZeusAction.Kind
        switch self {
        case .clickIndex(let index, let state):
            kind = .browserClickIndex
            payload["index"] = .number(Double(index))
            put(state)
        case .typeIndex(let index, let text, let submit, let state):
            kind = .browserTypeIndex
            payload["index"] = .number(Double(index))
            payload["text"] = .string(text)
            payload["submit"] = .bool(submit)
            put(state)
        case .selectOption(let index, let option, let state):
            kind = .browserSelect
            payload["index"] = .number(Double(index))
            payload["option"] = .string(option)
            put(state)
        case .scroll(let scroll, let state):
            kind = .browserScroll
            switch scroll {
            case .up(let pages):
                payload["direction"] = .string("up")
                payload["pages"] = .number(pages)
            case .down(let pages):
                payload["direction"] = .string("down")
                payload["pages"] = .number(pages)
            case .toElement(let index):
                payload["index"] = .number(Double(index))
                put(state)
            }
        case .back:
            kind = .browserBack
        case .forward:
            kind = .browserForward
        case .switchTab(let match):
            kind = .browserSwitchTab
            payload.merge(match.params) { $1 }
        case .closeTab(let match):
            kind = .browserCloseTab
            if let match { payload.merge(match.params) { $1 } }
        case .extract(let limit):
            kind = .browserExtract
            payload["limit"] = .number(Double(limit))
        }
        payload["type"] = .string(kind.rawValue)
        return ZeusAction(kind: kind, payload: payload)
    }

    /// The extension request type (handled in extension/src/sw.ts).
    public var bridgeType: String {
        switch self {
        case .clickIndex: "page.click_index"
        case .typeIndex: "page.type_index"
        case .selectOption: "page.select"
        case .scroll: "page.scroll"
        case .back: "tab.back"
        case .forward: "tab.forward"
        case .switchTab: "tab.switch"
        case .closeTab: "tab.close"
        case .extract: "page.extract"
        }
    }

    public var bridgeParams: [String: JSONValue] {
        var params = action.payload
        params["type"] = nil
        return params
    }

    /// Changes a page, so it goes through the per-site consent. Scrolling, switching tabs and
    /// reading don't change anything on a site.
    public var changesPage: Bool {
        switch self {
        case .clickIndex, .typeIndex, .selectOption, .back, .forward, .closeTab: true
        case .scroll, .switchTab, .extract: false
        }
    }

    /// What the consent card says. `label` is the element's or tab's text, when known.
    public func summary(label: String?) -> String {
        let named = label.flatMap { $0.isEmpty ? nil : "“\($0)”" }
        switch self {
        case .clickIndex(let index, _):
            return "Click \(named ?? "item \(index)")"
        case .typeIndex(let index, let text, let submit, _):
            return "Type “\(text)” into \(named ?? "item \(index)")" + (submit ? " and submit" : "")
        case .selectOption(let index, let option, _):
            return "Choose “\(option)” in \(named ?? "item \(index)")"
        case .scroll(.up, _):
            return "Scroll up"
        case .scroll(.down, _):
            return "Scroll down"
        case .scroll(.toElement(let index), _):
            return "Scroll to \(named ?? "item \(index)")"
        case .back:
            return "Go back"
        case .forward:
            return "Go forward"
        case .switchTab(let match):
            return "Switch to \(named ?? match.description)"
        case .closeTab(let match):
            return "Close \(named ?? match?.description ?? "this tab")"
        case .extract:
            return "Read this page"
        }
    }

    /// The element number this command acts on, if any.
    public var elementIndex: Int? {
        switch self {
        case .clickIndex(let index, _), .typeIndex(let index, _, _, _), .selectOption(let index, _, _),
             .scroll(.toElement(let index), _):
            index
        default:
            nil
        }
    }

    static func index(_ value: JSONValue?) -> Int? {
        guard let number = value?.numberValue, number >= 1, number.rounded() == number, number < 100_000 else { return nil }
        return Int(number)
    }

    static func tabMatch(_ payload: [String: JSONValue]) -> TabMatch? {
        if let id = payload["tabId"]?.numberValue, id.rounded() == id, id >= 0 { return .id(Int(id)) }
        if let title = payload["title"]?.stringValue?.trimmingCharacters(in: .whitespaces), !title.isEmpty { return .title(title) }
        return nil
    }
}

extension BrowserCommand.TabMatch: CustomStringConvertible {
    /// Extension request parameters (`tab.find`, `tab.switch`, `tab.close`).
    public var params: [String: JSONValue] {
        switch self {
        case .id(let id): ["tabId": .number(Double(id))]
        case .title(let title): ["title": .string(title)]
        }
    }

    public var description: String {
        switch self {
        case .id(let id): "tab \(id)"
        case .title(let title): "the “\(title)” tab"
        }
    }
}
