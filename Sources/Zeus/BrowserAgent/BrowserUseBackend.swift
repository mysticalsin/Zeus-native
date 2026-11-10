import Foundation
import ZeusCore

/// The "Separate browser" for the browser agent: browser-use's own Chromium, driven through the
/// browser_* tools of `uvx browser-use --mcp`. Zeus's brain still picks every step; this only
/// shows the page as the loop's indexed elements (with a page-state id the loop's freshness check
/// uses) and carries the loop's ops out as tool calls. Approvals and the password and card
/// refusals stay in `BrowserAgentLoop`; this backend refuses a sensitive field again as a last
/// check, and never calls browser-use's AI tools.
actor BrowserUseBackend {
    private let client: any MCPToolCalling
    private let allowedDomains: [String]
    private(set) var snapshot: BrowserUseSnapshot?

    init(client: any MCPToolCalling, allowedDomains: [String] = []) {
        self.client = client
        self.allowedDomains = allowedDomains
    }

    /// Starts browser-use (own profile, own config), checks it has the tools this relies on and opens
    /// the browser. A first launch on a brand new profile can outlast browser-use's own 30 second
    /// start limit, which leaves that server unusable, so a failed start is retried once on a fresh
    /// server (the profile is warm by then).
    static func launch(allowedDomains: [String], headless: Bool? = nil) async throws -> BrowserUseBackend {
        let launch = try BrowserUseSetup.launch(allowedDomains: allowedDomains, headless: headless)
        var lastError: Error = MCPClientError.launchFailed("no attempt")
        for attempt in 0..<2 {
            let client = MCPStdioClient(launch: launch)
            do {
                try await client.start()
                let names = Set(try await client.listTools().map(\.name))
                let missing = BrowserUseTool.used.filter { !names.contains($0) }
                guard missing.isEmpty else {
                    throw MCPClientError.badResponse("browser-use \(BrowserUseConfig.pinnedVersion) lacks \(missing.joined(separator: ", "))")
                }
                // The first browser_* call starts Chromium.
                let warm = try await client.callTool(BrowserUseTool.listTabs, arguments: [:], timeout: 75)
                if warm.isError || warm.text.hasPrefix("Error:") { throw MCPClientError.launchFailed(String(warm.text.prefix(160))) }
                return BrowserUseBackend(client: client, allowedDomains: allowedDomains)
            } catch {
                lastError = error
                await client.close()
                if Task.isCancelled || (error as? MCPClientError).map({ if case .badResponse = $0 { true } else { false } }) == true { break }
                if attempt == 0 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
        throw lastError
    }

    /// Closes the browser window and ends the server.
    func close() async {
        _ = try? await client.callTool(BrowserUseTool.closeAll, arguments: [:], timeout: 10)
        await client.close()
    }

    // MARK: Observe

    /// The active tab with its numbered elements. A page still loading gets a few more looks.
    func observe() async throws -> BrowserAgentPage {
        var state: BrowserUseState?
        for attempt in 0..<4 {
            let result = try await call(BrowserUseTool.getState)
            guard let parsed = BrowserUseState.parse(result.text) else {
                throw BridgeError(code: "failed", message: "The separate browser's page list couldn't be read.")
            }
            state = parsed
            if !parsed.elements.isEmpty || parsed.url == "about:blank" { break }
            if attempt < 3 { try? await Task.sleep(for: .milliseconds(600)) }
        }
        guard let state else { throw BridgeError(code: BridgeError.notConnected) }
        // browser_get_state's title is often just the address; the page's own <title> is better.
        var title: String?
        if let html = try? await call(BrowserUseTool.getHTML, ["selector": .string("title")]) {
            title = BrowserUseMapping.title(fromHTML: html.text)
        }
        let taken = BrowserUseMapping.snapshot(from: state, title: title)
        snapshot = taken
        return taken.page
    }

    // MARK: Execute

    /// Carries out one loop action. Returns page text for extract, nil otherwise. Throws
    /// `BridgeError` the way the Chrome backend does (stale elements, sensitive field, ...).
    func execute(_ action: BrowserAgentAction) async throws -> String? {
        let snapshot = self.snapshot ?? .empty
        let plan = try BrowserUseMapping.call(for: action, snapshot: snapshot)
        if case .command(let command) = action, command.elementIndex != nil {
            try await ensureFresh(expected: Self.state(of: command) ?? snapshot.page.state)
        }
        switch plan {
        case .tool(let name, let arguments):
            if name == BrowserUseTool.navigate {
                let url = arguments["url"]?.stringValue ?? ""
                guard BrowserUseAllowlist.allows(url: url, domains: allowedDomains) else {
                    throw BridgeError(code: "blocked_domain", message: "That site isn't in your allowed domains for the separate browser.")
                }
            }
            _ = try await call(name, arguments)
            try? await Task.sleep(for: .milliseconds(name == BrowserUseTool.navigate ? 900 : (name == BrowserUseTool.scroll ? 250 : 600)))
            return nil
        case .type(let real, let text, let submit):
            try await refuseSensitive(real)
            _ = try await call(BrowserUseTool.type, ["index": .number(Double(real)), "text": .string(text)])
            if submit { try await submitTyped(real) }
            try? await Task.sleep(for: .milliseconds(400))
            return nil
        case .switchTab(let match):
            let listing = try await call(BrowserUseTool.listTabs)
            guard let id = BrowserUseMapping.tabID(matching: match, in: listing.text) else {
                throw BridgeError(code: "failed", message: "No open tab matches \(match.description).")
            }
            _ = try await call(BrowserUseTool.switchTab, ["tab_id": .string(id)])
            return nil
        case .closeTab(let match):
            guard let match else { throw BridgeError(code: "unsupported", message: "Say which tab to close, by its title.") }
            let listing = try await call(BrowserUseTool.listTabs)
            guard let id = BrowserUseMapping.tabID(matching: match, in: listing.text) else {
                throw BridgeError(code: "failed", message: "No open tab matches \(match.description).")
            }
            _ = try await call(BrowserUseTool.closeTab, ["tab_id": .string(id)])
            return nil
        case .extract(let limit):
            // browser_extract_content needs an AI key inside browser-use; read the page HTML instead.
            let html = try await call(BrowserUseTool.getHTML)
            return BrowserUseMapping.plainText(fromHTML: html.text, limit: limit)
        case .pause(let ms):
            try? await Task.sleep(for: .milliseconds(ms))
            return nil
        case .none:
            return nil
        case .unsupported(let message):
            throw BridgeError(code: "unsupported", message: message)
        }
    }

    private static func state(of command: BrowserCommand) -> String? {
        switch command {
        case .clickIndex(_, let state), .typeIndex(_, _, _, let state), .selectOption(_, _, let state), .scroll(_, let state): state
        default: nil
        }
    }

    // MARK: Checks

    /// Looks at the page again right before an indexed step: a changed address or element list is a
    /// stale page, and nothing is touched.
    private func ensureFresh(expected: String?) async throws {
        let result = try await call(BrowserUseTool.getState)
        guard let state = BrowserUseState.parse(result.text) else { return }
        let fresh = BrowserUseMapping.stateID(url: state.url, elements: state.elements)
        if let expected, fresh != expected { throw BridgeError(code: BridgeError.staleElements) }
    }

    /// Passwords, card numbers and one-time codes are left to Tony. The loop refuses a field whose
    /// label says so; browser-use doesn't report an input's type, so an input with no label at all
    /// is checked against the page's own password and card inputs.
    private func refuseSensitive(_ real: Int) async throws {
        let refusal = BridgeError(code: "sensitive_field", message: "That's a password or payment field, so I left it for you. Type it yourself and tell me when to carry on.")
        guard let snapshot else { return }
        if let loopIndex = snapshot.realIndex.first(where: { $0.value == real })?.key,
           let element = snapshot.page.element(loopIndex), BrowserAgentSafety.isSensitive(element) { throw refusal }
        let raw = snapshot.raw.first { $0.index == real }
        if BrowserUseMapping.isUnnamedField(raw) {
            let probe = try await call(BrowserUseTool.getHTML, ["selector": .string(BrowserUseMapping.sensitiveSelector)])
            if probe.text.hasPrefix("<") { throw refusal }
        }
    }

    /// browser-use has no Enter key; the control that sends the text on is clicked instead.
    private func submitTyped(_ real: Int) async throws {
        let result = try await call(BrowserUseTool.getState)
        let elements = BrowserUseState.parse(result.text)?.elements ?? snapshot?.raw ?? []
        guard let control = BrowserUseMapping.submitControl(after: real, in: elements) else {
            throw BridgeError(code: "submit_unavailable", message: "I typed it, but found no button to send it. Click the button that submits it.")
        }
        _ = try await call(BrowserUseTool.click, ["index": .number(Double(control))])
    }

    // MARK: Tool calls

    @discardableResult
    private func call(_ name: String, _ arguments: [String: JSONValue] = [:]) async throws -> MCPToolResult {
        let result: MCPToolResult
        do {
            result = try await client.callTool(name, arguments: arguments, timeout: name == BrowserUseTool.navigate ? 60 : 45)
        } catch let error as MCPClientError {
            switch error {
            case .notRunning, .launchFailed:
                throw BridgeError(code: BridgeError.notConnected, message: error.errorDescription)
            default:
                throw BridgeError(code: "failed", message: error.errorDescription)
            }
        }
        if name != BrowserUseTool.getHTML, let failure = BrowserUseMapping.failure(in: result, tool: name) { throw failure }
        return result
    }
}
