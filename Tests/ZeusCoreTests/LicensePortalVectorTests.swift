import CryptoKit
import Foundation
import Testing
@testable import ZeusCore

/// Keys, activation proofs and revocation lists made by the license portal (portal/, Node WebCrypto)
/// must verify here byte for byte. Vector from a throwaway key, generated once.
@Suite struct LicensePortalVectorTests {
    static let publicKey = "l0Q1ZJD8qQDM+TCnDbx4q/f0+bKCaeQE/4sJ9sCNpBw="
    static let device = "2f0c9a7d1e3b5a61"
    static let key = "ZEUS1.eyJlbWFpbCI6InZlY3RvckBleGFtcGxlLmNvbSIsImV4cGlyZXMiOjE4MzE1MzYwMDAsImlkIjoiTC1WRUNUT1IwMDAxIiwiaXNzdWVkIjoxODAwMDAwMDAwLCJuYW1lIjoiVmVjdG9yIFRlc3RlciIsInBsYW4iOiJhbm51YWwiLCJzZWF0cyI6Mn0.53-tjLDTeYPc0VXJz771CZ6nwdpxl_xIeVva6bvnzOEPWQ9Dqc9pOLKtjyQZGu1IacIWY1N79a5WiHJ2M8bSAw"
    static let activation = "ZEUSA1.eyJkZXZpY2UiOiIyZjBjOWE3ZDFlM2I1YTYxIiwiaXNzdWVkIjoxODAwMDAwMTAwLCJsaWNlbnNlIjoiTC1WRUNUT1IwMDAxIiwic2VhdCI6MSwic2VhdHMiOjJ9.HruscR-IbBugHnMboU0lIxA9JLvmiKn5RmZg7mDgoE0-5BfNiSC7_Zbfo_MJ-b3k9j8Qer9lX4jfXBxxl5RjDg"
    static let revoked = "ZEUSR1.eyJpZHMiOlsiTC1WRUNUT1IwMDAxIl0sImlzc3VlZCI6MTgwMDAwMDIwMH0.birOnjyPKyMVo4C1ihuuPCqiZX3b195s9RBgsN3rGL_kzhjE3bwyNgEaSXxnj1yj-0J6zEQywz4uRgFS6ps1DA"
    static let emptyList = "ZEUSR1.eyJpZHMiOltdLCJpc3N1ZWQiOjE4MDAwMDAyMDB9.pXj5nc2ybZry6TTgZENdueVm35UUCYGnq2N939zU-kmSVhOCaNB6iEHJ4XT-x5x1VocPpF3vJmlm_MfSwJluBA"

    let keys = [License.publicKey(base64: Self.publicKey)!]
    var evaluator: LicenseEvaluator { LicenseEvaluator(publicKeys: keys, deviceID: Self.device) }
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func portalKeyVerifiesInSwift() throws {
        let payload = try License.verify(Self.key, publicKeys: keys, deviceID: Self.device, now: start).get()
        #expect(payload.id == "L-VECTOR0001")
        #expect(payload.kind == .annual)
        #expect(payload.seatCount == 2)
        #expect(payload.name == "Vector Tester")
    }

    @Test func annualKeyCountsDownAndExpires() {
        let day30 = start.addingTimeInterval(30 * 86_400)
        #expect(evaluator.evaluate(.init(key: Self.key, trialStart: start, now: day30)).isLicensed)
        if case .licensed(_, let left) = evaluator.evaluate(.init(key: Self.key, trialStart: start, now: day30)) { #expect(left == 335) }
        let late = start.addingTimeInterval(400 * 86_400)
        guard case .expired(let payload) = evaluator.evaluate(.init(key: Self.key, trialStart: start, now: late)) else {
            Issue.record("expected expired"); return
        }
        #expect(payload.id == "L-VECTOR0001")
    }

    @Test func rejectedActivationCannotBeRestoredByAKeyRetainedAfterFailedDeletion() {
        let day30 = start.addingTimeInterval(30 * 86_400)
        #expect(evaluator.evaluate(.init(key: Self.key, activation: Self.activation,
                                        trialStart: start, now: day30)).isLicensed)
        let rejected = evaluator.evaluate(.init(key: Self.key, activation: Self.activation,
                                                trialStart: start, now: day30, activationRejected: true))
        #expect(rejected == .trialEnded)
        #expect(!rejected.isLicensed)
        #expect(!LicenseGate.allows(.pro, status: rejected, gatingEnabled: true))
        // Existing commercial configuration remains separate from credential cleanup.
        #expect(LicenseGate.allows(.pro, status: rejected, gatingEnabled: false))
    }

    @Test func activationProofIsForThisKeyAndMac() throws {
        let proof = try evaluator.checkActivation(Self.activation, licenseID: "L-VECTOR0001").get()
        #expect(proof.seat == 1 && proof.seats == 2)
        #expect(evaluator.checkActivation(Self.activation, licenseID: "L-OTHER") == .failure(.unknownLicense))
        let otherMac = LicenseEvaluator(publicKeys: keys, deviceID: "ffffffffffffffff")
        #expect(otherMac.checkActivation(Self.activation, licenseID: "L-VECTOR0001") == .failure(.wrongDevice))
    }

    @Test func signedRevocationListTurnsKeyOff() {
        #expect(evaluator.evaluate(.init(key: Self.key, revocations: Self.revoked, trialStart: start, now: start)) != .trialEnded)
        guard case .revoked = evaluator.evaluate(.init(key: Self.key, revocations: Self.revoked, trialStart: start, now: start)) else {
            Issue.record("expected revoked"); return
        }
        #expect(evaluator.evaluate(.init(key: Self.key, revocations: Self.emptyList, trialStart: start, now: start)).isLicensed)
    }

    @Test func forgedRevocationListIsIgnored() {
        let forger = Curve25519.Signing.PrivateKey()
        let forged = try! SignedBlob.encode(RevocationList(issued: 1, ids: ["L-VECTOR0001"]), prefix: RevocationList.prefix, signingKey: forger)
        #expect(evaluator.evaluate(.init(key: Self.key, revocations: forged, trialStart: start, now: start)).isLicensed)
    }

    @Test func tamperedPortalKeyFails() {
        var parts = Self.key.split(separator: ".").map(String.init)
        parts[1] = String(parts[1].dropLast()) + (parts[1].last == "A" ? "B" : "A")
        #expect(License.verify(parts.joined(separator: "."), publicKeys: keys, deviceID: Self.device, now: start).isFailure)
    }
}

extension LicensePortalVectorTests {
    @Test func secondSpellingOfSignatureIsRefused() {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let index = alphabet.firstIndex(of: Self.key.last!)!
        let twin = String(Self.key.dropLast()) + String(alphabet[index ^ 1])
        #expect(License.verify(twin, publicKeys: keys, deviceID: Self.device, now: start).isFailure)
    }
}

@Suite struct LicenseGateTests {
    let payload = LicensePayload(id: "L-1", email: "a@b.co", plan: "lifetime", issued: 1)

    @Test func gatingOffUnlocksEverything() {
        #expect(LicenseGate.allows(.pro, status: .trialEnded, gatingEnabled: false))
    }

    @Test func gracefulLockoutKeepsCore() {
        for status in [LicenseStatus.trialEnded, .expired(payload), .revoked(payload)] {
            #expect(LicenseGate.allows(.core, status: status, gatingEnabled: true))
            #expect(!LicenseGate.allows(.assistant, status: status, gatingEnabled: true))
        }
        #expect(LicenseGate.allows(.assistant, status: .trial(daysLeft: 3), gatingEnabled: true))
        #expect(LicenseGate.allows(.assistant, status: .licensed(payload, daysLeft: nil), gatingEnabled: true))
        #expect(!LicenseGate.allows(.pro, status: .licensed(payload, daysLeft: nil), gatingEnabled: true))
    }

    @Test func trialWithoutKeyCountsDown() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let evaluator = LicenseEvaluator(publicKeys: [Curve25519.Signing.PrivateKey().publicKey], deviceID: "x")
        #expect(evaluator.evaluate(.init(trialStart: start, now: start.addingTimeInterval(86_400 * 4))) == .trial(daysLeft: 10))
        #expect(evaluator.evaluate(.init(trialStart: start, now: start.addingTimeInterval(86_400 * 20))) == .trialEnded)
        #expect(evaluator.evaluate(.init(key: "junk", trialStart: start, now: start)) == .trial(daysLeft: 14))
    }

    @Test func serverErrorCodesMapToMessages() {
        #expect(LicenseServerClient.error(code: "seats_full", message: nil) == .seatsFull)
        #expect(LicenseServerClient.error(code: "revoked", message: nil) == .revoked)
        #expect(LicenseServerClient.isOffline(.server("Can't reach the license server. Check your connection and try again.")))
        #expect(!LicenseServerClient.isOffline(.seatsFull))
    }
}

extension Result {
    var isFailure: Bool { if case .failure = self { true } else { false } }
}
