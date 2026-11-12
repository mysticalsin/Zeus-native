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
    /// Zeus's inbound limit matches its local socket transport. This is not Chrome's platform limit.
    public static let maxChromeToHostBytes = 4 * 1024 * 1024
    public static let maxReadChunkBytes = 16 * 1024

    public enum FrameError: Error, Equatable, Sendable {
        case tooLarge(Int)
        case emptyFrame
        case truncatedFrame
        case decoderClosed
    }

    public static func encode(_ json: Data) throws -> Data {
        guard !json.isEmpty else { throw FrameError.emptyFrame }
        guard json.count <= maxHostToChromeBytes else { throw FrameError.tooLarge(json.count) }
        var length = UInt32(json.count).littleEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(json)
        return frame
    }

    /// Bounded convenience for an already buffered read. Streaming callers should use Decoder,
    /// which emits one frame at a time and never builds an array of peer-controlled messages.
    public static func decode(_ buffer: inout Data) throws -> [Data] {
        guard buffer.count <= maxChromeToHostBytes + maxReadChunkBytes + 4 else {
            throw FrameError.tooLarge(buffer.count)
        }
        var messages: [Data] = []
        var cursor = buffer.startIndex
        while buffer.endIndex - cursor >= 4 {
            let length = try inboundLength(buffer[cursor..<(cursor + 4)])
            guard buffer.endIndex - cursor - 4 >= length else { break }
            let start = cursor + 4
            messages.append(Data(buffer[start..<(start + length)]))
            cursor = start + length
        }
        // One removal, rather than copying the remaining buffer after every tiny frame.
        buffer = Data(buffer[cursor...])
        return messages
    }

    private static func inboundLength(_ header: Data) throws -> Int {
        let raw = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard raw > 0 else { throw FrameError.emptyFrame }
        guard raw <= UInt32(maxChromeToHostBytes) else {
            throw FrameError.tooLarge(Int(exactly: raw) ?? Int.max)
        }
        return Int(raw)
    }

    /// Incremental, fail-closed native-message framing. A header is validated before any body
    /// bytes are retained, and a complete body is released before invoking the receiver.
    /// JSON/schema validation belongs to the receiver; an error there also closes this decoder.
    public struct Decoder: Sendable {
        private var header = Data()
        private var body = Data()
        private var expectedLength: Int?
        private var closed = false

        public init() {}

        public var bufferedByteCount: Int { header.count + body.count }

        public mutating func consume(_ chunk: Data, receive: (Data) throws -> Void) throws {
            guard !closed else { throw FrameError.decoderClosed }
            do {
                var cursor = chunk.startIndex
                while cursor < chunk.endIndex {
                    if expectedLength == nil {
                        let length = min(4 - header.count, chunk.endIndex - cursor)
                        header.append(contentsOf: chunk[cursor..<(cursor + length)])
                        cursor += length
                        guard header.count == 4 else { return }
                        expectedLength = try NativeMessagingFrame.inboundLength(header)
                        header = Data()
                    }
                    guard let expectedLength else { throw FrameError.decoderClosed }
                    let length = min(expectedLength - body.count, chunk.endIndex - cursor)
                    body.append(contentsOf: chunk[cursor..<(cursor + length)])
                    cursor += length
                    if body.count == expectedLength {
                        let complete = body
                        body = Data()
                        self.expectedLength = nil
                        try receive(complete)
                    }
                }
            } catch {
                close()
                throw error
            }
        }

        /// A clean EOF is terminal; incomplete bytes are rejected and immediately released.
        public mutating func finish() throws {
            guard !closed else { throw FrameError.decoderClosed }
            let truncated = !header.isEmpty || expectedLength != nil
            close()
            if truncated { throw FrameError.truncatedFrame }
        }

        private mutating func close() {
            closed = true
            header = Data()
            body = Data()
            expectedLength = nil
        }
    }
}
