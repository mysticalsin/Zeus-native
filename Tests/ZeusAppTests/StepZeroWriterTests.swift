import Foundation
import Testing
@testable import Zeus

@Suite("Step zero report writer")
struct StepZeroWriterTests {
    @Test func aMissingFolderIsMadeAndAnyOtherFolderIsRefused() {
        let writer = StepZeroReportWriter.self
        #expect(writer.rule(facts(exists: false)) == .make)
        #expect(writer.rule(facts(exists: true, directory: true, owner: true, mode: 0o700)) == .open)
        let refused = [
            facts(exists: true, directory: true, owner: true, mode: 0o755),
            facts(exists: true, directory: true, owner: true, mode: 0o770),
            facts(exists: true, directory: true, owner: true, mode: 0o600),
            facts(exists: true, directory: true, owner: true, mode: 0o701),
            facts(exists: true, directory: true, owner: true, mode: 0),
            facts(exists: true, directory: true, owner: false, mode: 0o700),
            facts(exists: true, link: true, directory: true, owner: true, mode: 0o700),
            facts(exists: true, directory: false, owner: true, mode: 0o700),
        ]
        for look in refused {
            #expect(writer.rule(look) == .refuse)
        }
    }

    @Test func theScreenKeepsSixteenDigitsOfAFullDigest() {
        let digest = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        #expect(StepZeroReportWriter.screenDigest(digest) == "e3b0c44298fc1c14")
        #expect(StepZeroReportWriter.screenDigest(String(digest.prefix(16))) == nil)
        #expect(StepZeroReportWriter.screenDigest(digest.uppercased()) == nil)
        #expect(StepZeroReportWriter.screenDigest(digest + "a") == nil)
        #expect(StepZeroReportWriter.screenDigest("") == nil)
    }

    @Test func aNewFileIsPrivateAndItsDigestIsTheBytes() throws {
        let box = try Scratch()
        defer { box.remove() }
        let samples: [(Data, String)] = [
            (Data(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            (Data("abc".utf8), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            (Data("message digest".utf8), "f7846f55cf23e14eebeab5b4e1550cad5b509e3348fbc4efa3a1413d393cb650"),
            (
                Data("The quick brown fox jumps over the lazy dog".utf8),
                "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
            ),
        ]
        for (index, sample) in samples.enumerated() {
            let folder = box.root.appendingPathComponent("run-\(index)", isDirectory: true)
            let result = StepZeroReportWriter.write(sample.0, into: folder, named: "step-zero.json")
            #expect(result == .wrote(digest: sample.1))
            #expect(StepZeroReportWriter.screenDigest(sample.1) == String(sample.1.prefix(16)))
            let file = folder.appendingPathComponent("step-zero.json")
            #expect(try Data(contentsOf: file) == sample.0)
            let folderFacts = StepZeroReportWriter.facts(at: folder)
            let fileFacts = StepZeroReportWriter.facts(at: file)
            #expect(folderFacts.isDirectory)
            #expect(!folderFacts.isSymbolicLink)
            #expect(folderFacts.ownerIsCaller)
            #expect(folderFacts.permissions == 0o700)
            #expect(fileFacts.isRegularFile)
            #expect(!fileFacts.isSymbolicLink)
            #expect(fileFacts.ownerIsCaller)
            #expect(fileFacts.permissions == 0o600)
        }
    }

    @Test func theByteLimitIsWrittenAndOnePastItIsNot() throws {
        let box = try Scratch()
        defer { box.remove() }
        let full = Data(repeating: 0x61, count: StepZeroReportWriter.byteLimit)
        let folder = box.root.appendingPathComponent("full", isDirectory: true)
        let wrote = StepZeroReportWriter.write(full, into: folder, named: "step-zero.json")
        #expect(wrote == .wrote(digest: "dd3dde87623d9a6b354c68c943d189c89c63652d945e7bbdf0986cae91a49521"))
        #expect(try Data(contentsOf: folder.appendingPathComponent("step-zero.json")) == full)

        let over = box.root.appendingPathComponent("over", isDirectory: true)
        let refused = StepZeroReportWriter.write(
            Data(repeating: 0x61, count: StepZeroReportWriter.byteLimit + 1),
            into: over,
            named: "step-zero.json"
        )
        #expect(refused == .refused(.tooLarge))
        #expect(StepZeroReportWriter.facts(at: over).exists == false)
    }

    @Test func aLinkAtTheNameIsLeftAlone() throws {
        let box = try Scratch()
        defer { box.remove() }
        let folder = try box.folder(named: "owned", mode: 0o700)
        let target = box.root.appendingPathComponent("kept.txt")
        try Data("keep".utf8).write(to: target)
        let link = folder.appendingPathComponent("step-zero.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let result = StepZeroReportWriter.write(Data("replace".utf8), into: folder, named: "step-zero.json")
        #expect(result == .refused(.link))
        #expect(try Data(contentsOf: target) == Data("keep".utf8))
        #expect(StepZeroReportWriter.facts(at: link).isSymbolicLink)
    }

    @Test func anExistingFileIsLeftAlone() throws {
        let box = try Scratch()
        defer { box.remove() }
        let folder = try box.folder(named: "owned", mode: 0o700)
        let file = folder.appendingPathComponent("step-zero.json")
        try Data("keep".utf8).write(to: file)
        let result = StepZeroReportWriter.write(Data("replace".utf8), into: folder, named: "step-zero.json")
        #expect(result == .refused(.existing))
        #expect(try Data(contentsOf: file) == Data("keep".utf8))
    }

    @Test func aFolderAtTheWrongModeIsLeftAlone() throws {
        let box = try Scratch()
        defer { box.remove() }
        let folder = try box.folder(named: "open", mode: 0o755)
        let result = StepZeroReportWriter.write(Data("abc".utf8), into: folder, named: "step-zero.json")
        #expect(result == .refused(.folder))
        #expect(StepZeroReportWriter.facts(at: folder).permissions == 0o755)
        #expect(StepZeroReportWriter.facts(at: folder.appendingPathComponent("step-zero.json")).exists == false)
    }

    @Test func aLinkToAFolderIsNotTheFolder() throws {
        let box = try Scratch()
        defer { box.remove() }
        let real = try box.folder(named: "real", mode: 0o700)
        let link = box.root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let result = StepZeroReportWriter.write(Data("abc".utf8), into: link, named: "step-zero.json")
        #expect(result == .refused(.folder))
        #expect(StepZeroReportWriter.facts(at: real.appendingPathComponent("step-zero.json")).exists == false)
        #expect(StepZeroReportWriter.facts(at: link).isSymbolicLink)
    }

    @Test func aBadNameCreatesNothing() throws {
        let box = try Scratch()
        defer { box.remove() }
        let names = ["", ".", "..", "a/b", "a\u{0}b", String(repeating: "n", count: 256)]
        for name in names {
            let folder = box.root.appendingPathComponent("for-\(names.firstIndex(of: name)!)", isDirectory: true)
            let result = StepZeroReportWriter.write(Data("abc".utf8), into: folder, named: name)
            #expect(result == .refused(.name))
            #expect(StepZeroReportWriter.facts(at: folder).exists == false)
        }
    }

    @Test func aMissingParentIsNotCreated() throws {
        let box = try Scratch()
        defer { box.remove() }
        let folder = box.root.appendingPathComponent("missing").appendingPathComponent("StepZero")
        let result = StepZeroReportWriter.write(Data("abc".utf8), into: folder, named: "step-zero.json")
        #expect(result == .refused(.folder))
        #expect(StepZeroReportWriter.facts(at: box.root.appendingPathComponent("missing")).exists == false)
    }

    @Test func aFailedWriteRemovesTheFile() throws {
        let box = try Scratch()
        defer { box.remove() }
        let folder = box.root.appendingPathComponent("owned", isDirectory: true)
        let name = "step-zero.json"
        let result = StepZeroReportWriter.write(Data("partial-secret".utf8), into: folder, named: name, transfer: { fd, bytes in
            _ = StepZeroReportWriter.writeAll(fd, Data(bytes.prefix(7)))
            return false
        })
        #expect(result == .refused(.write))
        #expect(StepZeroReportWriter.facts(at: folder.appendingPathComponent(name)).exists == false)
        let listing = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        #expect(listing.isEmpty)
    }

    @Test func aSecondNameLeavesTheFirstFile() throws {
        let box = try Scratch()
        defer { box.remove() }
        let folder = box.root.appendingPathComponent("owned", isDirectory: true)
        let first = StepZeroReportWriter.write(Data("abc".utf8), into: folder, named: "one.json")
        let second = StepZeroReportWriter.write(Data("message digest".utf8), into: folder, named: "two.json")
        #expect(first == .wrote(digest: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        #expect(second == .wrote(digest: "f7846f55cf23e14eebeab5b4e1550cad5b509e3348fbc4efa3a1413d393cb650"))
        #expect(try Data(contentsOf: folder.appendingPathComponent("one.json")) == Data("abc".utf8))
        #expect(try Data(contentsOf: folder.appendingPathComponent("two.json")) == Data("message digest".utf8))
    }

    private func facts(
        exists: Bool,
        link: Bool = false,
        directory: Bool = false,
        owner: Bool = false,
        mode: Int = 0
    ) -> StepZeroReportWriter.PathFacts {
        StepZeroReportWriter.PathFacts(
            exists: exists,
            isSymbolicLink: link,
            isDirectory: directory,
            isRegularFile: false,
            ownerIsCaller: owner,
            permissions: mode
        )
    }
}

private struct Scratch {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("step-zero-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func folder(named name: String, mode: Int) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
