import Foundation
import Testing
@testable import ZeusCore

/// Responses recorded from the real `uvx browser-use@0.13.14 --mcp` (Tests/Fixtures/browseruse).
enum BrowserUseFixture {
    struct Entry { let outgoing: Bool; let message: JSONValue }

    static func load(_ name: String) throws -> [Entry] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/browseruse/\(name).json")
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        return (value.arrayValue ?? []).map { Entry(outgoing: $0["dir"]?.stringValue == "->", message: $0["msg"] ?? .null) }
    }

    /// The nth recorded answer to `tools/call` of `tool`.
    static func toolResult(_ fixture: String, _ tool: String, nth: Int = 0, arguments: [String: JSONValue]? = nil) throws -> MCPToolResult {
        let entries = try load(fixture)
        let requests = entries.filter {
            $0.outgoing && $0.message["method"]?.stringValue == "tools/call" && $0.message["params"]?["name"]?.stringValue == tool
                && (arguments == nil || $0.message["params"]?["arguments"] == .object(arguments!))
        }
        let request = try #require(requests.indices.contains(nth) ? requests[nth] : nil)
        let id = try #require(request.message["id"]?.numberValue)
        let response = try #require(entries.first { !$0.outgoing && $0.message["id"]?.numberValue == id })
        return try #require(MCPToolResult(result: response.message["result"]))
    }

    static func state(_ fixture: String, nth: Int = 0) throws -> BrowserUseState {
        try #require(BrowserUseState.parse(try toolResult(fixture, BrowserUseTool.getState, nth: nth).text))
    }
}

@Suite("browser-use MCP messages")
struct BrowserUseProtocolTests {
    @Test func requestsAreOneSortedLineEndingInNewline() throws {
        let data = MCPCodec.request(id: 7, method: "tools/call", params: MCPCodec.callParams(name: "browser_navigate", arguments: ["url": .string("https://example.com")]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text == #"{"id":7,"jsonrpc":"2.0","method":"tools/call","params":{"arguments":{"url":"https://example.com"},"name":"browser_navigate"}}"# + "\n")
        #expect(text.filter { $0 == "\n" }.count == 1)
    }

    @Test func notificationsCarryNoID() {
        let text = String(decoding: MCPCodec.notification(method: "notifications/initialized"), as: UTF8.self)
        #expect(text == #"{"jsonrpc":"2.0","method":"notifications/initialized"}"# + "\n")
    }

    @Test func initializeAsksForTheProtocolRevisionAndNamesZeus() throws {
        let params = MCPCodec.initializeParams()
        #expect(params["protocolVersion"]?.stringValue == "2025-06-18")
        #expect(params["clientInfo"]?["name"]?.stringValue == "zeus")
    }

    @Test func decodesResponsesErrorsNotificationsAndServerRequests() throws {
        #expect(try MCPCodec.decode(Data(#"{"jsonrpc":"2.0","id":3,"result":{"ok":true}}"#.utf8))
            == .response(id: 3, result: .object(["ok": .bool(true)]), error: nil))
        #expect(try MCPCodec.decode(Data(#"{"jsonrpc":"2.0","id":4,"error":{"code":-32602,"message":"bad"}}"#.utf8))
            == .response(id: 4, result: nil, error: MCPError(code: -32_602, message: "bad")))
        #expect(try MCPCodec.decode(Data(#"{"jsonrpc":"2.0","method":"notifications/message","params":{"level":"info"}}"#.utf8))
            == .notification(method: "notifications/message", params: .object(["level": .string("info")])))
        #expect(try MCPCodec.decode(Data(#"{"jsonrpc":"2.0","id":"p1","method":"ping"}"#.utf8))
            == .request(id: .string("p1"), method: "ping", params: nil))
        #expect(throws: MCPCodecError.notJSON) { try MCPCodec.decode(Data("Traceback (most recent call last)".utf8)) }
        #expect(throws: MCPCodecError.notAMessage) { try MCPCodec.decode(Data(#"{"jsonrpc":"2.0"}"#.utf8)) }
    }

    @Test func responseIDsOutsideIntegerRangeOrWithFractionsAreRejectedWithoutTrapping() {
        for id in ["1e100", "-1e100", "9223372036854775808", "-9223372036854777856", "1.5",
                   #""NaN""#, #""Infinity""#, #""-Infinity""#] {
            let line = Data("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"result\":{}}".utf8)
            #expect(throws: MCPCodecError.notAMessage) { try MCPCodec.decode(line) }
        }
    }

    @Test func errorCodesOutsideIntegerRangeOrWithFractionsAreRejectedWithoutTrapping() {
        for code in ["1e100", "-1e100", "9223372036854775808", "-9223372036854777856", "1.5", "-0.5",
                     #""NaN""#, #""Infinity""#, #""-Infinity""#] {
            let line = Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":\(code),\"message\":\"bad\"}}".utf8)
            #expect(throws: MCPCodecError.notAMessage) { try MCPCodec.decode(line) }
        }
    }

    @Test func exactlyRepresentableIntegerBoundariesAndDefaultErrorCodeKeepTheirValues() throws {
        let upper = try #require(Int(exactly: Double(Int.max).nextDown))
        for number in [Int.min, -32_602, 0, 42, upper] {
            let line = Data("{\"jsonrpc\":\"2.0\",\"id\":\(number),\"error\":{\"code\":\(number),\"message\":\"bad\"}}".utf8)
            #expect(try MCPCodec.decode(line) == .response(id: number, result: nil,
                                                         error: MCPError(code: number, message: "bad")))
        }
        #expect(try MCPCodec.decode(Data(#"{"jsonrpc":"2.0","id":1,"error":{"message":"missing code"}}"#.utf8))
                == .response(id: 1, result: nil, error: MCPError(code: -32_603, message: "missing code")))
    }

    @Test func everyRecordedLineDecodes() throws {
        for name in ["example-com", "form-page", "form-extras"] {
            for entry in try BrowserUseFixture.load(name) where !entry.outgoing {
                let line = try JSONEncoder().encode(entry.message)
                _ = try MCPCodec.decode(line)
            }
        }
    }

    @Test func recordedHandshakeNamesTheServerAndItsTools() throws {
        let entries = try BrowserUseFixture.load("example-com")
        let initialize = try #require(entries.first { !$0.outgoing && $0.message["id"]?.numberValue == 1 })
        let result = try #require(initialize.message["result"])
        #expect(result["serverInfo"]?["name"]?.stringValue == "browser-use")
        #expect(result["serverInfo"]?["version"]?.stringValue == "0.13.14")
        #expect(result["protocolVersion"]?.stringValue == "2025-06-18")
        let list = try #require(entries.first { !$0.outgoing && $0.message["id"]?.numberValue == 2 }?.message["result"])
        let tools = MCPToolInfo.parse(list)
        #expect(tools.map(\.name) == ["browser_navigate", "browser_click", "browser_type", "browser_get_state", "browser_extract_content",
                                       "browser_get_html", "browser_screenshot", "browser_scroll", "browser_go_back", "browser_list_tabs",
                                       "browser_switch_tab", "browser_close_tab", "retry_with_browser_use_agent", "browser_list_sessions",
                                       "browser_close_session", "browser_close_all"])
        for name in BrowserUseTool.used { #expect(tools.contains { $0.name == name }, "missing \(name)") }
        #expect(tools.first { $0.name == "browser_type" }?.required == ["index", "text"])
        #expect(tools.first { $0.name == "browser_navigate" }?.required == ["url"])
        #expect(tools.first { $0.name == "browser_switch_tab" }?.properties == ["tab_id"])
    }

    @Test func toolResultsJoinTextAndCountImages() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"content":[{"type":"text","text":"a"},{"type":"image","data":"x","mimeType":"image/png"},{"type":"text","text":"b"}],"isError":true}"#.utf8))
        let result = try #require(MCPToolResult(result: value))
        #expect(result == MCPToolResult(text: "a\nb", imageCount: 1, isError: true))
        #expect(MCPToolResult(result: .object([:])) == nil)
    }

    @Test func recordedToolOutputsKeepTheirShape() throws {
        #expect(try BrowserUseFixture.toolResult("example-com", BrowserUseTool.navigate).text == "Navigated to: https://example.com")
        #expect(try BrowserUseFixture.toolResult("example-com", BrowserUseTool.scroll).text == "Scrolled down")
        #expect(try BrowserUseFixture.toolResult("example-com", BrowserUseTool.goBack).text == "Navigated back")
        #expect(try BrowserUseFixture.toolResult("form-extras", BrowserUseTool.type).text == "Typed 'hello zeus' into element 4")
        let unknown = try BrowserUseFixture.toolResult("example-com", "browser_nonexistent")
        #expect(unknown.isError && unknown.text == "Error: Unknown tool: browser_nonexistent")
        // The AI-backed tool needs a key inside browser-use, so Zeus never calls it.
        let extract = try BrowserUseFixture.toolResult("example-com", BrowserUseTool.extractContent)
        #expect(extract.text == "Error: LLM not initialized (set OPENAI_API_KEY)")
    }

    @Test func plainTextFailuresBecomeBridgeErrors() throws {
        let missing = try BrowserUseFixture.toolResult("example-com", BrowserUseTool.click, nth: 0)
        #expect(missing.text == "Element with index 1 not found" && !missing.isError)
        #expect(BrowserUseMapping.failure(in: missing, tool: BrowserUseTool.click)?.code == BridgeError.staleElements)
        let unknown = try BrowserUseFixture.toolResult("example-com", "browser_nonexistent")
        #expect(BrowserUseMapping.failure(in: unknown, tool: "browser_nonexistent")?.code == "failed")
        let fine = try BrowserUseFixture.toolResult("example-com", BrowserUseTool.navigate)
        #expect(BrowserUseMapping.failure(in: fine, tool: BrowserUseTool.navigate) == nil)
    }
}

@Suite("browser-use page mapping")
struct BrowserUseMappingTests {
    @Test func exampleDotComBecomesOneNumberedLink() throws {
        let state = try BrowserUseFixture.state("example-com")
        #expect(state.url == "https://example.com/")
        let snapshot = BrowserUseMapping.snapshot(from: state, title: "Example Domain")
        #expect(snapshot.page.title == "Example Domain")
        #expect(snapshot.page.elements.count == 1)
        #expect(snapshot.page.elements[0].promptLine == "[1] link \"Learn more\" -> https://iana.org/help/example-domains")
        // browser-use's own index (35) stays behind the loop's 1.
        #expect(snapshot.real(1) == 35)
    }

    @Test func titleFallsBackToStateThenAddress() throws {
        let state = try BrowserUseFixture.state("example-com")
        #expect(BrowserUseMapping.snapshot(from: state, title: nil).page.title == "example.com")
        let bare = BrowserUseState(url: "https://x.test/", title: "")
        #expect(BrowserUseMapping.snapshot(from: bare).page.title == "https://x.test/")
    }

    @Test func formElementsAreRenumberedWithLabelsFolded() throws {
        let snapshot = BrowserUseMapping.snapshot(from: try BrowserUseFixture.state("form-page"), title: "Zeus Form")
        let lines = snapshot.page.elements.map(\.promptLine)
        #expect(lines == [
            "[1] textbox \"Email (you@example.com)\"",
            "[2] textbox \"Password\"",
            "[3] textbox \"Card number\"",
            "[4] select options: Red | Blue",
            "[5] textbox \"Search the site\"",
            "[6] button \"Pay now\"",
            "[7] link \"Next page\" -> /done.html",
        ])
        // Real indexes are sparse and unordered: 4, 5, 6, 7, 8, 9, 34.
        #expect((1...7).compactMap { snapshot.real($0) } == [4, 5, 6, 7, 8, 9, 34])
    }

    @Test func passwordAndCardFieldsAreRecognisedFromTheirLabels() throws {
        let page = BrowserUseMapping.snapshot(from: try BrowserUseFixture.state("form-page")).page
        #expect(BrowserAgentSafety.isSensitive(page.elements[1]))   // Password
        #expect(BrowserAgentSafety.isSensitive(page.elements[2]))   // Card number
        #expect(!BrowserAgentSafety.isSensitive(page.elements[0]))  // Email
        #expect(!BrowserAgentSafety.isSensitive(page.elements[4]))  // Search
    }

    @Test func stateIDIsStableAndFollowsTheElementList() throws {
        let state = try BrowserUseFixture.state("form-page")
        let a = BrowserUseMapping.stateID(url: state.url, elements: state.elements)
        #expect(a == BrowserUseMapping.stateID(url: state.url, elements: state.elements))
        #expect(a.hasPrefix("bu-") && a.count == 3 + 16)
        // The same list in a fresh parse (a second look at an unchanged page).
        let again = try BrowserUseFixture.state("form-page", nth: 1)
        #expect(BrowserUseMapping.stateID(url: again.url, elements: again.elements) == a)
        // A different address, label, link or browser-use index is a different page.
        #expect(BrowserUseMapping.stateID(url: state.url + "?x", elements: state.elements) != a)
        var renamed = state.elements
        renamed[8] = BrowserUseElement(index: 9, tag: "button", text: "Pay later")
        #expect(BrowserUseMapping.stateID(url: state.url, elements: renamed) != a)
        var moved = state.elements
        moved[8] = BrowserUseElement(index: 10, tag: "button", text: "Pay now")
        #expect(BrowserUseMapping.stateID(url: state.url, elements: moved) != a)
        // Pinned value: the id is the same in every run and every build (FNV-1a, not Hasher).
        #expect(BrowserUseMapping.stateID(url: "https://example.com/", elements: []) == "bu-" + "0469df34057e9db1")
    }

    @Test func snapshotCarriesTheStateIDForTheLoopsFreshnessCheck() throws {
        let state = try BrowserUseFixture.state("example-com")
        let snapshot = BrowserUseMapping.snapshot(from: state)
        #expect(snapshot.page.state == BrowserUseMapping.stateID(url: state.url, elements: state.elements))
        let command = try BrowserUseMapping.call(for: BrowserAgentLoop.action(for: .click(index: 1), on: snapshot.page).get()!, snapshot: snapshot)
        #expect(command == .tool("browser_click", ["index": .number(35)]))
    }

    @Test func titleAndTextComeOutOfPageHTML() throws {
        #expect(BrowserUseMapping.title(fromHTML: "<title>Zeus Form</title>") == "Zeus Form")
        #expect(BrowserUseMapping.title(fromHTML: "<TITLE data-x=1>A &amp; B </TITLE>") == "A & B")
        #expect(BrowserUseMapping.title(fromHTML: "No element found for selector: title") == nil)
        let html = try BrowserUseFixture.toolResult("example-com", BrowserUseTool.getHTML).text
        let text = BrowserUseMapping.plainText(fromHTML: html, limit: 4_000)
        #expect(text.contains("This domain is for use in documentation examples"))
        #expect(!text.contains("<") && !text.contains("color-scheme") && !text.contains("viewBox"))
        #expect(BrowserUseMapping.plainText(fromHTML: "<p>" + String(repeating: "word ", count: 200) + "</p>", limit: 50).count <= 50)
    }
}

@Suite("browser-use tool mapping")
struct BrowserUseToolMappingTests {
    private func snapshot() throws -> BrowserUseSnapshot { BrowserUseMapping.snapshot(from: try BrowserUseFixture.state("form-page")) }

    private func call(_ op: BrowserAgentOp, _ snapshot: BrowserUseSnapshot) throws -> BrowserUseCall? {
        guard let action = try BrowserAgentLoop.action(for: op, on: snapshot.page).get() else { return nil }
        return try BrowserUseMapping.call(for: action, snapshot: snapshot)
    }

    @Test func everyOpMapsToItsTool() throws {
        let s = try snapshot()
        #expect(try call(.click(index: 6), s) == .tool("browser_click", ["index": .number(9)]))
        #expect(try call(.type(index: 1, text: "ada", submit: false), s) == .type(realIndex: 4, text: "ada", submit: false))
        #expect(try call(.type(index: 5, text: "cables", submit: true), s) == .type(realIndex: 8, text: "cables", submit: true))
        #expect(try call(.scroll(.down), s) == .tool("browser_scroll", ["direction": .string("down")]))
        #expect(try call(.scroll(.up), s) == .tool("browser_scroll", ["direction": .string("up")]))
        #expect(try call(.scroll(.element(7)), s) == BrowserUseCall.none)
        #expect(try call(.back, s) == .tool("browser_go_back", [:]))
        #expect(try call(.open(url: "https://example.com"), s) == .tool("browser_navigate", ["url": .string("https://example.com")]))
        #expect(try call(.switchTab(title: "Docs"), s) == .switchTab(.title("Docs")))
        #expect(try call(.extract(question: "price"), s) == .extract(limit: PageText.defaultExtractLimit))
        #expect(try call(.wait(milliseconds: 400), s) == .pause(milliseconds: 400))
        #expect(try call(.wait(milliseconds: 99_999), s) == .pause(milliseconds: BrowserAgentOp.maxWait))
        #expect(try call(.done(answer: "x"), s) == nil)
    }

    @Test func whatBrowserUseCannotDoIsSaidPlainly() throws {
        let s = try snapshot()
        guard case .unsupported(let select)? = try call(.select(index: 4, option: "Blue"), s) else { Issue.record("select"); return }
        #expect(select.contains("dropdown"))
        guard case .unsupported(let forward)? = try call(.forward, s) else { Issue.record("forward"); return }
        #expect(forward.contains("forward"))
    }

    @Test func anIndexFromAnOlderListIsStale() throws {
        let s = try snapshot()
        let action = BrowserAgentAction.command(.clickIndex(index: 40, state: s.page.state))
        #expect(throws: BridgeError(code: BridgeError.staleElements)) { try BrowserUseMapping.call(for: action, snapshot: s) }
        #expect(throws: BridgeError(code: BridgeError.staleElements)) { try BrowserUseMapping.call(for: action, snapshot: .empty) }
    }

    @Test func theLoopRejectsAnIndexOutsideTheList() throws {
        let s = try snapshot()
        #expect(throws: BrowserAgentOp.ParseError.self) { try BrowserAgentLoop.action(for: .click(index: 8), on: s.page).get() }
    }

    @Test func submitClicksTheNextSendingControl() throws {
        let state = try BrowserUseFixture.state("form-page")
        // Search box (8) is followed by "Pay now"; that is not a sending word, so nothing is clicked by guess.
        #expect(BrowserUseMapping.submitControl(after: 8, in: state.elements) == nil)
        let search = state.elements + [BrowserUseElement(index: 50, tag: "button", text: "Search")]
        #expect(BrowserUseMapping.submitControl(after: 8, in: search) == 50)
        #expect(BrowserUseMapping.submitControl(after: 99, in: search) == nil)
        #expect(BrowserUseMapping.submitControl(after: 50, in: search) == nil)
    }

    @Test func tabsAreFoundByTitleThenAddress() throws {
        let listing = try BrowserUseFixture.toolResult("form-extras", BrowserUseTool.listTabs).text
        #expect(BrowserUseMapping.tabID(matching: .title("done.html"), in: listing) == "6A16")
        #expect(BrowserUseMapping.tabID(matching: .title("FORM"), in: listing) == "E2F1")
        #expect(BrowserUseMapping.tabID(matching: .title("nothing"), in: listing) == nil)
        #expect(BrowserUseMapping.tabID(matching: .id(2), in: listing) == "6A16")
        #expect(BrowserUseMapping.tabID(matching: nil, in: listing) == nil)
    }

    @Test func unnamedInputsNeedThePasswordCheck() {
        #expect(BrowserUseMapping.isUnnamedField(BrowserUseElement(index: 1, tag: "input", text: "")))
        #expect(!BrowserUseMapping.isUnnamedField(BrowserUseElement(index: 1, tag: "input", text: "", placeholder: "Search")))
        #expect(!BrowserUseMapping.isUnnamedField(BrowserUseElement(index: 1, tag: "button", text: "")))
        #expect(BrowserUseMapping.sensitiveSelector.contains("password") && BrowserUseMapping.sensitiveSelector.contains("cc-"))
    }
}

/// Zeus's approval rules on this backend: the loop decides, from the page the backend shows.
@Suite("browser-use approvals")
struct BrowserUseApprovalTests {
    private actor Run {
        var executed: [BrowserAgentAction] = []
        var approvals: [BrowserAgentApproval] = []
        let page: BrowserAgentPage
        let approve: Bool
        init(page: BrowserAgentPage, approve: Bool) { self.page = page; self.approve = approve }
        func record(_ action: BrowserAgentAction) { executed.append(action) }
        func ask(_ approval: BrowserAgentApproval) -> Bool { approvals.append(approval); return approve }
    }

    private func run(_ reply: String, approve: Bool = true) async throws -> (BrowserAgentOutcome, Run) {
        let page = BrowserUseMapping.snapshot(from: try BrowserUseFixture.state("form-page"), title: "Zeus Form").page
        let run = Run(page: page, approve: approve)
        let replies = ReplyBox([reply])
        var loop = BrowserAgentLoop(goal: "test", maxSteps: 5)
        let outcome = await loop.run(BrowserAgentPorts(
            think: { _ in await replies.next() },
            observe: { page },
            execute: { await run.record($0); return nil },
            approve: { await run.ask($0) }))
        return (outcome, run)
    }

    private actor ReplyBox {
        var replies: [String]
        init(_ replies: [String]) { self.replies = replies }
        func next() -> String { replies.isEmpty ? #"{"op":"done","answer":"ok"}"# : replies.removeFirst() }
    }

    @Test func payNowAlwaysAsksAndAYesRunsIt() async throws {
        let (outcome, run) = try await run(#"{"op":"click","index":6}"#)
        #expect(outcome == .done("ok"))
        let approvals = await run.approvals
        #expect(approvals.map(\.reason) == ["it touches payment"])
        let executed = await run.executed
        #expect(executed.count == 1)
    }

    @Test func aNoStopsBeforeAnythingIsTouched() async throws {
        let (outcome, run) = try await run(#"{"op":"click","index":6}"#, approve: false)
        guard case .declined = outcome else { Issue.record("expected declined, got \(outcome)"); return }
        #expect(await run.executed.isEmpty)
    }

    @Test func typingAndSubmittingAsks() async throws {
        let (_, run) = try await run(#"{"op":"type","index":5,"text":"usb-c","submit":true}"#)
        #expect(await run.approvals.map(\.reason) == ["it submits a form"])
    }

    @Test func plainTypingAndLinksDoNotAsk() async throws {
        let (_, typed) = try await run(#"{"op":"type","index":1,"text":"ada","submit":false}"#)
        #expect(await typed.approvals.isEmpty)
        #expect(await typed.executed.count == 1)
        let (_, link) = try await run(#"{"op":"click","index":7}"#)
        #expect(await link.approvals.isEmpty)
    }

    @Test func passwordAndCardFieldsAreRefusedBeforeAnyApproval() async throws {
        for index in [2, 3] {
            let (outcome, run) = try await run(#"{"op":"type","index":\#(index),"text":"hunter2"}"#)
            guard case .refused = outcome else { Issue.record("expected refused for \(index), got \(outcome)"); return }
            #expect(await run.executed.isEmpty)
            #expect(await run.approvals.isEmpty)
        }
    }
}

@Suite("browser-use setup and selection")
struct BrowserUseSettingsTests {
    @Test func allowedDomainsParseAndMatchSubdomains() {
        #expect(BrowserUseAllowlist.parse("Example.com, https://wikipedia.org/wiki/X\n*.docs.test;example.com") == ["example.com", "wikipedia.org", "*.docs.test"])
        #expect(BrowserUseAllowlist.parse("  ").isEmpty)
        let domains = ["example.com", "*.docs.test"]
        #expect(BrowserUseAllowlist.allows(url: "https://example.com/a", domains: domains))
        #expect(BrowserUseAllowlist.allows(url: "https://www.example.com/", domains: domains))
        #expect(BrowserUseAllowlist.allows(url: "https://a.docs.test/", domains: domains))
        #expect(!BrowserUseAllowlist.allows(url: "https://evil-example.com/", domains: domains))
        #expect(!BrowserUseAllowlist.allows(url: "https://example.com.evil.test/", domains: domains))
        #expect(BrowserUseAllowlist.allows(url: "https://anything.test/", domains: []))
        #expect(BrowserUseAllowlist.environmentValue(domains) == "example.com,*.docs.test")
        #expect(BrowserUseAllowlist.environmentValue([]) == nil)
    }

    @Test func launchEnvironmentHasTelemetryOffNoKeysAndTheAllowlist() {
        let base = ["PATH": "/usr/bin", "HOME": "/Users/x", "OPENAI_API_KEY": "sk-1", "ANTHROPIC_API_KEY": "a", "GH_AUTH_TOKEN": "t",
                    "BROWSER_USE_API_KEY": "b", "BROWSER_USE_ALLOWED_DOMAINS": "old.test"]
        let environment = BrowserUseConfig.environment(base: base, searchPath: ["/opt/homebrew/bin", "/usr/bin"], configPath: "/z/config.json",
                                                       configDirectory: "/z/home", allowedDomains: ["example.com", "wikipedia.org"], headless: true)
        #expect(environment["ANONYMIZED_TELEMETRY"] == "False")
        #expect(environment["BROWSER_USE_CLOUD_SYNC"] == "false")
        #expect(environment["BROWSER_USE_VERSION_CHECK"] == "false")
        #expect(environment["BROWSER_USE_ALLOWED_DOMAINS"] == "example.com,wikipedia.org")
        #expect(environment["BROWSER_USE_CONFIG_PATH"] == "/z/config.json")
        #expect(environment["BROWSER_USE_HEADLESS"] == "true")
        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/bin")
        #expect(environment["HOME"] == "/Users/x")
        #expect(environment["OPENAI_API_KEY"] == nil && environment["ANTHROPIC_API_KEY"] == nil && environment["GH_AUTH_TOKEN"] == nil)
        #expect(environment["BROWSER_USE_API_KEY"] == nil)
        let none = BrowserUseConfig.environment(base: base, searchPath: [], configPath: "c", configDirectory: "d", allowedDomains: [])
        #expect(none["BROWSER_USE_ALLOWED_DOMAINS"] == nil)
        #expect(BrowserUseConfig.uvxArguments(["--mcp"]) == ["browser-use@0.13.14", "--mcp"])
    }

    @Test func configHasItsOwnProfileAndNoLLMKey() throws {
        let data = BrowserUseConfig.json(profileDirectory: "/p/browser-use-profile", downloadsDirectory: "/p/dl", headless: false)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let profile = try #require(value["browser_profile"]?["zeus"])
        #expect(profile["user_data_dir"]?.stringValue == "/p/browser-use-profile")
        #expect(profile["default"]?.boolValue == true && profile["headless"]?.boolValue == false)
        #expect(value["llm"]?["zeus"]?["api_key"] == nil)
        #expect(String(decoding: data, as: UTF8.self).contains("sk-") == false)
    }

    @Test func backendSelectionFollowsTheSettingAndTheFlag() {
        #expect(BrowserAgentBackendKind.resolve(setting: "Your Chrome") == .chrome)
        #expect(BrowserAgentBackendKind.resolve(setting: "") == .chrome)
        #expect(BrowserAgentBackendKind.resolve(setting: "Separate browser (browser-use)") == .separate)
        #expect(BrowserAgentBackendKind.resolve(setting: "Your Chrome", forceSeparate: true) == .separate)
        let suite = "zeus.test.browseruse.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(FeatureSettings.browserAgentBackend(defaults: defaults) == .chrome)
        #expect(FeatureSettings.browserAgentAllowedDomains(defaults: defaults).isEmpty)
        defaults.set("Separate browser (browser-use)", forKey: FeatureSettings.key("browserAgent.backend"))
        defaults.set("example.com, wikipedia.org", forKey: FeatureSettings.key("browserAgent.allowedDomains"))
        #expect(FeatureSettings.browserAgentBackend(defaults: defaults) == .separate)
        #expect(FeatureSettings.browserAgentAllowedDomains(defaults: defaults) == ["example.com", "wikipedia.org"])
        #expect(FeatureSettings.browserBackendChoices == ["Your Chrome", "Separate browser (browser-use)"])
    }

    @Test func browseSeparateReachesTheCommand() throws {
        let plain = try ZeusCLI.parse(["browse", "find cables"], id: "a")
        #expect(plain.command?.separate == nil)
        let forced = try ZeusCLI.parse(["browse", "--separate", "find", "cables"], id: "b")
        #expect(forced.command?.separate == true && forced.command?.text == "find cables" && forced.command?.op == .browse)
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["ask", "hi", "--separate"]) }
        // An older app's line (no "separate") still decodes.
        let old = try JSONDecoder().decode(ZeusCommand.self, from: Data(#"{"kind":"zeus.command","v":1,"id":"x","op":"browse","text":"t","deep":false,"speak":true}"#.utf8))
        #expect(old.separate == nil)
        #expect(ZeusCLI.usage.contains("--separate"))
    }
}
