import Foundation
import Testing

/// S04-06. Location and calendar calls are already in the app. The hardened-runtime file did not allow them.
enum ResourceEntitlementRule {
    /// The whole key set. Equality rejects an extra key such as network.server.
    static let keys: Set<String> = [
        "com.apple.security.app-sandbox",
        "com.apple.security.automation.apple-events",
        "com.apple.security.device.audio-input",
        "com.apple.security.device.camera",
        "com.apple.security.network.client",
        "com.apple.security.personal-information.calendars",
        "com.apple.security.personal-information.location",
    ]

    static func allows(_ file: [String: Any]) -> Bool {
        guard Set(file.keys) == keys else { return false }
        guard file["com.apple.security.app-sandbox"] as? Bool == false else { return false }
        return keys.filter { $0 != "com.apple.security.app-sandbox" }.allSatisfy { file[$0] as? Bool == true }
    }
}

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
        #expect(Set(file.keys) == ResourceEntitlementRule.keys)
        #expect(file["com.apple.security.app-sandbox"] as? Bool == false)
        #expect(file["com.apple.security.personal-information.location"] as? Bool == true)
        #expect(file["com.apple.security.personal-information.calendars"] as? Bool == true)
        #expect(ResourceEntitlementRule.allows(file))
    }

    @Test func addingNetworkServerIsNotTheSameKeySet() throws {
        var file = try entitlements()
        file["com.apple.security.network.server"] = true
        #expect(Set(file.keys) != ResourceEntitlementRule.keys)
        #expect(!ResourceEntitlementRule.allows(file))
    }
}
