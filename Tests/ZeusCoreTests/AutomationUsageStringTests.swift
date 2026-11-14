import Foundation
import Testing

/// The macOS Automation prompt shows this text, so it has to name everything Zeus scripts.
@Suite("Automation usage description")
struct AutomationUsageStringTests {
    private func plist() throws -> [String: Any] {
        // Tests/ZeusCoreTests/<this file> -> repository root -> Resources/Info.plist
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func theAppleEventsStringNamesTheTerminalAndITermScripting() throws {
        let text = try #require(try plist()["NSAppleEventsUsageDescription"] as? String)
        for name in ["Chrome", "Music", "Spotify", "Terminal", "iTerm"] {
            #expect(text.contains(name), "\(name) is scripted but not named")
        }
        #expect(text.contains("type"), "it should say Zeus types into a shell")
    }

    @Test func theStringKeepsToTheHouseWritingRules() throws {
        let text = try #require(try plist()["NSAppleEventsUsageDescription"] as? String)
        #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "no em or en dashes")
        #expect(text.count < 600)
    }
}
