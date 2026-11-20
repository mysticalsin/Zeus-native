import Foundation
import Testing

/// The macOS Local Network prompt shows this text, and Bonjour browsing is refused unless the service type is declared.
@Suite("Fling Info.plist")
struct FlingPlistTests {
    private func plist() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// REG-683: no Local Network prompt without its reason, and no browsing without the declared type.
    @Test func theLocalNetworkPromptSaysWhyAndTheBonjourTypeIsDeclared() throws {
        let plist = try plist()
        #expect(plist["NSLocalNetworkUsageDescription"] as? String == "Zeus looks for nearby Macs running Zeus so you can send files to them with Fling. When you turn on nearby speaker names, Zeus also looks for speakers on your local network.")
        #expect(plist["NSBonjourServices"] as? [String] == ["_zeus-fling._tcp", "_airplay._tcp", "_raop._tcp"])
    }
}
