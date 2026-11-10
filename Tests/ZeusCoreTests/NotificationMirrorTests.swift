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
}
