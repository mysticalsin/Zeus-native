import Foundation
import Testing

/// S04-06. Location and calendar calls are already in the app. The hardened-runtime file did not allow them.
@Suite("Location and calendar entitlements")
struct ResourceEntitlementTests {
    private func entitlements() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                let data = try Data(contentsOf: url.appendingPathComponent("Resources/Zeus.entitlements"))
                return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            }
            url.deleteLastPathComponent()
        }
        Issue.record("Package.swift not found")
        return [:]
    }

    @Test func locationAndCalendarsAreAllowedForTheCallsAlreadyMade() throws {
        let file = try entitlements()
        #expect(file["com.apple.security.app-sandbox"] as? Bool == false)
        #expect(file["com.apple.security.personal-information.location"] as? Bool == true)
        #expect(file["com.apple.security.personal-information.calendars"] as? Bool == true)
    }
}
