import Foundation
import Testing
@testable import ZeusCore

@Suite struct AtticusCleanRoomTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func forbiddenTokensAreAbsentFromSampleAtticusStrings() {
        for sample in AtticusCleanRoom.sampleAtticusParityStrings {
            #expect(AtticusCleanRoom.forbiddenHits(in: sample).isEmpty, "sample: \(sample)")
        }
        #expect(AtticusCleanRoom.forbiddenHits(in: "public CGEvent.postToPid only").isEmpty)
    }

    @Test func forbiddenDetectorFindsBannedTokens() {
        let skyLightPrivate = ["SL", "EventPostToPid"].joined()
        let probe = "\(skyLightPrivate) vendor analytics checkout"
        let hits = AtticusCleanRoom.forbiddenHits(in: probe)
        #expect(hits.contains(skyLightPrivate))
    }

    @Test func noticesMustNotClaimAtticusCode() throws {
        let noticesURL = Self.repoRoot.appendingPathComponent("Resources/NOTICES.txt")
        let notices = try String(contentsOf: noticesURL, encoding: .utf8)
        #expect(AtticusCleanRoom.noticesViolations(notices).isEmpty)
        let sources = Self.repoRoot.appendingPathComponent("Sources")
        let report = AtticusCleanRoom.report(notices: notices, sourceRoot: sources)
        #expect(report.passed)
        #expect(report.text.hasPrefix("PASS"))
    }

    @Test func acceptanceReportPassesOnThisTree() throws {
        let notices = try String(contentsOf: Self.repoRoot.appendingPathComponent("Resources/NOTICES.txt"), encoding: .utf8)
        let report = AtticusCleanRoom.report(
            notices: notices,
            sourceRoot: Self.repoRoot.appendingPathComponent("Sources")
        )
        #expect(report.passed)
        #expect(report.text.hasPrefix("PASS"))
    }
}
