import Foundation
import Testing

/// Notch Dynamic Type. These assertions fail until the ramp is in the notch folder.
/// NotchView.swift stays untouched; its findings remain deferred.
@Suite("UI UX notch repairs")
struct UIUXNotchRepairTests {
    /// ZB-UIUX-TYPE-002.
    private static let owned = [
        "Sources/Zeus/Notch",
        "Sources/Zeus/Notch/EdgeWave.swift",
        "Sources/Zeus/Notch/NotchDynamicType.swift",
    ]

    @Test func notchDynamicTypeStaysClosed() throws {
        let root = try #require(UIUXRepo.root())
        let actual = UIUXAudit.scan(root: root)
        let open = actual.filter { Self.owned.contains($0.file) }
        #expect(open.isEmpty)
        #expect(!actual.contains { $0.kind == "dynamic-type" && $0.surface == "Notch" })
    }
}
