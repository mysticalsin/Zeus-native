import Foundation

/// A request from ZEUS to the Chrome extension (or back), relayed by `zeus-bridge`.
public struct BridgeRequest: Codable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let params: [String: JSONValue]

    public init(id: String = UUID().uuidString, type: String, params: [String: JSONValue] = [:]) {
        self.id = id
        self.type = type
        self.params = params
    }
}

public struct BridgeError: Codable, Equatable, Sendable, Error {
    public let code: String
    public let site: String?
    public let message: String?

    public init(code: String, site: String? = nil, message: String? = nil) {
        self.code = code
        self.site = site
        self.message = message
    }

    public static let consentRequired = "consent_required"
    public static let notConnected = "not_connected"
    /// An element number from an older `page.elements` list: the page navigated or changed a lot
    /// since, so the number may now point at something else. Nothing was touched.
    public static let staleElements = "stale_elements"
    /// Back or forward with no page to go to in that direction.
    public static let noHistory = "no_history"

    /// What ZEUS says when Chrome answers with this error.
    public var spokenMessage: String {
        switch code {
        case Self.staleElements:
            "The page changed since I looked at it, so I didn't touch anything. Ask me again and I'll take a fresh look."
        case Self.noHistory:
            message ?? "There's no page to go to in that direction."
        default:
            message ?? code
        }
    }
}

public struct BridgeResponse: Codable, Equatable, Sendable {
    public let id: String
    public let ok: Bool
    public let result: JSONValue?
    public let error: BridgeError?

    public init(id: String, ok: Bool, result: JSONValue? = nil, error: BridgeError? = nil) {
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
    }

    public static func success(_ id: String, _ result: JSONValue? = nil) -> BridgeResponse {
        BridgeResponse(id: id, ok: true, result: result)
    }

    public static func failure(_ id: String, _ error: BridgeError) -> BridgeResponse {
        BridgeResponse(id: id, ok: false, error: error)
    }
}

/// Chrome native messaging framing: a 4-byte length in native byte order, then UTF-8 JSON.
public enum NativeMessagingFrame {
    /// Chrome rejects messages larger than this from a native host.
    public static let maxHostToChromeBytes = 1024 * 1024

    public enum FrameError: Error, Equatable {
        case tooLarge(Int)
    }

    public static func encode(_ json: Data) throws -> Data {
        guard json.count <= maxHostToChromeBytes else { throw FrameError.tooLarge(json.count) }
        var length = UInt32(json.count).littleEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(json)
        return frame
    }

    /// Removes and returns every complete message at the front of `buffer`.
    public static func decode(_ buffer: inout Data) -> [Data] {
        var messages: [Data] = []
        while buffer.count >= 4 {
            let header = buffer.prefix(4)
            let length = header.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
            guard buffer.count >= 4 + length else { break }
            let start = buffer.startIndex + 4
            messages.append(Data(buffer[start..<(start + length)]))
            buffer = Data(buffer[(start + length)...])
        }
        return messages
    }
}
