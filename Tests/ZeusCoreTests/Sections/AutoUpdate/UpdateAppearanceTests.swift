import Foundation
import Testing
@testable import ZeusCore

/// ZB-020. Reopening the card must not abort a download, a verify, or an install.
@Suite("Update appearance")
struct UpdateAppearanceTests {
    private static let now = Date(timeIntervalSince1970: 1_763_683_200)

    @Test func zb020ReopeningDuringWorkDoesNotStartACheck() {
        let candidate = Self.candidate()
        let busy: [UpdateSessionState] = [
            .downloading(candidate),
            .verifying(candidate),
            .installing(candidate),
        ]
        for state in busy {
            #expect(UpdateAppearance.startsCheckOnAppear(state, automaticChecks: true, configured: true) == false)
        }
        #expect(UpdateAppearance.startsCheckOnAppear(.idle, automaticChecks: true, configured: true))
        #expect(UpdateAppearance.startsCheckOnAppear(.upToDate, automaticChecks: true, configured: true))
        #expect(UpdateAppearance.startsCheckOnAppear(.idle, automaticChecks: false, configured: true) == false)
        #expect(UpdateAppearance.startsCheckOnAppear(.downloading(candidate), automaticChecks: true, configured: false) == false)
        let wouldCancel = UpdateSession.reduce(.downloading(candidate), .checkRequested, Self.context())
        #expect(wouldCancel.effects.contains(.cancelNetwork))
    }

    @Test func theCardUsesTheAppearGate() throws {
        var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        while url.path != "/" && !FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
            url.deleteLastPathComponent()
        }
        let source = try String(contentsOf: url.appendingPathComponent("Sources/Zeus/Settings/GlassShell/Sections/AutoUpdate/UpdatesSessionModel.swift"), encoding: .utf8)
        guard let gate = source.range(of: "func appear()"),
              let check = source.range(of: "checkNow()", range: gate.upperBound..<source.endIndex),
              let decision = source.range(of: "startsCheckOnAppear", range: gate.upperBound..<check.lowerBound) else {
            Issue.record("appear does not consult the gate before checking")
            return
        }
        #expect(decision.lowerBound < check.lowerBound)
    }

    private static func context() -> UpdateContext {
        UpdateContext(
            configuration: UpdateConfiguration(
                automaticChecks: true,
                feedURL: "https://updates.example.com/appcast.xml",
                publicKey: Data(repeating: 4, count: 32).base64EncodedString()
            ),
            currentVersion: ZeusVersion(major: 1, minor: 0, patch: 0),
            duringTests: true,
            disposableCopy: false,
            now: now,
            reduceMotion: false,
            acceptsUpdates: true
        )
    }

    private static func candidate() -> UpdateCandidate {
        UpdateCandidate(
            version: ZeusVersion(major: 2, minor: 0, patch: 0),
            downloadURL: URL(string: "https://updates.example.com/Zeus.zip")!,
            edSignature: "ed25519-signature",
            notes: []
        )
    }
}
