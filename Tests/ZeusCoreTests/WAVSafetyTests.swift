import Foundation
import Testing
@testable import ZeusCore

@Suite("Saved WAV container safety")
struct WAVSafetyTests {
    private func number<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
    private func chunk(_ id: String, _ body: Data, declared: UInt32? = nil, padding: Bool = true) -> Data {
        var result = Data(id.utf8) + number(declared ?? UInt32(body.count)) + body
        if padding && body.count % 2 == 1 { result.append(0) }
        return result
    }
    private func wave(_ chunks: Data) -> Data {
        Data("RIFF".utf8) + number(UInt32(chunks.count + 4)) + Data("WAVE".utf8) + chunks
    }
    private var format: Data { Data(WAVFile.encode([])[20..<36]) }
    private var pcm: Data { Data([0, 0, 0xff, 0x7f, 0, 0x80]) }

    @Test func truncatedFormatBodyAtEndOfAValidSizeContainerReturnsNil() {
        let malformed = wave(chunk("JUNK", Data(repeating: 0, count: 16))
            + chunk("fmt ", Data(), declared: 16))
        #expect(malformed.count == 44)
        #expect(WAVFile.decode(malformed) == nil)
    }

    @Test func everyTruncatedPrefixAndOversizedChunkIsRejected() {
        let valid = WAVFile.encode([0, 0.5, -0.5, 1])
        for length in 0..<valid.count { #expect(WAVFile.decode(Data(valid.prefix(length))) == nil) }
        for size in [UInt32(17), 100, UInt32.max] {
            #expect(WAVFile.decode(wave(chunk("fmt ", format, declared: size) + chunk("data", pcm))) == nil)
            #expect(WAVFile.decode(wave(chunk("fmt ", format) + chunk("data", pcm, declared: size))) == nil)
        }
    }

    @Test func formatIsRequiredAndMustDescribeMonoSixteenBitPCM() {
        #expect(WAVFile.decode(wave(chunk("data", Data(repeating: 0, count: 32)))) == nil)
        for (offset, value) in [(0, UInt16(3)), (2, 2), (12, 4), (14, 32)] {
            var invalid = format
            invalid.replaceSubrange(offset..<offset + 2, with: number(value))
            #expect(WAVFile.decode(wave(chunk("fmt ", invalid) + chunk("data", pcm))) == nil)
        }
        for offset in [4, 8] {
            var invalid = format
            invalid.replaceSubrange(offset..<offset + 4, with: number(UInt32(0)))
            #expect(WAVFile.decode(wave(chunk("fmt ", invalid) + chunk("data", pcm))) == nil)
        }
        #expect(WAVFile.decode(wave(chunk("fmt ", format) + chunk("fmt ", format) + chunk("data", pcm))) == nil)
    }

    @Test func partialOrDuplicateSamplesAreNeverReturnedAsSuccessfulAudio() {
        #expect(WAVFile.decode(wave(chunk("fmt ", format) + chunk("data", Data([0])))) == nil)
        #expect(WAVFile.decode(wave(chunk("fmt ", format) + chunk("data", pcm, declared: 8))) == nil)
        #expect(WAVFile.decode(wave(chunk("fmt ", format) + chunk("data", pcm) + chunk("data", pcm))) == nil)
    }

    @Test func paddedUnknownChunksAndNonzeroIndexDataRemainReadable() throws {
        let valid = wave(chunk("JUNK", Data([7])) + chunk("fmt ", format) + chunk("data", pcm)
            + chunk("LIST", Data([9])))
        let decoded = try #require(WAVFile.decode(valid))
        #expect(decoded.sampleRate == 16_000)
        #expect(decoded.samples == [0, 1, -1])
        let prefixed = Data(repeating: 0xff, count: 5) + valid
        let slice = prefixed.dropFirst(5)
        #expect(slice.startIndex != 0)
        #expect(WAVFile.decode(slice)?.samples == decoded.samples)
        let missingPadding = wave(chunk("fmt ", format) + chunk("data", pcm) + chunk("JUNK", Data([7]), padding: false))
        #expect(WAVFile.decode(missingPadding) == nil)
    }

    @Test func emptyEncodedAudioRemainsValidAndDeclaredContainerCannotHideTruncation() throws {
        let empty = try #require(WAVFile.decode(WAVFile.encode([])))
        #expect(empty.samples.isEmpty && empty.sampleRate == 16_000)
        var invalid = WAVFile.encode([0, 1])
        invalid.replaceSubrange(4..<8, with: number(UInt32.max))
        #expect(WAVFile.decode(invalid) == nil)
        invalid.replaceSubrange(4..<8, with: number(UInt32(36)))
        #expect(WAVFile.decode(invalid) == nil)
    }
}
