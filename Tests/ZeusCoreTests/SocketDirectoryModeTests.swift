import Foundation
import Testing
@testable import ZeusCore

@Suite("Socket directory mode")
struct SocketDirectoryModeTests {
    @Test func aNewSocketDirectoryIsPrivate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-sock-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("private", isDirectory: true)
        let path = directory.appendingPathComponent("zeus.sock").path
        let server = UnixSocketServer(path: path) { _, _ in }
        try server.start()
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let value = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect((value?.intValue ?? -1) & 0o777 == 0o700)
    }
}
