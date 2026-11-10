import CryptoKit
import Foundation
import Testing
@testable import ZeusCore

@Suite struct LicenseTests {
    let signer = Curve25519.Signing.PrivateKey()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let mac = License.deviceID(hardwareUUID: "TEST-UUID-1")

    func key(expires: Int? = nil, device: String? = nil) throws -> String {
        try License.encode(LicensePayload(id: "L-1", email: "a@example.com", plan: "lifetime", issued: 1_700_000_000,
                                          expires: expires, device: device), signingKey: signer)
    }

    @Test func validKeyVerifies() throws {
        let result = License.verify(try key(device: mac), publicKey: signer.publicKey, deviceID: mac, now: now)
        #expect(try result.get().email == "a@example.com")
    }

    @Test func tamperedKeyFails() throws {
        let parts = try key().split(separator: ".").map(String.init)
        let forged = try JSONEncoder().encode(LicensePayload(id: "L-1", email: "a@example.com", plan: "pro", issued: 1_700_000_000))
        let tampered = [parts[0], License.base64URL(forged), parts[2]].joined(separator: ".")
        #expect(License.verify(tampered, publicKey: signer.publicKey, deviceID: mac, now: now) == .failure(.badSignature))
        let other = Curve25519.Signing.PrivateKey().publicKey
        #expect(License.verify(try key(), publicKey: other, deviceID: mac, now: now) == .failure(.badSignature))
        #expect(License.verify("ZEUS1.nope", publicKey: signer.publicKey, deviceID: mac, now: now) == .failure(.malformed))
    }

    @Test func expiredKeyFails() throws {
        #expect(License.verify(try key(expires: 1_750_000_000), publicKey: signer.publicKey, deviceID: mac, now: now) == .failure(.expired))
        #expect((try? License.verify(try key(expires: 1_900_000_000), publicKey: signer.publicKey, deviceID: mac, now: now).get()) != nil)
    }

    @Test func wrongDeviceFails() throws {
        let other = License.deviceID(hardwareUUID: "TEST-UUID-2")
        #expect(License.verify(try key(device: other), publicKey: signer.publicKey, deviceID: mac, now: now) == .failure(.wrongDevice))
    }

    @Test func pastedWithLineBreaksStillVerifies() throws {
        let wrapped = try key().enumerated().map { $0.offset % 40 == 39 ? "\($0.element)\n" : "\($0.element)" }.joined()
        #expect((try? License.verify(wrapped, publicKey: signer.publicKey, deviceID: mac, now: now).get()) != nil)
    }

    @Test func trialCountsDown() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Trial.daysLeft(start: start, now: start) == 14)
        #expect(Trial.daysLeft(start: start, now: start.addingTimeInterval(86_400 * 3)) == 11)
        #expect(Trial.daysLeft(start: start, now: start.addingTimeInterval(86_400 * 30)) == 0)
    }
}
