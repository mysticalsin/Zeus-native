import Foundation
import Testing
@testable import ZeusCore

@Suite("Fling file names and offer limits")
struct FlingNamesTests {
    /// REG-667: a name that could leave the stack folder declines the whole offer.
    @Test(arguments: ["../evil.txt", "a/b", "a\\b", "a:b", "..", ".", ".hidden", "", "nul\u{0}byte", "tab\tname", "line\nbreak", "esc\u{1B}x", "\u{7F}"])
    func unsafeNamesAreRejected(_ name: String) {
        #expect(FlingNames.validate(name) == .failure(.unsafe))
    }

    @Test func aTooLongNameIsRejectedByUTF8BytesAfterNFC() {
        #expect(FlingNames.validate(String(repeating: "a", count: 255)) == .success(String(repeating: "a", count: 255)))
        #expect(FlingNames.validate(String(repeating: "a", count: 256)) == .failure(.tooLong))
        // 128 two-byte characters is 256 bytes.
        #expect(FlingNames.validate(String(repeating: "é", count: 128)) == .failure(.tooLong))
        // Decomposed e + combining accent is 3 bytes, but NFC makes it 2, so 127 of them fit.
        let decomposed = String(repeating: "e\u{301}", count: 127)
        #expect(FlingNames.validate(decomposed) == .success(String(repeating: "é", count: 127)))
    }

    @Test func ordinaryNamesPassUnchanged() {
        for name in ["photo.png", "Report final (2).pdf", "日本語.txt", "no extension", "a.b.c"] {
            #expect(FlingNames.validate(name) == .success(name.precomposedStringWithCanonicalMapping))
        }
    }

    @Test func aSenderCleansItsOwnNamesIntoValidOnes() {
        for dirty in ["../evil.txt", "a/b:c", ".hidden", "", "..", "x\u{0}y", String(repeating: "a", count: 400)] {
            let clean = FlingNames.clean(dirty)
            #expect(FlingNames.validate(clean) == .success(clean), "\(dirty.debugDescription) -> \(clean.debugDescription)")
        }
        #expect(FlingNames.clean("a/b") == "a_b")
        #expect(FlingNames.clean("photo.png") == "photo.png")
    }

    @Test func aFreeNameAppendsANumberBeforeTheExtension() {
        #expect(FlingNames.freeName("a.png", taken: []) == "a.png")
        #expect(FlingNames.freeName("a.png", taken: ["a.png"]) == "a 2.png")
        #expect(FlingNames.freeName("a.png", taken: ["a.png", "a 2.png"]) == "a 3.png")
        #expect(FlingNames.freeName("noext", taken: ["noext"]) == "noext 2")
    }

    @Test func theFinalPathMustStayInsideTheStackFolder() {
        let root = URL(fileURLWithPath: "/tmp/Fling/Stack")
        #expect(FlingNames.isContained(root.appendingPathComponent("a.png"), in: root))
        #expect(!FlingNames.isContained(root.appendingPathComponent("../x"), in: root))
        #expect(!FlingNames.isContained(URL(fileURLWithPath: "/tmp/Fling/Stack2/a"), in: root))
        #expect(!FlingNames.isContained(root, in: root))
    }

    @Test func aSymlinkCannotEscapeTheRealRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fling-root-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("fling-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(!FlingNames.isContained(link, in: root))
        #expect(!FlingNames.isContained(link.appendingPathComponent("secret.txt"), in: root))
    }
}

@Suite("Fling offer validation")
struct FlingOfferValidationTests {
    private func file(_ i: Int, name: String = "f.bin", size: Int64 = 10) -> FlingOfferItem {
        FlingOfferItem(index: i, name: name, size: size, kind: .file, uti: nil, sha256: String(repeating: "0", count: 64), url: nil)
    }
    private func link(_ i: Int, _ url: String) -> FlingOfferItem {
        FlingOfferItem(index: i, name: "Link", size: 0, kind: .link, uti: nil, sha256: String(repeating: "0", count: 64), url: url)
    }
    private func check(_ items: [FlingOfferItem], free: Int64 = 100 * 1024 * 1024 * 1024) -> FlingDeclineReason? {
        FlingOfferRules.validate(FlingOffer(stackID: UUID(), items: items), freeBytes: free)
    }

    /// REG-668: more than 100 items, or none, declines the offer.
    @Test func theItemCountIsBoundedAtOneHundred() {
        #expect(check((0..<100).map { file($0, name: "f\($0)") }) == nil)
        #expect(check((0..<101).map { file($0, name: "f\($0)") }) == .tooMany)
        #expect(check([]) == .tooMany)
    }

    @Test func aBadNameDeclinesTheWholeOffer() {
        #expect(check([file(0), file(1, name: "../evil.txt")]) == .badName)
    }

    @Test func indexesMustBeUniqueAndInRange() {
        #expect(check([file(0), file(0, name: "g")]) == .malformed)
        #expect(check([file(0), file(5, name: "g")]) == .malformed)
        #expect(check([file(1, name: "g"), file(0)]) == nil)
    }

    @Test func aNegativeSizeOrBadHashIsMalformed() {
        #expect(check([file(0, size: -1)]) == .malformed)
        let bad = FlingOfferItem(index: 0, name: "f", size: 1, kind: .file, uti: nil, sha256: "xyz", url: nil)
        #expect(check([bad]) == .malformed)
    }

    /// REG-693: links are http or https only and at most 2048 characters; a link carries no bytes.
    @Test func linksAreHttpOrHttpsAndBounded() {
        #expect(check([link(0, "https://example.com/a?b=c")]) == nil)
        #expect(check([link(0, "http://example.com")]) == nil)
        for bad in ["file:///etc/passwd", "javascript:alert(1)", "ftp://x.y", "zeus://thing", "example.com", "https://", "not a url"] {
            #expect(check([link(0, bad)]) == .badLink, "\(bad)")
        }
        let long = "https://example.com/" + String(repeating: "a", count: 2048)
        #expect(check([link(0, long)]) == .badLink)
        #expect(check([FlingOfferItem(index: 0, name: "Link", size: 0, kind: .link, uti: nil, sha256: String(repeating: "0", count: 64), url: nil)]) == .badLink)
        #expect(check([FlingOfferItem(index: 0, name: "Link", size: 5, kind: .link, uti: nil, sha256: String(repeating: "0", count: 64), url: "https://a.b")]) == .malformed)
    }

    @Test func theTotalMustFitInFreeSpaceMinusOneGiB() {
        let gib: Int64 = 1024 * 1024 * 1024
        #expect(check([file(0, size: 3 * gib)], free: 4 * gib) == nil)
        #expect(check([file(0, size: 3 * gib + 1)], free: 4 * gib) == .diskFull)
        #expect(check([file(0, size: 1)], free: gib) == .diskFull)
    }

    @Test func overTwoGigabytesAsksForAWarning() {
        let gb: Int64 = 1_000_000_000
        #expect(!FlingLimits.shouldWarn(totalBytes: 2 * gb))
        #expect(FlingLimits.shouldWarn(totalBytes: 2 * gb + 1))
    }
}
