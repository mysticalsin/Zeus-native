import Foundation
import Testing

/// Dictation surfaces from the UI/UX catalog. These assertions fail until the sites are repaired.
@Suite("UI UX dictation repairs")
struct UIUXDictationRepairTests {
    /// ZB-UIUX-A11Y-009 through ZB-UIUX-A11Y-028, ZB-UIUX-MOTION-001, and ZB-UIUX-REDUCE-001.
    private static let owned = [
        "Sources/Zeus/Dictation/DictationExtrasSettings.swift",
        "Sources/Zeus/Dictation/DictationHistoryWindow.swift",
        "Sources/Zeus/Dictation/DictationPreviewCard.swift",
        "Sources/Zeus/Dictation/SpeechEngineSettings.swift",
    ]

    @Test func dictationContractSitesStayClosed() throws {
        let root = try #require(UIUXRepo.root())
        let actual = UIUXAudit.scan(root: root)
        let open = actual.filter { Self.owned.contains($0.file) }
        #expect(open.isEmpty)
    }
}
