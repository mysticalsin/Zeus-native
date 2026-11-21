import Foundation
import Testing

/// S04-07. Check now reads the feed flag and URL, and the About page did not bind them.
@Suite("Update feed rows")
struct UpdateFeedRowTests {
    private func source(_ relative: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return try String(contentsOf: url.appendingPathComponent(relative), encoding: .utf8)
            }
            url.deleteLastPathComponent()
        }
        Issue.record("Package.swift not found")
        return ""
    }

    @Test func aboutPageBindsTheFeedSwitchAndURL() throws {
        let page = try source("Sources/Zeus/Settings/GSAboutPage.swift")
        #expect(page.contains("about.autoUpdate"))
        #expect(page.contains("about.updateFeedURL"))
    }
}
