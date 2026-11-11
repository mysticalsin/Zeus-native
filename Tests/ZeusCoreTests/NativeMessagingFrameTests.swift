import Foundation
import Testing
@testable import ZeusCore

/// Synthetic bytes only: no browser, subprocess, socket, capture or user configuration.
@Suite("Bounded native messaging frames")
struct NativeMessagingFrameTests {
    private func header(_ length: UInt32) -> Data {
        var value = length.littleEndian
        return Data(bytes: &value, count: 4)
    }

    @Test func oversizedHeaderIsRejectedBeforeAnyDeclaredBodyIsBuffered() throws {
        for size in [UInt32(NativeMessagingFrame.maxChromeToHostBytes + 1), UInt32.max] {
            var decoder = NativeMessagingFrame.Decoder()
            let bytes = header(size)
            var deliveries = 0
            for byte in bytes.prefix(3) {
                try decoder.consume(Data([byte])) { _ in deliveries += 1 }
            }
            #expect(decoder.bufferedByteCount == 3)
            #expect(throws: NativeMessagingFrame.FrameError.tooLarge(Int(size))) {
                try decoder.consume(Data(bytes.suffix(1))) { _ in deliveries += 1 }
            }
            #expect(deliveries == 0 && decoder.bufferedByteCount == 0)
            #expect(throws: NativeMessagingFrame.FrameError.decoderClosed) {
                try decoder.consume(try NativeMessagingFrame.encode(Data("{}".utf8))) { _ in deliveries += 1 }
            }
            #expect(deliveries == 0, "A framing error cannot resynchronize into later peer bytes")
        }
    }

    @Test func zeroLengthFramesFailClosedInBothDirections() {
        var decoder = NativeMessagingFrame.Decoder()
        #expect(throws: NativeMessagingFrame.FrameError.emptyFrame) {
            try decoder.consume(header(0)) { _ in Issue.record("Empty frame was delivered") }
        }
        #expect(decoder.bufferedByteCount == 0)
        #expect(throws: NativeMessagingFrame.FrameError.emptyFrame) {
            try NativeMessagingFrame.encode(Data())
        }
    }

    @Test func everyFragmentBoundaryPreservesConcatenatedUnicodeMessagesExactly() throws {
        let messages = [Data(#"{"id":"a","text":"Résumé 🦉"}"#.utf8), Data(#"{"id":"b","ok":true}"#.utf8)]
        let bytes = try messages.reduce(into: Data()) { $0.append(try NativeMessagingFrame.encode($1)) }
        for split in 0...bytes.count {
            var decoder = NativeMessagingFrame.Decoder()
            var received: [Data] = []
            try decoder.consume(Data(bytes.prefix(split))) { received.append($0) }
            try decoder.consume(Data(bytes.dropFirst(split))) { received.append($0) }
            try decoder.finish()
            #expect(received == messages)
            #expect(decoder.bufferedByteCount == 0)
        }
        // Data slices may have a nonzero startIndex, unlike newly constructed buffers.
        var padded = Data([0xFF, 0xFF])
        padded.append(bytes)
        var slicedDecoder = NativeMessagingFrame.Decoder()
        var sliced: [Data] = []
        try slicedDecoder.consume(padded.dropFirst(2)) { sliced.append($0) }
        try slicedDecoder.finish()
        #expect(sliced == messages)
    }

    @Test func maximumInboundFrameStreamsWithoutExceedingItsBodyBudget() throws {
        let limit = NativeMessagingFrame.maxChromeToHostBytes
        let body = Data([0x22]) + Data(repeating: 0x61, count: limit - 2) + Data([0x22])
        var decoder = NativeMessagingFrame.Decoder()
        var received: [Data] = []
        try decoder.consume(header(UInt32(limit))) { received.append($0) }
        #expect(decoder.bufferedByteCount == 0, "A validated header must not retain any body bytes")
        var offset = 0
        while offset < body.count {
            let end = min(body.count, offset + NativeMessagingFrame.maxReadChunkBytes)
            try decoder.consume(Data(body[offset..<end])) { received.append($0) }
            #expect(decoder.bufferedByteCount <= limit)
            if end < body.count { #expect(received.isEmpty) }
            offset = end
        }
        try decoder.finish()
        #expect(received == [body])
        #expect(decoder.bufferedByteCount == 0)
        // Zeus's inbound cap is deliberately independent of Chrome's smaller outbound cap.
        #expect(throws: NativeMessagingFrame.FrameError.tooLarge(limit)) {
            try NativeMessagingFrame.encode(body)
        }
    }

    @Test func truncatedEOFRejectsHeaderAndBodyAndReleasesRetainedBytes() throws {
        let incomplete = [Data([0x05]), Data([0x05, 0]), Data([0x05, 0, 0]), header(5), header(5) + Data("abc".utf8)]
        for bytes in incomplete {
            var decoder = NativeMessagingFrame.Decoder()
            try decoder.consume(bytes) { _ in Issue.record("Incomplete frame was delivered") }
            #expect(throws: NativeMessagingFrame.FrameError.truncatedFrame) { try decoder.finish() }
            #expect(decoder.bufferedByteCount == 0)
            #expect(throws: NativeMessagingFrame.FrameError.decoderClosed) {
                try decoder.consume(Data()) { _ in Issue.record("Closed decoder delivered a frame") }
            }
        }
        var clean = NativeMessagingFrame.Decoder()
        try clean.finish()
        #expect(throws: NativeMessagingFrame.FrameError.decoderClosed) {
            try clean.consume(Data()) { _ in Issue.record("EOF was not terminal") }
        }
    }

    @Test func receiverFailureStopsTheSameChunkBeforeItsNextFrame() throws {
        enum Rejected: Error { case invalidJSON }
        var decoder = NativeMessagingFrame.Decoder()
        let bytes = try NativeMessagingFrame.encode(Data("not JSON".utf8)) + NativeMessagingFrame.encode(Data("{}".utf8))
        var received = 0
        #expect(throws: Rejected.invalidJSON) {
            try decoder.consume(bytes) { _ in received += 1; throw Rejected.invalidJSON }
        }
        #expect(received == 1 && decoder.bufferedByteCount == 0)
        #expect(throws: NativeMessagingFrame.FrameError.decoderClosed) {
            try decoder.consume(bytes) { _ in received += 1 }
        }
        #expect(received == 1)
    }

    @Test func batchedConvenienceRejectsOversizedHeadersAndRetainsOnlyIncompleteTail() throws {
        var oversized = header(UInt32.max)
        #expect(throws: NativeMessagingFrame.FrameError.tooLarge(Int(UInt32.max))) {
            try NativeMessagingFrame.decode(&oversized)
        }
        var empty = header(0)
        #expect(throws: NativeMessagingFrame.FrameError.emptyFrame) { try NativeMessagingFrame.decode(&empty) }
        let message = Data("{}".utf8)
        let frame = try NativeMessagingFrame.encode(message)
        var batch = Data()
        for _ in 0..<500 { batch.append(frame) }
        batch.append(contentsOf: [5, 0])
        let decoded = try NativeMessagingFrame.decode(&batch)
        #expect(decoded == Array(repeating: message, count: 500))
        #expect(batch == Data([5, 0]))
    }

    @Test func bufferedConvenienceHasABatchLimitEvenForOtherwiseValidFrames() throws {
        let frame = try NativeMessagingFrame.encode(Data("{}".utf8))
        var bytes = Data(repeating: 0, count: NativeMessagingFrame.maxChromeToHostBytes + NativeMessagingFrame.maxReadChunkBytes + 5)
        bytes.replaceSubrange(0..<frame.count, with: frame)
        let count = bytes.count
        #expect(throws: NativeMessagingFrame.FrameError.tooLarge(count)) {
            try NativeMessagingFrame.decode(&bytes)
        }
        #expect(bytes.count == count, "Invalid batch admission must not partially consume input")
    }
}
