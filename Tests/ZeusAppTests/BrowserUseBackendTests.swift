import Foundation
import Testing
import ZeusCore
@testable import Zeus

private func fixtureURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/browseruse/\(name)")
}

private func recorded(_ fixture: String, _ tool: String, nth: Int = 0) throws -> String {
    let data = try Data(contentsOf: fixtureURL("\(fixture).json"))
    let entries = try #require(try JSONDecoder().decode(JSONValue.self, from: data).arrayValue)
    let requests = entries.filter { $0["dir"]?.stringValue == "->" && $0["msg"]?["params"]?["name"]?.stringValue == tool }
    let id = try #require(requests[nth]["msg"]?["id"]?.numberValue)
    let response = try #require(entries.first { $0["dir"]?.stringValue == "<-" && $0["msg"]?["id"]?.numberValue == id })
    return try #require(MCPToolResult(result: response["msg"]?["result"])).text
}

/// Answers browser_* calls from a closure and keeps every call, so tests can see what was sent.
private actor FakeMCP: MCPToolCalling {
    typealias Handler = @Sendable (String, [String: JSONValue]) -> MCPToolResult
    private(set) var calls: [(name: String, arguments: [String: JSONValue])] = []
    private(set) var closed = false
    private let handler: Handler

    init(_ handler: @escaping Handler) { self.handler = handler }

    func callTool(_ name: String, arguments: [String: JSONValue], timeout: TimeInterval) async throws -> MCPToolResult {
        calls.append((name, arguments))
        return handler(name, arguments)
    }

    func close() async { closed = true }

    var names: [String] { calls.map(\.name) }
}

private func text(_ value: String) -> MCPToolResult { MCPToolResult(text: value) }

/// A browser that shows the recorded form page.
private func formBrowser(sensitiveOnPage: Bool = true, extra: (@Sendable (String, [String: JSONValue]) -> MCPToolResult?)? = nil) throws -> FakeMCP {
    let state = try recorded("form-page", "browser_get_state")
    let tabs = try recorded("form-extras", "browser_list_tabs")
    return FakeMCP { name, arguments in
        if let answer = extra?(name, arguments) { return answer }
        switch name {
        case "browser_get_state": return text(state)
        case "browser_get_html":
            if arguments["selector"]?.stringValue == "title" { return text("<title>Zeus Form</title>") }
            if arguments["selector"]?.stringValue == BrowserUseMapping.sensitiveSelector {
                return text(sensitiveOnPage ? "<input type=\"password\" name=\"pw\">" : "No element found for selector: x")
            }
            return text("<html><body><h1>Sign in</h1><script>var a=1</script><p>Hello &amp; welcome</p></body></html>")
        case "browser_list_tabs": return text(tabs)
        case "browser_click": return text("Clicked element \(arguments["index"]?.numberValue.map { Int($0) } ?? 0)")
        case "browser_type": return text("Typed into element")
        case "browser_navigate": return text("Navigated to: \(arguments["url"]?.stringValue ?? "")")
        default: return text("ok")
        }
    }
}

@Suite("Separate browser backend")
struct BrowserUseBackendTests {
    @Test func observeShowsNumberedElementsTheRealTitleAndAStateID() async throws {
        let fake = try formBrowser()
        let backend = BrowserUseBackend(client: fake)
        let page = try await backend.observe()
        #expect(page.title == "Zeus Form")
        #expect(page.elements.count == 7)
        #expect(page.elements[5].promptLine == "[6] button \"Pay now\"")
        #expect(page.state?.hasPrefix("bu-") == true)
        let again = try await backend.observe()
        #expect(again.state == page.state)
        #expect(again.fingerprint == page.fingerprint)
    }

    @Test func clickUsesBrowserUsesOwnIndexAfterLookingAgain() async throws {
        let fake = try formBrowser()
        let backend = BrowserUseBackend(client: fake)
        let page = try await backend.observe()
        let action = try #require(try BrowserAgentLoop.action(for: .click(index: 6), on: page).get())
        _ = try await backend.execute(action)
        let calls = await fake.calls
        let click = try #require(calls.last)
        #expect(click.name == "browser_click" && click.arguments == ["index": .number(9)])
        // It looked again (browser_get_state) right before acting.
        let names = await fake.names
        #expect(names.filter { $0 == "browser_get_state" }.count == 2)
    }

    @Test func aPageThatChangedUnderTheBrainIsStaleAndNothingIsTouched() async throws {
        let form = try recorded("form-page", "browser_get_state")
        let other = try recorded("example-com", "browser_get_state")
        let state = StateFlip(first: form, then: other)
        let fake = FakeMCP { name, arguments in
            switch name {
            case "browser_get_state": return text(state.next())
            case "browser_get_html": return text("<title>T</title>")
            default: return text("ok")
            }
        }
        let backend = BrowserUseBackend(client: fake)
        let page = try await backend.observe()
        let action = try #require(try BrowserAgentLoop.action(for: .click(index: 6), on: page).get())
        await #expect(throws: BridgeError(code: BridgeError.staleElements)) { try await backend.execute(action) }
        #expect(await fake.names.contains("browser_click") == false)
    }

    @Test func browserUseSayingAnElementIsGoneIsAStalePage() async throws {
        let fake = try formBrowser(extra: { name, _ in name == "browser_click" ? text("Element with index 9 not found") : nil })
        let backend = BrowserUseBackend(client: fake)
        let page = try await backend.observe()
        let action = try #require(try BrowserAgentLoop.action(for: .click(index: 6), on: page).get())
        await #expect(throws: BridgeError(code: BridgeError.staleElements)) { try await backend.execute(action) }
    }

    @Test func typingReachesTheRightInput() async throws {
        let fake = try formBrowser()
        let backend = BrowserUseBackend(client: fake)
        let page = try await backend.observe()
        let action = try #require(try BrowserAgentLoop.action(for: .type(index: 1, text: "ada@example.com", submit: false), on: page).get())
        _ = try await backend.execute(action)
        let type = try #require(await fake.calls.last)
        #expect(type.name == "browser_type" && type.arguments == ["index": .number(4), "text": .string("ada@example.com")])
    }

    @Test func passwordAndCardFieldsAreRefusedAgainstTheBackendToo() async throws {
        let fake = try formBrowser()
        let backend = BrowserUseBackend(client: fake)
        let page = try await backend.observe()
        for index in [2, 3] {
            let action = try #require(try BrowserAgentLoop.action(for: .type(index: index, text: "secret", submit: false), on: page).get())
            await #expect(throws: BridgeError.self) { try await backend.execute(action) }
        }
        #expect(await fake.names.contains("browser_type") == false)
    }

    @Test func anUnlabelledInputOnAPageWithAPasswordFieldIsRefused() async throws {
        let state = #"{"url":"https://login.test/","title":"Login","tabs":[],"interactive_elements":[{"index":3,"tag":"input","text":""},{"index":4,"tag":"button","text":"Continue"}]}"#
        let refusing = FakeMCP { name, arguments in
            switch name {
            case "browser_get_state": return text(state)
            case "browser_get_html": return text(arguments["selector"]?.stringValue == "title" ? "<title>Login</title>" : "<input type=\"password\">")
            default: return text("ok")
            }
        }
        let backend = BrowserUseBackend(client: refusing)
        let page = try await backend.observe()
        let action = try #require(try BrowserAgentLoop.action(for: .type(index: 1, text: "x", submit: false), on: page).get())
        await #expect(throws: BridgeError(code: "sensitive_field", message: "That's a password or payment field, so I left it for you. Type it yourself and tell me when to carry on.")) {
            try await backend.execute(action)
        }
        #expect(await refusing.names.contains("browser_type") == false)

        let open = FakeMCP { name, arguments in
            switch name {
            case "browser_get_state": return text(state)
            case "browser_get_html": return text(arguments["selector"]?.stringValue == "title" ? "<title>Login</title>" : "No element found for selector: x")
            default: return text("Typed 'x' into element 3")
            }
        }
        let permissive = BrowserUseBackend(client: open)
        let page2 = try await permissive.observe()
        _ = try await permissive.execute(try #require(try BrowserAgentLoop.action(for: .type(index: 1, text: "x", submit: false), on: page2).get()))
        #expect(await open.names.contains("browser_type"))
    }

    @Test func submitTypesThenClicksTheSendingButton() async throws {
        let state = #"{"url":"https://s.test/","title":"S","tabs":[],"interactive_elements":[{"index":8,"tag":"input","text":"","placeholder":"Search"},{"index":9,"tag":"button","text":"Search"}]}"#
        let fake = FakeMCP { name, arguments in
            switch name {
            case "browser_get_state": return text(state)
            case "browser_get_html": return text("<title>S</title>")
            default: return text("ok")
            }
        }
        let backend = BrowserUseBackend(client: fake)
        let page = try await backend.observe()
        _ = try await backend.execute(try #require(try BrowserAgentLoop.action(for: .type(index: 1, text: "cables", submit: true), on: page).get()))
        let calls = await fake.calls.filter { $0.name == "browser_type" || $0.name == "browser_click" }
        #expect(calls.map(\.name) == ["browser_type", "browser_click"])
        #expect(calls[1].arguments == ["index": .number(9)])
    }

    @Test func extractReadsThePageHTMLNotTheAIBackedTool() async throws {
        let fake = try formBrowser()
        let backend = BrowserUseBackend(client: fake)
        _ = try await backend.observe()
        let page = try await backend.execute(.command(.extract(limit: 500)))
        #expect(page == "Sign in\nHello & welcome")
        let names = await fake.names
        #expect(!names.contains(BrowserUseTool.extractContent) && !names.contains(BrowserUseTool.retryWithAgent))
    }

    @Test func scrollBackOpenAndTabsMapToTheirTools() async throws {
        let fake = try formBrowser()
        let backend = BrowserUseBackend(client: fake)
        _ = try await backend.observe()
        _ = try await backend.execute(.command(.scroll(.down(pages: 1), state: nil)))
        _ = try await backend.execute(.command(.back))
        _ = try await backend.execute(.open(url: "https://example.com"))
        _ = try await backend.execute(.command(.switchTab(.title("done.html"))))
        let calls = await fake.calls.filter { $0.name != "browser_get_state" && $0.name != "browser_get_html" }
        #expect(calls.map(\.name) == ["browser_scroll", "browser_go_back", "browser_navigate", "browser_list_tabs", "browser_switch_tab"])
        #expect(calls[0].arguments == ["direction": .string("down")])
        #expect(calls[2].arguments == ["url": .string("https://example.com")])
        #expect(calls[4].arguments == ["tab_id": .string("6A16")])
    }

    @Test func dropdownsAndForwardAreSaidToBeUnsupported() async throws {
        let fake = try formBrowser()
        let backend = BrowserUseBackend(client: fake)
        let page = try await backend.observe()
        let select = try #require(try BrowserAgentLoop.action(for: .select(index: 4, option: "Blue"), on: page).get())
        await #expect(throws: BridgeError.self) { try await backend.execute(select) }
        await #expect(throws: BridgeError.self) { try await backend.execute(.command(.forward)) }
    }

    @Test func anAllowlistBlocksOtherSitesBeforeAnythingIsSent() async throws {
        let fake = try formBrowser()
        let backend = BrowserUseBackend(client: fake, allowedDomains: ["example.com"])
        await #expect(throws: BridgeError.self) { try await backend.execute(.open(url: "https://evil.test/")) }
        #expect(await fake.names.isEmpty)
        _ = try await backend.execute(.open(url: "https://www.example.com/x"))
        #expect(await fake.names == ["browser_navigate"])
    }

    @Test func aDeadServerIsNotConnected() async throws {
        struct Dead: MCPToolCalling {
            func callTool(_ name: String, arguments: [String: JSONValue], timeout: TimeInterval) async throws -> MCPToolResult {
                throw MCPClientError.notRunning("Chromium failed to start")
            }
            func close() async {}
        }
        let backend = BrowserUseBackend(client: Dead())
        do { _ = try await backend.observe(); Issue.record("expected a failure") } catch let error as BridgeError {
            #expect(error.code == BridgeError.notConnected && error.message?.contains("Chromium failed to start") == true)
        }
    }

    @Test func closeEndsTheSession() async throws {
        let fake = try formBrowser()
        await BrowserUseBackend(client: fake).close()
        #expect(await fake.names == ["browser_close_all"])
        #expect(await fake.closed)
    }
}

/// Returns `first` once, then `then` for every later call.
private final class StateFlip: @unchecked Sendable {
    private let lock = NSLock()
    private var served = 0
    private let first: String, then: String
    init(first: String, then: String) { self.first = first; self.then = then }
    func next() -> String { lock.withLock { served += 1; return served == 1 ? first : then } }
}

@Suite("MCP stdio client")
struct MCPStdioClientTests {
    private func client() -> MCPStdioClient {
        MCPStdioClient(launch: MCPStdioClient.Launch(executable: "/usr/bin/python3", arguments: [fixtureURL("fake_mcp_server.py").path],
                                                     environment: ["PATH": "/usr/bin:/bin"], currentDirectory: nil))
    }

    @Test func handshakeListAndCall() async throws {
        let client = client()
        let info = try await client.start(timeout: 10)
        #expect(info == MCPStdioClient.ServerInfo(name: "browser-use", version: "0.13.14", protocolVersion: "2025-06-18"))
        #expect(try await client.listTools(timeout: 5).count == 16)
        let result = try await client.callTool("browser_navigate", arguments: ["url": .string("https://example.com")], timeout: 5)
        #expect(result.text == "Navigated to: https://example.com" && !result.isError)
        let state = try await client.callTool("browser_get_state", arguments: [:], timeout: 5)
        #expect(BrowserUseState.parse(state.text)?.url == "https://example.com/")
        #expect(await client.notifications.contains("notifications/message"))
        await client.close()
        #expect(await client.isRunning == false)
    }

    @Test func aRequestThatNeverAnswersTimesOut() async throws {
        let client = client()
        try await client.start(timeout: 10)
        let started = Date()
        await #expect(throws: MCPClientError.timedOut("slow", 1)) { try await client.callTool("slow", arguments: [:], timeout: 1) }
        #expect(Date().timeIntervalSince(started) < 5)
        // The connection is still good after a timeout.
        #expect(try await client.callTool("browser_navigate", arguments: ["url": .string("https://a.test")], timeout: 5).text.hasPrefix("Navigated"))
        await client.close()
    }

    @Test func serverPingsAreAnswered() async throws {
        let client = client()
        try await client.start(timeout: 10)
        #expect(try await client.callTool("ping", arguments: [:], timeout: 5).text == "pong-ok")
        await client.close()
    }

    @Test func aCrashFailsTheCallWithTheLastErrorLine() async throws {
        let client = client()
        try await client.start(timeout: 10)
        do {
            _ = try await client.callTool("crash", arguments: [:], timeout: 5)
            Issue.record("expected a failure")
        } catch let error as MCPClientError {
            guard case .notRunning(let tail) = error else { Issue.record("wrong error \(error)"); return }
            #expect(tail.contains("Chromium failed to start"))
        }
        await #expect(throws: MCPClientError.self) { try await client.callTool("browser_get_state", arguments: [:], timeout: 2) }
        await client.close()
    }

    @Test func closeWaitsForTheServerToFinishWhenItsInputEnds() async throws {
        let client = client()
        try await client.start(timeout: 10)
        let started = Date()
        await client.close()
        #expect(Date().timeIntervalSince(started) < 3)
        #expect(await client.isRunning == false)
        await #expect(throws: MCPClientError.self) { try await client.callTool("browser_get_state", arguments: [:], timeout: 2) }
    }

    @Test func aMissingProgramIsALaunchFailure() async {
        let client = MCPStdioClient(launch: MCPStdioClient.Launch(executable: "/nonexistent/uvx", arguments: [], environment: [:], currentDirectory: nil))
        await #expect(throws: MCPClientError.self) { try await client.start(timeout: 2) }
    }
}

@Suite("Browser agent backend selection")
struct BrowserBackendSelectionTests {
    @MainActor
    @Test func theRunnerFollowsTheSettingAndTheFlag() {
        let suite = "zeus.test.backend.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(BrowserAgentRunner.backendKind(forceSeparate: false, defaults: defaults) == .chrome)
        #expect(BrowserAgentRunner.backendKind(forceSeparate: true, defaults: defaults) == .separate)
        defaults.set("Separate browser (browser-use)", forKey: FeatureSettings.key("browserAgent.backend"))
        #expect(BrowserAgentRunner.backendKind(forceSeparate: false, defaults: defaults) == .separate)
    }

    @Test func setupStatusReadsWhatIsOnDisk() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-bu-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        // Only a Playwright Chromium present (Chrome itself may or may not be installed on this Mac).
        let binary = home.appendingPathComponent("Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Chromium.app/Contents/MacOS/Chromium")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: binary.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        let found = BrowserUseSetup.browserPath(home: home.path)
        #expect(found == "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" || found == binary.path)
        #expect(BrowserUseSetup.Status(uvPath: "/x/uv", packageCached: true, browserPath: "/b").ready)
        #expect(!BrowserUseSetup.Status(uvPath: "/x/uv", packageCached: false, browserPath: "/b").ready)
        #expect(!BrowserUseSetup.Status(uvPath: nil, packageCached: true, browserPath: "/b").ready)
        #expect(BrowserUseSetup.Status(uvPath: nil, packageCached: false, browserPath: nil).browserText == "No Chromium yet")
    }

    @Test func profileAndConfigLiveUnderZeusSupport() {
        #expect(BrowserUseSetup.profileDirectory.path.hasSuffix("Zeus/browser-use-profile") || ProcessInfo.processInfo.environment["ZEUS_SUPPORT_DIR"] != nil)
        #expect(BrowserUseSetup.profileDirectory.lastPathComponent == "browser-use-profile")
        #expect(BrowserUseSetup.configFile.lastPathComponent == "config.json")
    }
}
