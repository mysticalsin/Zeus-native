import Foundation
import Testing
@testable import ZeusCore

@Suite("Fling wire framing")
struct FlingWireTests {
    private func frame(_ type: UInt8, _ payload: Data) -> Data {
        var d = Data()
        var n = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &n) { d.append(contentsOf: $0) }
        d.append(type)
        d.append(payload)
        return d
    }

    @Test func aFrameIsLengthTypeThenPayload() throws {
        let bytes = FlingWire.encode(type: .stackDone, payload: Data([1, 2, 3]))
        #expect(bytes == frame(FlingMessageType.stackDone.rawValue, Data([1, 2, 3])))
        var decoder = FlingFrameDecoder()
        let frames = try decoder.feed(bytes)
        #expect(frames == [FlingFrame(type: .stackDone, payload: Data([1, 2, 3]))])
    }

    @Test func aFrameSplitAcrossReadsIsReassembledAndTwoFramesInOneReadBothComeOut() throws {
        let a = FlingWire.encode(type: .accept, payload: Data("{}".utf8))
        let b = FlingWire.encode(type: .cancel, payload: Data("{}".utf8))
        let all = a + b
        var decoder = FlingFrameDecoder()
        var got: [FlingFrame] = []
        for byte in all { got += try decoder.feed(Data([byte])) }
        #expect(got.count == 2)
        #expect(got.map(\.type) == [.accept, .cancel])
        var whole = FlingFrameDecoder()
        #expect(try whole.feed(all).count == 2)
        #expect(whole.bufferedByteCount == 0)
    }

    /// REG-660: a header that claims more than the cap is refused from its five header bytes, before any payload is buffered.
    @Test func anOversizedHeaderOrChunkIsRefusedBeforeItsPayloadArrives() throws {
        var decoder = FlingFrameDecoder()
        var n = UInt32(FlingLimits.maxHeaderPayloadBytes + 1).bigEndian
        var head = Data()
        withUnsafeBytes(of: &n) { head.append(contentsOf: $0) }
        head.append(FlingMessageType.offer.rawValue)
        #expect(throws: FlingWireError.frameTooLarge) { try decoder.feed(head) }

        var chunkDecoder = FlingFrameDecoder()
        var m = UInt32(FlingLimits.maxChunkPayloadBytes + 1).bigEndian
        var chunkHead = Data()
        withUnsafeBytes(of: &m) { chunkHead.append(contentsOf: $0) }
        chunkHead.append(FlingMessageType.chunk.rawValue)
        #expect(throws: FlingWireError.frameTooLarge) { try chunkDecoder.feed(chunkHead) }

        // The cap itself is allowed.
        var ok = FlingFrameDecoder()
        var edge = UInt32(FlingLimits.maxChunkPayloadBytes).bigEndian
        var edgeHead = Data()
        withUnsafeBytes(of: &edge) { edgeHead.append(contentsOf: $0) }
        edgeHead.append(FlingMessageType.chunk.rawValue)
        #expect(try ok.feed(edgeHead).isEmpty)
    }

    /// REG-661: after an error the decoder stays failed, so a hostile stream cannot resynchronise into a later frame.
    @Test func aDecoderThatFailedStaysFailed() throws {
        var decoder = FlingFrameDecoder()
        #expect(throws: FlingWireError.unknownType(250)) { try decoder.feed(frame(250, Data())) }
        #expect(throws: FlingWireError.alreadyFailed) { try decoder.feed(FlingWire.encode(type: .accept, payload: Data("{}".utf8))) }
    }

    /// REG-662: a Hello whose version is not 1 is a version error, and a peer's malformed header is a clean failure, not a crash.
    @Test func aWrongVersionAndGarbageHeadersAreRefusedCleanly() throws {
        let good = try FlingWire.encode(.hello(FlingHello(v: 1, id: "A", name: "Mac", model: "Mac15,3")))
        var decoder = FlingFrameDecoder()
        let message = try FlingWire.decode(try #require(try decoder.feed(good).first))
        #expect(message == .hello(FlingHello(v: 1, id: "A", name: "Mac", model: "Mac15,3")))

        let bad = try FlingWire.encode(.hello(FlingHello(v: 2, id: "A", name: "Mac", model: "x")))
        var d2 = FlingFrameDecoder()
        let badFrame = try #require(try d2.feed(bad).first)
        #expect(throws: FlingWireError.version) { try FlingWire.decode(badFrame) }

        let junk = FlingFrame(type: .offer, payload: Data("not json".utf8))
        #expect(throws: FlingWireError.malformed) { try FlingWire.decode(junk) }
    }

    @Test func aChunkCarriesItsIndexAndBytes() throws {
        let chunk = FlingChunk(index: 7, bytes: Data([9, 8, 7]))
        let frame = FlingWire.encode(chunk: chunk)
        var decoder = FlingFrameDecoder()
        let parsed = try #require(try decoder.feed(frame).first)
        #expect(parsed.type == .chunk)
        #expect(try FlingWire.decode(parsed) == .chunk(chunk))
        #expect(throws: FlingWireError.malformed) { try FlingWire.decode(FlingFrame(type: .chunk, payload: Data([1, 2]))) }
    }

    @Test func everyMessageRoundTrips() throws {
        let stack = UUID()
        let items = [
            FlingOfferItem(index: 0, name: "a.png", size: 10, kind: .file, uti: "public.png", sha256: String(repeating: "a", count: 64), url: nil),
            FlingOfferItem(index: 1, name: "Link", size: 0, kind: .link, uti: nil, sha256: String(repeating: "b", count: 64), url: "https://example.com"),
        ]
        let all: [FlingMessage] = [
            .pairCommit(FlingPairCommit(h: "abcd")),
            .pairKey(FlingPairKey(pub: "k")),
            .pairReveal(FlingPairReveal(pub: "k", nonce: "n")),
            .pairConfirm(FlingPairConfirm(mac: "m")),
            .pairDecline(FlingPairDecline(reason: "declined")),
            .offer(FlingOffer(stackID: stack, items: items)),
            .accept(FlingStackRef(stackID: stack)),
            .decline(FlingDecline(stackID: stack, reason: .badName)),
            .fileDone(FlingFileDone(index: 3)),
            .itemResult(FlingItemResult(index: 3, ok: false)),
            .stackDone(FlingStackRef(stackID: stack)),
            .cancel(FlingStackRef(stackID: stack)),
        ]
        for message in all {
            var decoder = FlingFrameDecoder()
            let parsed = try #require(try decoder.feed(try FlingWire.encode(message)).first)
            #expect(try FlingWire.decode(parsed) == message)
        }
    }
}
