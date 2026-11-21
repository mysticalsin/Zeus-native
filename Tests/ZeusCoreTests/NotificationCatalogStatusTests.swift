import Foundation
import Testing

/// S04-18. The catalog status said notifications were unused while the app already asks for them.
@Suite("Notification catalog status")
struct NotificationCatalogStatusTests {
    static let replacement = "Asked when you turn notifications on"

    private func source() throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return try String(contentsOf: url.appendingPathComponent("Sources/Zeus/App/SettingsStore.swift"), encoding: .utf8)
            }
            url.deleteLastPathComponent()
        }
        Issue.record("Package.swift not found")
        return ""
    }

    @Test func catalogDoesNotClaimNotificationsAreUnused() throws {
        let store = try source()
        #expect(!store.contains("Not used yet"))
        #expect(store.contains(Self.replacement))
    }
}
