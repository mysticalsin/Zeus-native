import Foundation

// The wire side of the "Separate browser" backend: MCP over stdio (newline-delimited JSON-RPC 2.0)
// to `uvx browser-use --mcp`. Pure encoding and decoding, so it is tested against the responses
// recorded from the real server (Tests/Fixtures/browseruse). browser-use is used only for its
// browser_* tools; Zeus's own brain picks every step.

public struct MCPError: Error, Equatable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// One message from the server.
public enum MCPIncoming: Equatable, Sendable {
    case response(id: Int, result: JSONValue?, error: MCPError?)
    case notification(method: String, params: JSONValue?)
    /// The server asking the client something (ping, roots, sampling). Zeus answers ping only.
    case request(id: JSONValue, method: String, params: JSONValue?)
}

public enum MCPCodecError: Error, Equatable, Sendable {
    case notJSON
    case notAMessage
}

public enum MCPCodec {
    /// The protocol revision Zeus asks for; the server answers with the one it speaks.
    public static let protocolVersion = "2025-06-18"

    /// One line, newline included.
    private static func line(_ object: [String: JSONValue]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = (try? encoder.encode(JSONValue.object(object))) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }

    public static func request(id: Int, method: String, params: JSONValue? = nil) -> Data {
        var object: [String: JSONValue] = ["jsonrpc": .string("2.0"), "id": .number(Double(id)), "method": .string(method)]
        if let params { object["params"] = params }
        return line(object)
    }

    public static func notification(method: String, params: JSONValue? = nil) -> Data {
        var object: [String: JSONValue] = ["jsonrpc": .string("2.0"), "method": .string(method)]
        if let params { object["params"] = params }
        return line(object)
    }

    /// The answer to a server request (an empty result for ping).
    public static func response(id: JSONValue, result: JSONValue = .object([:])) -> Data {
        line(["jsonrpc": .string("2.0"), "id": id, "result": result])
    }

    public static func initializeParams(clientName: String = "zeus", clientVersion: String = "1") -> JSONValue {
        .object([
            "protocolVersion": .string(protocolVersion),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string(clientName), "version": .string(clientVersion)]),
        ])
    }

    public static func callParams(name: String, arguments: [String: JSONValue]) -> JSONValue {
        .object(["name": .string(name), "arguments": .object(arguments)])
    }

    public static func decode(_ line: Data) throws -> MCPIncoming {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: line), case .object(let object) = value else {
            throw MCPCodecError.notJSON
        }
        let method = object["method"]?.stringValue
        let id = object["id"]
        if let method {
            if let id { return .request(id: id, method: method, params: object["params"]) }
            return .notification(method: method, params: object["params"])
        }
        guard let number = id?.numberValue, number.rounded() == number else { throw MCPCodecError.notAMessage }
        if case .object(let error)? = object["error"] {
            let code = Int(error["code"]?.numberValue ?? -32_603)
            return .response(id: Int(number), result: nil, error: MCPError(code: code, message: error["message"]?.stringValue ?? "error"))
        }
        return .response(id: Int(number), result: object["result"], error: nil)
    }
}

/// What a `tools/call` returned: the text parts joined, how many images came with it, and the
/// server's own error flag. browser-use also reports many failures as plain text with the flag
/// off ("Element with index 6 not found"), which the backend checks for.
public struct MCPToolResult: Equatable, Sendable {
    public let text: String
    public let imageCount: Int
    public let isError: Bool

    public init(text: String, imageCount: Int = 0, isError: Bool = false) {
        self.text = text
        self.imageCount = imageCount
        self.isError = isError
    }

    public init?(result: JSONValue?) {
        guard let result, case .array(let parts)? = result["content"] else { return nil }
        var texts: [String] = []
        var images = 0
        for part in parts {
            switch part["type"]?.stringValue {
            case "text": texts.append(part["text"]?.stringValue ?? "")
            case "image": images += 1
            default: break
            }
        }
        self.init(text: texts.joined(separator: "\n"), imageCount: images, isError: result["isError"]?.boolValue ?? false)
    }
}

public struct MCPToolInfo: Equatable, Sendable {
    public let name: String
    public let description: String
    public let required: [String]
    public let properties: [String]

    public static func parse(_ result: JSONValue?) -> [MCPToolInfo] {
        guard case .array(let tools)? = result?["tools"] else { return [] }
        return tools.compactMap { tool in
            guard let name = tool["name"]?.stringValue else { return nil }
            let schema = tool["inputSchema"]
            var properties: [String] = []
            if case .object(let object)? = schema?["properties"] { properties = object.keys.sorted() }
            return MCPToolInfo(name: name, description: tool["description"]?.stringValue ?? "",
                               required: schema?["required"]?.arrayValue?.compactMap(\.stringValue) ?? [], properties: properties)
        }
    }
}

/// The browser_* tools Zeus uses. Names and parameters are as recorded from browser-use 0.13.14.
public enum BrowserUseTool {
    public static let navigate = "browser_navigate"       // url, new_tab
    public static let click = "browser_click"             // index | coordinate_x + coordinate_y, new_tab
    public static let type = "browser_type"               // index, text
    public static let getState = "browser_get_state"      // include_screenshot
    public static let getHTML = "browser_get_html"        // selector
    public static let scroll = "browser_scroll"           // direction up|down
    public static let goBack = "browser_go_back"
    public static let listTabs = "browser_list_tabs"
    public static let switchTab = "browser_switch_tab"    // tab_id (4 characters)
    public static let closeTab = "browser_close_tab"      // tab_id
    public static let closeAll = "browser_close_all"
    /// Needs an LLM key inside browser-use ("LLM not initialized"), so Zeus never calls it.
    public static let extractContent = "browser_extract_content"
    /// Runs browser-use's own AI agent. Never called: Zeus's brain decides each step.
    public static let retryWithAgent = "retry_with_browser_use_agent"

    /// Every tool the backend relies on.
    public static let used = [navigate, click, type, getState, getHTML, scroll, goBack, listTabs, switchTab, closeTab, closeAll]
}
