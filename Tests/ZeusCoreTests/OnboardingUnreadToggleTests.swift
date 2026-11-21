import Foundation
import Testing

/// S04-08. The welcome step offered two switches that no cue reads. Errors stay, because that switch is read.
@Suite("Onboarding unread toggles")
struct OnboardingUnreadToggleTests {
    private func source() throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return try String(contentsOf: url.appendingPathComponent("Sources/Zeus/Onboarding/OnboardingSteps.swift"), encoding: .utf8)
            }
            url.deleteLastPathComponent()
        }
        Issue.record("Package.swift not found")
        return ""
    }

    @Test func stayInControlDoesNotOfferUnreadSwitches() throws {
        let step = try source()
        #expect(!step.contains("notify.approvals"))
        #expect(!step.contains("notify.agentDone"))
        #expect(step.contains("notify.errors"))
    }
}
