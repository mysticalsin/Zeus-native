import Foundation

/// Every AI backend ZEUS can route a voice turn to.
public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case claudeCLI
    case codexCLI
    case geminiCLI
    case cursorAgent
    case ollama
    case dust
    case anthropicAPI
    case openAIAPI
}

public struct ProviderCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let images = ProviderCapabilities(rawValue: 1 << 0)
    public static let streaming = ProviderCapabilities(rawValue: 1 << 1)
    public static let browserTools = ProviderCapabilities(rawValue: 1 << 2)
    public static let mcp = ProviderCapabilities(rawValue: 1 << 3)
}

public enum ProviderHealth: Equatable, Sendable {
    case ready(version: String?)
    case notInstalled
    case notLoggedIn(hint: String)
    case outdated(found: String, minimum: String)
    case unreachable(reason: String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// One display, captured at hotkey-down. JPEG, longest side 1280 px.
public struct ScreenShot: Sendable {
    public let jpegData: Data
    /// e.g. "screen 1 of 2 — cursor is on this screen (primary focus)"
    public let label: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// The display's frame in AppKit points (bottom-left origin), used to map POINT tags back.
    public let displayFrame: CGRect

    public init(jpegData: Data, label: String, pixelWidth: Int, pixelHeight: Int, displayFrame: CGRect) {
        self.jpegData = jpegData
        self.label = label
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.displayFrame = displayFrame
    }
}

/// The active Chrome tab, as reported by the ZEUS extension.
/// The active Chrome tab, read through the ZEUS extension when Chrome is in front.
public struct TabContext: Codable, Equatable, Sendable {
    public let url: String
    public let title: String
    public let selection: String?
    /// Visible page text, trimmed to a few thousand characters.
    public let text: String?
    /// Labels of visible links and buttons, for `browser.click`.
    public let controls: [String]?
    /// The page-state id of `elements`; indexed actions carry it so a changed page is caught.
    public let elementsState: String?
    /// Numbered interactive elements (`page.elements`), for the indexed `browser.*` actions.
    public let elements: [PageElement]?
    /// Main text from an earlier `browser.extract` on this page, already truncated.
    public let extract: String?

    public init(url: String, title: String, selection: String? = nil, text: String? = nil, controls: [String]? = nil,
                elementsState: String? = nil, elements: [PageElement]? = nil, extract: String? = nil) {
        self.url = url
        self.title = title
        self.selection = selection
        self.text = text
        self.controls = controls
        self.elementsState = elementsState
        self.elements = elements
        self.extract = extract
    }

    public func with(extract: String?) -> TabContext {
        TabContext(url: url, title: title, selection: selection, text: text, controls: controls,
                   elementsState: elementsState, elements: elements, extract: extract)
    }
}

/// One past exchange. History is text only: no screenshots, tags stripped.
public struct Exchange: Codable, Equatable, Sendable {
    public let user: String
    public let assistant: String

    public init(user: String, assistant: String) {
        self.user = user
        self.assistant = assistant
    }
}

public struct BrainRequest: Sendable {
    public let turn: UUID
    public let transcript: String
    public let screenshots: [ScreenShot]
    public let axSummary: String?
    public let activeTab: TabContext?
    public let history: [Exchange]
    public let systemPrompt: String
    /// More thinking for this turn (`zeus --deep`).
    public let deep: Bool

    public init(
        turn: UUID = UUID(),
        transcript: String,
        screenshots: [ScreenShot] = [],
        axSummary: String? = nil,
        activeTab: TabContext? = nil,
        history: [Exchange] = [],
        systemPrompt: String,
        deep: Bool = false
    ) {
        self.turn = turn
        self.transcript = transcript
        self.screenshots = screenshots
        self.axSummary = axSummary
        self.activeTab = activeTab
        self.history = history
        self.systemPrompt = systemPrompt
        self.deep = deep
    }

    /// A copy with one field changed. Used when a turn retries deeper, or a racer needs its own id so cancelling the loser leaves the winner running.
    public func with(turn: UUID? = nil, transcript: String? = nil, screenshots: [ScreenShot]? = nil,
                     systemPrompt: String? = nil, deep: Bool? = nil) -> BrainRequest {
        BrainRequest(turn: turn ?? self.turn, transcript: transcript ?? self.transcript,
                     screenshots: screenshots ?? self.screenshots, axSummary: axSummary, activeTab: activeTab,
                     history: history, systemPrompt: systemPrompt ?? self.systemPrompt, deep: deep ?? self.deep)
    }
}

public struct Usage: Equatable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum BrainEvent: Equatable, Sendable {
    case textDelta(String)
    /// A complete sentence, sent to TTS right away.
    case sentence(String)
    case tag(ZeusTag)
    /// Tool use in progress, e.g. "reading github.com".
    case progress(String)
    case done(Usage?)
}

public protocol BrainProvider: Sendable {
    var id: ProviderID { get }
    var capabilities: ProviderCapabilities { get }
    func healthCheck() async -> ProviderHealth
    func send(_ request: BrainRequest) -> AsyncThrowingStream<BrainEvent, Error>
    func cancel(turn: UUID) async
}
