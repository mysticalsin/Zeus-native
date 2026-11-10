import Foundation
import ZeusCore

/// Sends one request to the ZEUS Chrome extension through `zeus-bridge`'s socket.
/// The socket only exists while Chrome is running with the extension loaded.
enum ChromeBridge {
    /// Immutable browser destination captured before consent. Chrome's document ID changes even
    /// when a reload returns to the same URL. It is never inferred again after approval.
    struct ActionTarget: Equatable, Sendable {
        let tabID: Int
        let url: String
        let documentID: String?
        let requiresActive: Bool

        init?(value: JSONValue?) {
            guard let id = value?["tabId"]?.numberValue, id.isFinite, id >= 0,
                  id < Double(Int.max), id.rounded() == id,
                  let url = value?["url"]?.stringValue, !url.isEmpty,
                  let requiresActive = value?["requiresActive"]?.boolValue else { return nil }
            tabID = Int(id)
            self.url = url
            documentID = value?["documentId"]?.stringValue
            self.requiresActive = requiresActive
        }

        var host: String { URL(string: url)?.host ?? url }
        var value: JSONValue {
            var result: [String: JSONValue] = ["tabId": .number(Double(tabID)), "url": .string(url),
                                              "requiresActive": .bool(requiresActive)]
            if let documentID { result["documentId"] = .string(documentID) }
            return .object(result)
        }
    }

    enum BridgeFailure: LocalizedError {
        case notConnected
        case failed(BridgeError)

        var errorDescription: String? {
            switch self {
            case .notConnected: "Chrome isn't connected to ZEUS. Open Chrome and check the ZEUS extension is on."
            case .failed(let error): error.spokenMessage
            }
        }

        var code: String {
            switch self {
            case .notConnected: BridgeError.notConnected
            case .failed(let error): error.code
            }
        }
    }

    static func call(_ type: String, _ params: [String: JSONValue] = [:], timeout: TimeInterval = 22) async throws -> JSONValue? {
        let request = BridgeRequest(type: type, params: params)
        let payload = try JSONEncoder().encode(request)
        let path = ZeusPaths.chromeSocket.path
        let reply = await Task.detached {
            UnixSocket.request(path: path, payload: payload, expectReply: true, timeout: timeout)
        }.value
        guard let reply, let response = try? JSONDecoder().decode(BridgeResponse.self, from: reply) else {
            throw BridgeFailure.notConnected
        }
        guard response.ok else {
            throw BridgeFailure.failed(response.error ?? BridgeError(code: "failed"))
        }
        return response.result
    }

    /// True when the extension answers a ping (Chrome open, extension loaded, host registered).
    static func isConnected() async -> Bool {
        (try? await call("ping", timeout: 2)) != nil
    }

    static func actionTarget(matching params: [String: JSONValue] = [:]) async throws -> ActionTarget {
        let value = try await call("page.target", params, timeout: 3)
        guard let target = ActionTarget(value: value) else {
            throw BridgeFailure.failed(BridgeError(code: "stale_target", message: "Chrome couldn't identify the page. Nothing was changed."))
        }
        return target
    }

    /// The active tab, or nil if Chrome isn't reachable within `timeout`. With `elements`, also
    /// numbers its interactive elements (`page.elements`) for the indexed actions. That starts a
    /// new page state, so only the turn's own read asks for it, never a consent check.
    static func activeTab(timeout: TimeInterval = 1.5, elements: Bool = false) async -> TabContext? {
        await activeTabSnapshot(timeout: timeout, elements: elements)?.context
    }

    /// Context and numbered elements must come from the same tab and document, not two
    /// concurrent active-tab lookups that can straddle a tab switch.
    static func activeTabSnapshot(timeout: TimeInterval = 1.5, elements: Bool = false) async -> (context: TabContext, target: ActionTarget?)? {
        guard let value = try? await call("page.context", timeout: timeout),
              let url = value["url"]?.stringValue else { return nil }
        let controls = value["controls"]?.arrayValue?.compactMap(\.stringValue)
        let target = ActionTarget(value: value["target"])
        let list = elements ? await pageElements(timeout: timeout, target: target) : nil
        // With a scriptable target, a missing list means it changed while being read.
        if elements, target?.documentID != nil, list == nil { return nil }
        let context = TabContext(
            url: url,
            title: value["title"]?.stringValue ?? "",
            selection: value["selection"]?.stringValue,
            text: value["text"]?.stringValue,
            controls: controls,
            elementsState: list?.url == url ? list?.state : nil,
            elements: list?.url == url ? list?.elements : nil
        )
        return (context, target)
    }

    /// The active tab's numbered elements, or nil (Chrome unreachable, an older extension, or a
    /// page Chrome doesn't let extensions script).
    static func pageElements(timeout: TimeInterval = 1.5, target: ActionTarget? = nil) async -> (url: String, state: String, elements: [PageElement])? {
        let params: [String: JSONValue] = target.map { ["pageTarget": $0.value] } ?? [:]
        guard let value = try? await call("page.elements", params, timeout: timeout),
              let url = value["url"]?.stringValue,
              let state = value["state"]?.stringValue,
              let data = try? JSONEncoder().encode(value["elements"] ?? .array([])),
              let elements = try? JSONDecoder().decode([PageElement].self, from: data) else { return nil }
        return (url, state, elements)
    }
}
