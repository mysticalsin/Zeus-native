import Foundation
import Testing
@testable import Zeus

@MainActor
@Suite struct ApprovalCardSnapshotTests {
    @Test func theApprovalStatesRenderWithSyntheticData() throws {
        let root = ProcessInfo.processInfo.environment["ZEUS_QA_ARTIFACT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("approval-cards-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        SnapshotRenderer.renderApprovalCards(into: root)
        let names = [
            "approval-run-dark.png", "approval-run-light.png", "approval-edit-dark.png",
            "approval-high-hold-dark.png", "approval-queue-dark.png", "approval-allowed-dark.png",
            "approval-timeout-dark.png", "approval-high-confirm-dark.png",
        ]
        for name in names {
            let url = root.appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            #expect(data.count > 32, "\(name) was not written")
        }
    }
}
