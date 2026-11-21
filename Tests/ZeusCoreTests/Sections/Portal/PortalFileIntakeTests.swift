import Foundation
import Testing
@testable import ZeusCore

@Suite("Portal file intake")
struct PortalFileIntakeTests {
    @Test func aTextFileIsConvertedIntoTheInbox() throws {
        let sandbox = try PortalFixtures.directory()
        let inbox = sandbox.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: inbox.path)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let source = try PortalFixtures.write("note.txt", bytes: Data("A\r\nB".utf8), in: sandbox)
        let flow = PortalLocalConversion.importDrop(path: source, declaredType: .plainText, inbox: inbox.path)
        let converted = try #require(doneOutput(flow))
        #expect(String(decoding: converted.bytes, as: UTF8.self) == "A\nB")
        let written = inbox.appendingPathComponent(converted.fileName)
        #expect(try Data(contentsOf: written) == converted.bytes)
        let mode = try FileManager.default.attributesOfItem(atPath: written.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        #expect(try String(contentsOf: URL(fileURLWithPath: source), encoding: .utf8) == "A\r\nB")
    }

    @Test func symlinksTraversalAndHardLinksAreRefused() throws {
        let sandbox = try PortalFixtures.directory()
        let outside = try PortalFixtures.directory()
        defer {
            try? FileManager.default.removeItem(at: sandbox)
            try? FileManager.default.removeItem(at: outside)
        }
        let secret = try PortalFixtures.write("secret.txt", bytes: Data("SECRET".utf8), in: outside)
        let link = sandbox.appendingPathComponent("note.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: secret))
        let linked = PortalLocalConversion.importDrop(path: link.path, declaredType: .plainText, inbox: sandbox.path)
        #expect(linked.phase == .failed(.symlink))
        #expect(try folderFiles(sandbox).filter { $0 != "note.txt" }.isEmpty)

        let escape = sandbox.path + "/../" + outside.lastPathComponent + "/secret.txt"
        #expect(PortalLocalConversion.importDrop(path: escape, declaredType: .plainText, inbox: sandbox.path).phase == .failed(.escapesSandbox))

        let nested = sandbox.appendingPathComponent("door")
        try FileManager.default.createSymbolicLink(at: nested, withDestinationURL: outside)
        let through = nested.appendingPathComponent("secret.txt").path
        #expect(PortalLocalConversion.importDrop(path: through, declaredType: .plainText, inbox: sandbox.path).phase == .failed(.symlink))

        let real = try PortalFixtures.write("once.txt", bytes: Data("once".utf8), in: sandbox)
        let alias = sandbox.appendingPathComponent("twice.txt").path
        #expect(PortalFixtures.hardLink(from: real, to: alias))
        #expect(PortalLocalConversion.importDrop(path: real, declaredType: .plainText, inbox: sandbox.path).phase == .failed(.hardLink))
    }

    @Test func oversizeAndALooseInboxFailClosed() throws {
        let sandbox = try PortalFixtures.directory()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let tooBig = Data(count: PortalLimits.maxConversionBytes + 1)
        let path = try PortalFixtures.write("big.txt", bytes: tooBig, in: sandbox)
        #expect(PortalLocalConversion.importDrop(path: path, declaredType: .plainText, inbox: sandbox.path).phase == .failed(.tooLarge))
        #expect(try folderFiles(sandbox) == ["big.txt"])

        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: sandbox.path)
        let small = try PortalFixtures.write("note.txt", bytes: Data("ok".utf8), in: sandbox)
        #expect(PortalLocalConversion.importDrop(path: small, declaredType: .plainText, inbox: sandbox.path).phase == .failed(.insecureSandbox))
    }

    @Test func aSiblingOfTheInboxIsNotAPlaceToWrite() throws {
        let parent = try PortalFixtures.directory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let inbox = parent.appendingPathComponent("inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: inbox.path)
        #expect(PortalInbox.write(bytes: Data("x".utf8), fileName: "../escape.txt", root: inbox.path) == .failure(.unsafeName))
        #expect(PortalInbox.write(bytes: Data("x".utf8), fileName: "a/b.txt", root: inbox.path) == .failure(.unsafeName))
        #expect(try folderFiles(parent) == ["inbox"])
    }

    private func doneOutput(_ flow: PortalDropFlow) -> PortalConversionOutput? {
        if case .done(let output) = flow.phase { return output }
        return nil
    }

    private func folderFiles(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }
}
