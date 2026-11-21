import Foundation
import Testing
@testable import ZeusCore

@Suite("Hands command log privacy")
struct HandsLogPrivacyTests {
    private func mode(_ url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        return (value?.intValue ?? -1) & 0o777
    }

    @Test func aNewLogIsPrivateToTheOwner() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-hands-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("hands-commands.log")
        var log = HandsCommandLog()
        log.record(command: "ls", verdict: "allow", outcome: "ran", at: Date(timeIntervalSince1970: 0))
        try log.write(to: url)
        #expect(try mode(url) == 0o600)
        #expect(try mode(url.deletingLastPathComponent()) == 0o700)
    }
}
