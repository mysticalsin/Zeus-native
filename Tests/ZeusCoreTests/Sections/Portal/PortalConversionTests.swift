import Foundation
import Testing
@testable import ZeusCore

@Suite("Portal local conversion")
struct PortalConversionTests {
    @Test func crc32MatchesTheKnownVector() {
        #expect(PortalChecksum.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func textBecomesUTF8WithFoldedNewlines() throws {
        let input = Data("A\r\nB\rC".utf8)
        let output = try #require(try PortalTextConversion.utf8(input).get())
        #expect(String(decoding: output, as: UTF8.self) == "A\nB\nC")
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data("Hello".utf8)
        #expect(try PortalTextConversion.utf8(bom).get() == Data("Hello".utf8))
        let nfd = Data("cafe\u{0301}".utf8)
        #expect(try PortalTextConversion.utf8(nfd).get() == Data("caf\u{00e9}".utf8))
        #expect(PortalTextConversion.utf8(Data([0xFF])) == .failure(.invalidContents))
        #expect(PortalTextConversion.utf8(Data("a\u{0}b".utf8)) == .failure(.invalidContents))
        #expect(PortalTextConversion.utf8(Data("hello".utf8), limit: 4) == .failure(.outputTooLarge))
    }

    @Test func randomTextRoundTripsToNFCAndLF() {
        var mixer = PortalSplitMix(state: 99)
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        for _ in 0..<40 {
            var text = ""
            let count = 1 + mixer.int(24)
            for index in 0..<count {
                if index % 5 == 4 { text += mixer.int(2) == 0 ? "\r\n" : "\r" }
                else { text.append(letters[mixer.int(letters.count)]) }
            }
            let output = PortalTextConversion.utf8(Data(text.utf8))
            guard case .success(let data) = output, let string = String(data: data, encoding: .utf8) else {
                Issue.record("text failed \(text)")
                continue
            }
            #expect(!string.contains("\r"))
            #expect(string.precomposedStringWithCanonicalMapping == string)
            #expect(data.count <= PortalLimits.maxConversionBytes)
        }
    }

    @Test func pngIsSanitizedAndOtherImagesFailClosedWithoutACodec() throws {
        let clean = PortalFixtures.png()
        #expect(try PortalPNG.sanitize(clean).get() == clean)
        let trailed = PortalFixtures.png(trailing: Data([0x00, 0x11]))
        #expect(try PortalPNG.sanitize(trailed).get() == clean)
        var broken = clean
        broken[20] ^= 0x01
        #expect(PortalPNG.sanitize(broken) == .failure(.invalidContents))
        #expect(PortalPNG.sanitize(Data("not a png".utf8)) == .failure(.invalidContents))
        #expect(PortalPNG.sanitize(PortalFixtures.png(width: 100_000, height: 100_000)) == .failure(.tooLarge))
        #expect(PortalPNG.sanitize(PortalFixtures.png(width: 0, height: 1)) == .failure(.invalidContents))

        let pngClaim = PortalFixtures.claim(name: "dot.png", type: .png, size: Int64(clean.count))
        let kept = PortalDropSession.run(claim: .success(pngClaim), bytes: clean)
        #expect(kept.phase == .done(PortalConversionOutput(fileName: "dot.png", bytes: clean, kind: .png)))

        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let photo = PortalFixtures.claim(name: "photo.jpg", type: .jpeg, size: Int64(jpeg.count))
        #expect(PortalDropSession.run(claim: .success(photo), bytes: jpeg).phase == .failed(.systemCodecUnavailable))

        let disguised = PortalFixtures.claim(name: "note.txt", type: .plainText, size: Int64(clean.count))
        #expect(PortalDropSession.run(claim: .success(disguised), bytes: clean).phase == .failed(.invalidContents))
    }

    @Test func anInjectedCodecCanFinishAnImageTheSystemCannot() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let png = PortalFixtures.png()
        let codecs = PortalCodecs(images: FixedPNG(data: png))
        let claim = PortalFixtures.claim(name: "photo.jpg", type: .jpeg, size: Int64(jpeg.count))
        let flow = PortalDropSession.run(claim: .success(claim), bytes: jpeg, codecs: codecs)
        #expect(flow.phase == .done(PortalConversionOutput(fileName: "photo.png", bytes: png, kind: .png)))

        let garbage = PortalCodecs(images: FixedPNG(data: Data("nope".utf8)))
        #expect(PortalDropSession.run(claim: .success(claim), bytes: jpeg, codecs: garbage).phase == .failed(.invalidContents))
    }

    @Test func outputNamesLoseSeparators() throws {
        #expect(try PortalOutputName.make(displayName: "note.txt", kind: .utf8Text).get() == "note.txt")
        #expect(try PortalOutputName.make(displayName: "photo.jpg", kind: .png).get() == "photo.png")
        let nested = try #require(try PortalOutputName.make(displayName: "../secret", kind: .utf8Text).get())
        #expect(!nested.contains("/"))
        #expect(!nested.contains("\\"))
        #expect(FlingNames.validate(nested).isOK)
        let empty = try #require(try PortalOutputName.make(displayName: "", kind: .png).get())
        #expect(empty == "File.png")
    }

    @Test func trayAcceptsOneHundredAndThenFails() {
        var tray = PortalTray()
        for index in 0..<PortalLimits.maxTrayItems {
            let name = "n\(index).txt"
            let bytes = Data("ok".utf8)
            let claim = PortalFixtures.claim(name: name, size: Int64(bytes.count))
            #expect(tray.receive(.success(claim)) == .applied)
            #expect(tray.begin() == .applied)
            let output = PortalConversionOutput(fileName: name, bytes: bytes, kind: .utf8Text)
            #expect(tray.finish(.success(output)) == .applied)
            #expect(tray.reset() == .applied)
        }
        #expect(tray.items.count == PortalLimits.maxTrayItems)
        #expect(tray.receive(.success(PortalFixtures.claim(name: "overflow.txt"))) == .applied)
        #expect(tray.flow.phase == .failed(.trayFull))
    }

    @Test func dragDecisionsCoverTheBoundaries() {
        let one = PortalDrag.decide(PortalDragOffer(fileCount: 1, includesNonFile: false, sizes: [1]))
        #expect(one == .accept(1))
        #expect(PortalDrag.decide(PortalDragOffer(fileCount: 0, includesNonFile: false, sizes: [])) == .refuse(.empty))
        #expect(PortalDrag.decide(PortalDragOffer(fileCount: 0, includesNonFile: true, sizes: [])) == .refuse(.notAFile))
        #expect(PortalDrag.decide(PortalDragOffer(fileCount: 1, includesNonFile: true, sizes: [1])) == .refuse(.mixed))
        #expect(PortalDrag.decide(PortalDragOffer(fileCount: 101, includesNonFile: false, sizes: Array(repeating: 1, count: 101))) == .refuse(.tooMany))
        #expect(PortalDrag.decide(PortalDragOffer(fileCount: 1, includesNonFile: false, sizes: [Int64(PortalLimits.maxConversionBytes)])) == .accept(1))
        #expect(PortalDrag.decide(PortalDragOffer(fileCount: 1, includesNonFile: false, sizes: [Int64(PortalLimits.maxConversionBytes) + 1])) == .refuse(.itemTooLarge))
        #expect(PortalDrag.decide(PortalDragOffer(fileCount: 1, includesNonFile: false, sizes: [0])) == .refuse(.emptyItem))
        #expect(PortalDrag.decide(PortalDragOffer(fileCount: 1, includesNonFile: false, sizes: [-1])) == .refuse(.unreadableSize))
        #expect(PortalLimits.maxTrayItems == 100)
        #expect(PortalLimits.maxConversionBytes == 8 * 1024 * 1024)
    }
}

private struct FixedPNG: PortalImageCoding {
    var data: Data
    func pngData(from data: Data, type: PortalFileType) -> Result<Data, PortalDropFailure> {
        .success(self.data)
    }
}

private extension Result where Success == String, Failure == FlingNameError {
    var isOK: Bool {
        if case .success = self { return true }
        return false
    }
}
