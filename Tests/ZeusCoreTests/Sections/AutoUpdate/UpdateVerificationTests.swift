import Foundation
import Testing
@testable import ZeusCore

/// ZB-005, ZB-006, and ZB-013. Item status and delivery order are fakes. No updater runs.
@Suite("Update verification")
struct UpdateVerificationTests {
    private static let now = Date(timeIntervalSince1970: 1_763_683_200)

    @Test func zb005AnUncheckedItemDoesNotPass() {
        #expect(UpdateVerification.allows(status: .unchecked, signatureString: "ed25519-signature") == false)
        #expect(UpdateVerification.allows(status: .failed, signatureString: "ed25519-signature") == false)
        #expect(UpdateVerification.allows(status: .valid, signatureString: "ed25519-signature"))
        #expect(UpdateVerification.allows(status: .valid, signatureString: ""))
        #expect(UpdateVerification.verdict(status: .unchecked) == .invalid)
        #expect(UpdateVerification.verdict(status: .failed) == .invalid)
        #expect(UpdateVerification.verdict(status: .valid) == .valid)
    }

    @Test func zb006ThePostedVerdictIsTheItemStatus() {
        let context = Self.context()
        let candidate = Self.candidate()
        let unchecked = UpdateSession.reduce(.downloading(candidate), .downloaded(UpdateVerification.verdict(status: .unchecked)), context)
        #expect(unchecked.state == .failed(.signature))
        #expect(!unchecked.effects.contains(.install))
        let failed = UpdateSession.reduce(.downloading(candidate), .downloaded(UpdateVerification.verdict(status: .failed)), context)
        #expect(failed.state == .failed(.signature))
        let valid = UpdateSession.reduce(.downloading(candidate), .downloaded(UpdateVerification.verdict(status: .valid)), context)
        #expect(valid.state == .readyToInstall(candidate))
        #expect(!valid.effects.contains(.install))
    }

    @Test func zb013OneEventStillVerifiesWhenASchedulerReversesTheBatch() {
        let context = Self.context()
        let candidate = Self.candidate()
        let valid = UpdateVerification.events(for: .valid)
        #expect(valid.count == 1)
        let ready = Self.apply(valid, reversed: true, from: .downloading(candidate), context: context)
        #expect(ready == .readyToInstall(candidate))
        let refused = Self.apply(UpdateVerification.events(for: .unchecked), reversed: true, from: .downloading(candidate), context: context)
        #expect(refused == .failed(.signature))
        let split = Self.apply([.downloadFinished, .verifyFinished(.valid)], reversed: true, from: .downloading(candidate), context: context)
        #expect(split == .verifying(candidate))
    }

    @Test func theBridgePostsTheRealStatusInOneEvent() throws {
        var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        while url.path != "/" && !FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
            url.deleteLastPathComponent()
        }
        let source = try String(contentsOf: url.appendingPathComponent("Sources/Zeus/Settings/GlassShell/Sections/AutoUpdate/SignedUpdateBridge.swift"), encoding: .utf8)
        #expect(!source.contains("signingValidationStatus != .failed"))
        #expect(!source.contains("verifyFinished(.valid)"))
        #expect(!source.contains("finish(.downloadFinished)"))
        #expect(source.contains("UpdateVerification.allows"))
        #expect(source.contains(".downloaded("))
    }

    private static func apply(_ events: [UpdateEvent], reversed: Bool, from state: UpdateSessionState, context: UpdateContext) -> UpdateSessionState {
        var state = state
        for event in reversed ? events.reversed() : events {
            state = UpdateSession.reduce(state, event, context).state
        }
        return state
    }

    private static func context() -> UpdateContext {
        UpdateContext(
            configuration: UpdateConfiguration(
                automaticChecks: false,
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
