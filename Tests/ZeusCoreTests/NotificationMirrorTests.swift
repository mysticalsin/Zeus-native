import Foundation
import Testing
@testable import ZeusCore

@Suite struct NotificationMirrorTests {
    @Test func parsesRecordPlist() throws {
        let plist: [String: Any] = ["app": "com.apple.MobileSMS", "req": ["titl": "Ana", "body": "On my way", "subt": "iMessage"]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let note = NotificationMirror.parse(data, app: "x")
        #expect(note?.title == "Ana")
        #expect(note?.body == "On my way")
        #expect(note?.app == "com.apple.MobileSMS")
        #expect(NotificationMirror.shortName("com.apple.MobileSMS") == "MobileSMS")
    }

    @Test func missingDatabaseIsNoAccess() {
        let result = NotificationMirror.recent(url: URL(fileURLWithPath: "/nonexistent/db"))
        #expect(result == .failure(.noAccess))
    }

    @Test func oversizedRecordIsSkipped() throws {
        let plist: [String: Any] = ["app": "com.example.sender", "req": ["titl": "Hi", "body": String(repeating: "A", count: 1_000_000)]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        #expect(data.count > 64 * 1024)
        #expect(NotificationMirror.parse(data, app: "com.example.sender") == nil)
    }
}
