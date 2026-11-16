import Foundation

public enum FlingWireError: Error, Equatable, Sendable {
    case frameTooLarge
    case unknownType(UInt8)
    case malformed
    case version
    /// The decoder saw a bad frame earlier and refuses everything after it.
    case alreadyFailed
}

public enum FlingMessageType: UInt8, Sendable {
    case hello = 1, pairCommit, pairKey, pairReveal, pairConfirm, pairDecline
    case offer, accept, decline, chunk, fileDone, itemResult, stackDone, cancel

    /// The largest payload this type may carry.
    var payloadCap: Int { self == .chunk ? FlingLimits.maxChunkPayloadBytes : FlingLimits.maxHeaderPayloadBytes }
}

public struct FlingFrame: Equatable, Sendable {
    public let type: FlingMessageType
    public let payload: Data
    public init(type: FlingMessageType, payload: Data) { self.type = type; self.payload = payload }
}

public enum FlingDeclineReason: String, Codable, Equatable, Sendable {
    case version, notPaired, badName, tooMany, malformed, badLink, diskFull, declined, timeout, replay, busy, overSize, hashMismatch, peerLost
}

public enum FlingItemKind: String, Codable, Equatable, Sendable { case file, link }

public struct FlingHello: Codable, Equatable, Sendable {
    public var v: Int, id: String, name: String, model: String
    /// A receiver's hello carries a fresh nonce; the sender answers with a `proof` over it (see `FlingCrypto.helloProof`).
    public var nonce: String?, proof: String?
    public init(v: Int = FlingLimits.protocolVersion, id: String, name: String, model: String, nonce: String? = nil, proof: String? = nil) {
        self.v = v; self.id = id; self.name = name; self.model = model; self.nonce = nonce; self.proof = proof
    }
}
public struct FlingPairCommit: Codable, Equatable, Sendable { public var h: String; public init(h: String) { self.h = h } }
public struct FlingPairKey: Codable, Equatable, Sendable { public var pub: String; public init(pub: String) { self.pub = pub } }
public struct FlingPairReveal: Codable, Equatable, Sendable {
    public var pub: String, nonce: String
    public init(pub: String, nonce: String) { self.pub = pub; self.nonce = nonce }
}
public struct FlingPairConfirm: Codable, Equatable, Sendable { public var mac: String; public init(mac: String) { self.mac = mac } }
public struct FlingPairDecline: Codable, Equatable, Sendable { public var reason: String; public init(reason: String) { self.reason = reason } }

public struct FlingOfferItem: Codable, Equatable, Sendable {
    public var index: Int
    public var name: String
    public var size: Int64
    public var kind: FlingItemKind
    public var uti: String?
    public var sha256: String
    public var url: String?
    public init(index: Int, name: String, size: Int64, kind: FlingItemKind, uti: String?, sha256: String, url: String?) {
        self.index = index; self.name = name; self.size = size; self.kind = kind; self.uti = uti; self.sha256 = sha256; self.url = url
    }
}
public struct FlingOffer: Codable, Equatable, Sendable {
    public var stackID: UUID
    public var items: [FlingOfferItem]
    public init(stackID: UUID, items: [FlingOfferItem]) { self.stackID = stackID; self.items = items }
}
public struct FlingStackRef: Codable, Equatable, Sendable { public var stackID: UUID; public init(stackID: UUID) { self.stackID = stackID } }
public struct FlingDecline: Codable, Equatable, Sendable {
    public var stackID: UUID, reason: FlingDeclineReason
    public init(stackID: UUID, reason: FlingDeclineReason) { self.stackID = stackID; self.reason = reason }
}
public struct FlingFileDone: Codable, Equatable, Sendable { public var index: Int; public init(index: Int) { self.index = index } }
public struct FlingItemResult: Codable, Equatable, Sendable {
    public var index: Int, ok: Bool
    public init(index: Int, ok: Bool) { self.index = index; self.ok = ok }
}
/// A chunk payload is a 4-byte big-endian item index followed by the data.
public struct FlingChunk: Equatable, Sendable {
    public var index: UInt32, bytes: Data
    public init(index: UInt32, bytes: Data) { self.index = index; self.bytes = bytes }
}

public enum FlingMessage: Equatable, Sendable {
    case hello(FlingHello), pairCommit(FlingPairCommit), pairKey(FlingPairKey), pairReveal(FlingPairReveal)
    case pairConfirm(FlingPairConfirm), pairDecline(FlingPairDecline)
    case offer(FlingOffer), accept(FlingStackRef), decline(FlingDecline), chunk(FlingChunk)
    case fileDone(FlingFileDone), itemResult(FlingItemResult), stackDone(FlingStackRef), cancel(FlingStackRef)
}

public enum FlingWire {
    public static func encode(type: FlingMessageType, payload: Data) -> Data {
        var data = Data(capacity: 5 + payload.count)
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(type.rawValue)
        data.append(payload)
        return data
    }

    public static func encode(chunk: FlingChunk) -> Data {
        var payload = Data(capacity: 4 + chunk.bytes.count)
        var index = chunk.index.bigEndian
        withUnsafeBytes(of: &index) { payload.append(contentsOf: $0) }
        payload.append(chunk.bytes)
        return encode(type: .chunk, payload: payload)
    }

    private static func json<T: Encodable>(_ type: FlingMessageType, _ value: T) throws(FlingWireError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let payload = try? encoder.encode(value), payload.count <= FlingLimits.maxHeaderPayloadBytes else { throw .frameTooLarge }
        return encode(type: type, payload: payload)
    }

    public static func encode(_ message: FlingMessage) throws(FlingWireError) -> Data {
        switch message {
        case .hello(let m): return try json(.hello, m)
        case .pairCommit(let m): return try json(.pairCommit, m)
        case .pairKey(let m): return try json(.pairKey, m)
        case .pairReveal(let m): return try json(.pairReveal, m)
        case .pairConfirm(let m): return try json(.pairConfirm, m)
        case .pairDecline(let m): return try json(.pairDecline, m)
        case .offer(let m): return try json(.offer, m)
        case .accept(let m): return try json(.accept, m)
        case .decline(let m): return try json(.decline, m)
        case .chunk(let m): return encode(chunk: m)
        case .fileDone(let m): return try json(.fileDone, m)
        case .itemResult(let m): return try json(.itemResult, m)
        case .stackDone(let m): return try json(.stackDone, m)
        case .cancel(let m): return try json(.cancel, m)
        }
    }

    private static func parse<T: Decodable>(_ type: T.Type, _ frame: FlingFrame) throws(FlingWireError) -> T {
        guard let value = try? JSONDecoder().decode(T.self, from: frame.payload) else { throw .malformed }
        return value
    }

    public static func decode(_ frame: FlingFrame) throws(FlingWireError) -> FlingMessage {
        switch frame.type {
        case .hello:
            let hello = try parse(FlingHello.self, frame)
            guard hello.v == FlingLimits.protocolVersion else { throw .version }
            return .hello(hello)
        case .pairCommit: return .pairCommit(try parse(FlingPairCommit.self, frame))
        case .pairKey: return .pairKey(try parse(FlingPairKey.self, frame))
        case .pairReveal: return .pairReveal(try parse(FlingPairReveal.self, frame))
        case .pairConfirm: return .pairConfirm(try parse(FlingPairConfirm.self, frame))
        case .pairDecline: return .pairDecline(try parse(FlingPairDecline.self, frame))
        case .offer: return .offer(try parse(FlingOffer.self, frame))
        case .accept: return .accept(try parse(FlingStackRef.self, frame))
        case .decline: return .decline(try parse(FlingDecline.self, frame))
        case .chunk:
            // A chunk with an index and no data carries nothing.
            guard frame.payload.count > 4 else { throw .malformed }
            let index = frame.payload.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return .chunk(FlingChunk(index: index, bytes: frame.payload.dropFirst(4)))
        case .fileDone: return .fileDone(try parse(FlingFileDone.self, frame))
        case .itemResult: return .itemResult(try parse(FlingItemResult.self, frame))
        case .stackDone: return .stackDone(try parse(FlingStackRef.self, frame))
        case .cancel: return .cancel(try parse(FlingStackRef.self, frame))
        }
    }
}

/// Incremental frame decoder. A frame's declared length is checked against its type's cap from the five header
/// bytes alone, so a hostile peer cannot make the receiver buffer an oversized payload.
public struct FlingFrameDecoder: Sendable {
    private var buffer = Data()
    private var failed = false
    public init() {}

    public var bufferedByteCount: Int { buffer.count }

    public mutating func feed(_ data: Data) throws(FlingWireError) -> [FlingFrame] {
        if failed { throw .alreadyFailed }
        buffer.append(data)
        var frames: [FlingFrame] = []
        // Frames are read at a moving offset and the buffer is compacted once at the end, so a long run of small
        // frames costs one pass instead of a copy of the rest of the buffer per frame.
        var offset = buffer.startIndex
        let end = buffer.endIndex
        while end - offset >= 5 {
            let length = Int(buffer[offset]) << 24 | Int(buffer[offset + 1]) << 16 | Int(buffer[offset + 2]) << 8 | Int(buffer[offset + 3])
            let rawType = buffer[offset + 4]
            guard let type = FlingMessageType(rawValue: rawType) else { failed = true; buffer.removeAll(); throw .unknownType(rawType) }
            guard length <= type.payloadCap else { failed = true; buffer.removeAll(); throw .frameTooLarge }
            guard end - offset >= 5 + length else { break }
            frames.append(FlingFrame(type: type, payload: Data(buffer[(offset + 5)..<(offset + 5 + length)])))
            offset += 5 + length
        }
        if offset > buffer.startIndex { buffer = Data(buffer[offset...]) }
        return frames
    }
}

/// What a receiver checks in an offer before it ever prompts. Returns the decline reason, or nil when the offer is fine.
public enum FlingOfferRules {
    public static func validate(_ offer: FlingOffer, freeBytes: Int64) -> FlingDeclineReason? {
        let items = offer.items
        guard !items.isEmpty, items.count <= FlingLimits.maxItems else { return .tooMany }
        guard Set(items.map(\.index)) == Set(0..<items.count) else { return .malformed }
        for item in items {
            if case .failure = FlingNames.validate(item.name) { return .badName }
            guard item.size >= 0, item.size <= FlingLimits.maxItemBytes, isSHA256Hex(item.sha256) else { return .malformed }
            if item.kind == .link {
                guard item.size == 0 else { return .malformed }
                guard let text = item.url, isWebLink(text) else { return .badLink }
            }
        }
        // Only now, with every size known to be sane, are they added up, and an overflow is "no room".
        var total: Int64 = 0
        for item in items where item.kind == .file {
            let (sum, overflow) = total.addingReportingOverflow(item.size)
            if overflow { return .diskFull }
            total = sum
        }
        let (room, overflow) = freeBytes.subtractingReportingOverflow(FlingLimits.freeSpaceReserveBytes)
        if overflow || total > room { return .diskFull }
        return nil
    }

    /// The bytes of all files, saturating at Int64.max instead of overflowing; for a prompt, never for a decision.
    public static func totalFileBytes(_ offer: FlingOffer) -> Int64 {
        offer.items.filter { $0.kind == .file }.reduce(Int64(0)) {
            let (sum, overflow) = $0.addingReportingOverflow($1.size)
            return overflow ? Int64.max : sum
        }
    }

    static func isSHA256Hex(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }

    /// http or https with a host, at most 2048 characters.
    public static func isWebLink(_ text: String) -> Bool {
        guard text.count <= FlingLimits.maxLinkLength, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }
}
