import Foundation
import ZeusCore

/// Carries out `[ACTION:{…}]` tags in Chrome. Opening pages and handing a prompt to ChatGPT,
/// Claude or Dust happen straight away (you asked for them out loud). Clicking or typing on a
/// site asks first in the notch, once per site per launch. Returns what to say if it failed.
/// The indexed actions (`browser.click_index` and friends) act on the numbered elements the turn
/// read with the tab; the ones that change a page go through the same per-site consent.
@MainActor
final class ChromeActions {
    private let notch: NotchController
    private var allowedHosts: Set<String> = []
    /// The numbered elements the brain saw this turn, to name them on the consent card.
    private var knownElements: (state: String?, elements: [PageElement]) = (nil, [])
    /// Text from `browser.extract`, handed to the brain with the next turn on the same page.
    private var readback: (url: String, text: String)?

    init(notch: NotchController) {
        self.notch = notch
    }

    func perform(_ action: ZeusAction) async -> String? {
        let payload = action.payload
        do {
            switch action.kind {
            case .macDrive, .macWalkthrough, .presentCard, .browserAgent, .terminalAgent, .terminalOpen, .terminalRun, .research:
                return nil // handled by DriveController / WalkthroughController / BrowserAgentRunner / CodeActions

            case .browserOpen:
                guard let url = payload["url"]?.stringValue else { return nil }
                _ = try await ChromeBridge.call("tab.open", ["url": .string(url)])

            case .panelOpen, .delegateDust, .delegateChrome:
                let which = action.kind == .delegateDust ? "dust" : (payload["which"]?.stringValue ?? "claude")
                let prompt = payload["prompt"]?.stringValue ?? ""
                if action.alwaysNeedsConsent {
                    let ok = await ask(site: which, what: "Send to \(which): \(prompt)", risk: .medium)
                    guard ok else { return "Okay, I won't send it." }
                }
                _ = try await ChromeBridge.call("ai.ask", [
                    "which": .string(which), "prompt": .string(prompt), "send": .bool(!prompt.isEmpty),
                ], timeout: 40)

            case .browserClick:
                guard let text = Self.targetText(payload) ?? payload["text"]?.stringValue else { return nil }
                let target = try await ChromeBridge.actionTarget()
                guard await consent(for: "Click “\(text)”", target: target, always: ModelActionApproval.clickAlwaysAsks(label: text)) else { return "Okay, I left it." }
                _ = try await ChromeBridge.call("page.click", ["text": .string(text), "pageTarget": target.value])

            case .browserType:
                guard let text = payload["text"]?.stringValue else { return nil }
                let field = Self.targetText(payload) ?? ""
                let target = try await ChromeBridge.actionTarget()
                let submit = payload["submit"]?.boolValue ?? false
                let what = "Type “\(text)”" + (field.isEmpty ? "" : " into \(field)") + (submit ? " and submit" : "")
                guard await consent(for: what, target: target) else { return "Okay, I didn't type anything." }
                _ = try await ChromeBridge.call("page.type", [
                    "target": .string(field), "text": .string(text), "submit": .bool(submit), "pageTarget": target.value,
                ])

            case .browserRead:
                break // the active tab is already sent with every turn while Chrome is in front

            case .browserClickIndex, .browserTypeIndex, .browserSelect, .browserScroll, .browserBack,
                 .browserForward, .browserSwitchTab, .browserCloseTab, .browserExtract:
                guard let command = BrowserCommand(action) else { return "I couldn't make sense of that browser step." }
                return try await run(command)
            }
            return nil
        } catch let failure as ChromeBridge.BridgeFailure {
            if failure.code == BridgeError.staleElements { knownElements = (nil, []) }
            return failure.errorDescription
        } catch {
            return error.localizedDescription
        }
    }

    /// Remembers the tab the brain is about to see, and adds any text an earlier
    /// `browser.extract` read from that same page.
    func prepare(_ tab: TabContext?) -> TabContext? {
        guard let tab else { return nil }
        knownElements = (tab.elementsState, tab.elements ?? [])
        guard let readback, readback.url == tab.url else { return tab }
        self.readback = nil
        return tab.with(extract: readback.text)
    }

    private func run(_ command: BrowserCommand) async throws -> String? {
        var params = command.bridgeParams
        if case .closeTab(let match?) = command {
            // Consent is for the site of the tab being closed, which may not be the active one.
            let target = try await ChromeBridge.actionTarget(matching: match.params)
            guard await consent(for: command.summary(label: nil), target: target) else { return "Okay, I left it open." }
            params = ["pageTarget": target.value]
        } else if command.changesPage {
            let target = try await ChromeBridge.actionTarget()
            let name = label(for: command)
            guard await consent(for: command.summary(label: name), target: target,
                                always: ModelActionApproval.clickAlwaysAsks(label: name)) else { return "Okay, I left it." }
            params["pageTarget"] = target.value
        }
        let result = try await ChromeBridge.call(command.bridgeType, params)
        if case .extract(let limit) = command, let url = result?["url"]?.stringValue,
           let text = result?["text"]?.stringValue, !text.isEmpty {
            readback = (url, PageText.truncate(text, to: limit))
        }
        return nil
    }

    /// One browser-agent step: the same per-site consent as a spoken step (skipped when Tony just
    /// approved this exact step on its own card), then the extension request. Returns page text
    /// for `extract`. Throws `BridgeError` (stale elements, sensitive field, declined consent).
    func agentExecute(_ command: BrowserCommand, label: String?, approved: Bool,
                      observedTarget: ChromeBridge.ActionTarget?) async throws -> String? {
        var params = command.bridgeParams
        if command.changesPage {
            let target: ChromeBridge.ActionTarget
            var needsConsent = !approved
            if case .closeTab(let match?) = command {
                // A named tab is not necessarily the page on the browser-agent approval card.
                // Resolve it before its own consent and never transfer an approval between tabs.
                target = try await ChromeBridge.actionTarget(matching: match.params)
                needsConsent = true
            } else {
                guard let observedTarget else { throw BridgeError(code: "stale_target", message: "Take a fresh look at the page before changing it.") }
                target = observedTarget
            }
            if needsConsent, !(await consent(for: command.summary(label: label), target: target)) {
                throw BridgeError(code: "declined", message: "Okay, I left it.")
            }
            params["pageTarget"] = target.value
        }
        let result = try await bridged { try await ChromeBridge.call(command.bridgeType, params) }
        if case .extract(let limit) = command, let text = result?["text"]?.stringValue {
            return PageText.truncate(text, to: limit)
        }
        return nil
    }

    /// Bridge failures as the `BridgeError` the agent loop reads.
    private func bridged(_ call: () async throws -> JSONValue?) async throws -> JSONValue? {
        do { return try await call() } catch let failure as ChromeBridge.BridgeFailure {
            switch failure {
            case .notConnected: throw BridgeError(code: BridgeError.notConnected, message: failure.errorDescription)
            case .failed(let error): throw error
            }
        }
    }

    /// The label of the element a command points at, from the list this turn saw.
    private func label(for command: BrowserCommand) -> String? {
        guard let index = command.elementIndex else { return nil }
        // A number from another page state may name a different element: show the number only.
        if let state = command.bridgeParams["state"]?.stringValue, state != knownElements.state { return nil }
        return knownElements.elements.first { $0.index == index }?.text
    }

    /// "Search" from {"target":{"text":"Search"}} or {"target":"Search"}.
    static func targetText(_ payload: [String: JSONValue]) -> String? {
        payload["target"]?["text"]?.stringValue ?? payload["target"]?.stringValue
    }

    /// `always`: a send, delete or buy click asks even when the site was allowed earlier, and does not widen that allowance.
    private func consent(for what: String, target: ChromeBridge.ActionTarget, always: Bool = false) async -> Bool {
        let host = target.host
        if always { return await ask(site: host, what: what, risk: .high) }
        if allowedHosts.contains(host) { return true }
        // Two steps on the same site at once share one card: the second waits for the first answer.
        await PermissionPrompts.shared.run("chrome:" + host) { [self] in
            if await ask(site: host, what: what, risk: .medium) { allowedHosts.insert(host) }
        }
        return allowedHosts.contains(host)
    }

    private func ask(site: String, what: String, risk: HookEvent.Risk) async -> Bool {
        await notch.requestApproval(agent: "Zeus", project: site, tool: "Chrome", command: what, risk: risk,
                                    timeout: .seconds(30), onTimeout: .deny) == .allow
    }
}
