import Foundation
import Testing

/// S04-03. Talk reads screen consent and the voice page did not bind it.
@Suite("Talk screen consent rows")
struct TalkScreenConsentRowTests {
    private func source() throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return try String(contentsOf: url.appendingPathComponent("Sources/Zeus/Settings/GlanceSettingsPages.swift"), encoding: .utf8)
            }
            url.deleteLastPathComponent()
        }
        Issue.record("Package.swift not found")
        return ""
    }

    @Test func voicePageBindsSeeScreenAndDrawOnScreen() throws {
        let page = try source()
        #expect(page.contains("talk.seeScreen"))
        #expect(page.contains("talk.drawOnScreen"))
    }
}
