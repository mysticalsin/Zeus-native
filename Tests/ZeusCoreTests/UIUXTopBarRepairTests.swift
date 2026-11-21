import Foundation
import Testing

/// Top bar surfaces from the UI/UX catalog. These assertions fail until the sites are repaired.
@Suite("UI UX top bar repairs")
struct UIUXTopBarRepairTests {
    /// ZB-UIUX-A11Y-294 to ZB-UIUX-A11Y-357, ZB-UIUX-TYPE-005,
    /// ZB-UIUX-MOTION-014 to ZB-UIUX-MOTION-025, and ZB-UIUX-REDUCE-004.
    /// Chat stays deferred.
    private static let owned = [
        "Sources/Zeus/TopBar/GlanceEmptyStates.swift",
        "Sources/Zeus/TopBar/GlanceHomeCards.swift",
        "Sources/Zeus/TopBar/HomeStripView.swift",
        "Sources/Zeus/TopBar/HomeWidgetViews.swift",
        "Sources/Zeus/TopBar/RecordingActivityWings.swift",
        "Sources/Zeus/TopBar/TeleprompterPage.swift",
        "Sources/Zeus/TopBar/TilingPage.swift",
        "Sources/Zeus/TopBar/TodayPages.swift",
        "Sources/Zeus/TopBar/TodoPage.swift",
        "Sources/Zeus/TopBar/TopBarViews.swift",
        "Sources/Zeus/TopBar/WavesPage.swift",
        "Sources/Zeus/TopBar",
        "Sources/Zeus/TopBar/LyricsViews.swift",
        "Sources/Zeus/TopBar/TopBarDynamicType.swift",
        "Sources/Zeus/TopBar/TopBarMotionTokens.swift",
    ]

    @Test func topBarContractSitesStayClosed() throws {
        let root = try #require(UIUXRepo.root())
        let actual = UIUXAudit.scan(root: root)
        let open = actual.filter { Self.owned.contains($0.file) }
        #expect(open.isEmpty)
        #expect(!actual.contains { $0.kind == "dynamic-type" && $0.surface == "TopBar" })
    }
}
