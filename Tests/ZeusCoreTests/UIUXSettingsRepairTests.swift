import Foundation
import Testing

/// Settings surfaces from the UI/UX catalog. These assertions fail until the sites are repaired.
@Suite("UI UX settings repairs")
struct UIUXSettingsRepairTests {
    /// ZB-UIUX-A11Y-100 to ZB-UIUX-A11Y-202 and ZB-UIUX-A11Y-213 to ZB-UIUX-A11Y-288,
    /// ZB-UIUX-TYPE-004, ZB-UIUX-MOTION-011 to ZB-UIUX-MOTION-013, and ZB-UIUX-REDUCE-003.
    /// Speaker recognition stays deferred.
    private static let owned = [
        "Sources/Zeus/Settings/GSAIConnectionsPage.swift",
        "Sources/Zeus/Settings/GSAboutPage.swift",
        "Sources/Zeus/Settings/GSAgentHubCards.swift",
        "Sources/Zeus/Settings/GSBeamerPage.swift",
        "Sources/Zeus/Settings/GSBrowserUseRows.swift",
        "Sources/Zeus/Settings/GSDiagnosticsLogs.swift",
        "Sources/Zeus/Settings/GSDictationPage.swift",
        "Sources/Zeus/Settings/GSDrawnNotchCard.swift",
        "Sources/Zeus/Settings/GSEnginePage.swift",
        "Sources/Zeus/Settings/GSEqualiserCard.swift",
        "Sources/Zeus/Settings/GSFacePresenceCard.swift",
        "Sources/Zeus/Settings/GSFeaturesPage.swift",
        "Sources/Zeus/Settings/GSInsomniaPage.swift",
        "Sources/Zeus/Settings/GSLanguagePacksCard.swift",
        "Sources/Zeus/Settings/GSLiveDiagnosticsCard.swift",
        "Sources/Zeus/Settings/GSPolyglotPage.swift",
        "Sources/Zeus/Settings/GSShelfPage.swift",
        "Sources/Zeus/Settings/GSShortcutRecorder.swift",
        "Sources/Zeus/Settings/GSSpeechEngineCard.swift",
        "Sources/Zeus/Settings/GSTilingPage.swift",
        "Sources/Zeus/Settings/GSVoiceCards.swift",
        "Sources/Zeus/Settings/GlanceSettingsPages.swift",
        "Sources/Zeus/Settings/GlanceSettingsStyle.swift",
        "Sources/Zeus/Settings",
        "Sources/Zeus/Settings/SettingsDynamicType.swift",
        "Sources/Zeus/Settings/SettingsMotionTokens.swift",
        "Sources/Zeus/Settings/GlanceSettingsWindow.swift",
    ]

    @Test func settingsContractSitesStayClosed() throws {
        let root = try #require(UIUXRepo.root())
        let actual = UIUXAudit.scan(root: root)
        let open = actual.filter { Self.owned.contains($0.file) }
        #expect(open.isEmpty)
        #expect(!actual.contains { $0.kind == "dynamic-type" && $0.surface == "Settings" })
    }
}
