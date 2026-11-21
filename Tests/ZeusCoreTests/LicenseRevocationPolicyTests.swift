import Foundation
import Testing
@testable import ZeusCore

/// A revocation that was already accepted stays revoked when the signed list is missing or will not decode.
/// No Keychain, network or signature. A decoded list, including an empty one, is the authority.
@Suite struct LicenseRevocationPolicyTests {
    @Test func aMissingOrUndecodableListKeepsARecordedRevocation() {
        #expect(LicenseRevocationPolicy.isRevoked(id: "L-1", decodedIDs: nil, lastGoodIDs: ["L-1"]))
        #expect(!LicenseRevocationPolicy.isRevoked(id: "L-2", decodedIDs: nil, lastGoodIDs: ["L-1"]))
        #expect(LicenseRevocationPolicy.isRevoked(id: "L-1", decodedIDs: nil, lastGoodIDs: ["L-9", "L-1"]))
    }

    @Test func noRecordMeansAMissingListDoesNotRevoke() {
        #expect(!LicenseRevocationPolicy.isRevoked(id: "L-1", decodedIDs: nil, lastGoodIDs: []))
    }

    @Test func aDecodedListIsTheAuthority() {
        #expect(LicenseRevocationPolicy.isRevoked(id: "L-1", decodedIDs: ["L-1"], lastGoodIDs: []))
        #expect(!LicenseRevocationPolicy.isRevoked(id: "L-1", decodedIDs: [], lastGoodIDs: ["L-1"]))
        #expect(!LicenseRevocationPolicy.isRevoked(id: "L-2", decodedIDs: ["L-1"], lastGoodIDs: ["L-2"]))
    }

    @Test func keychainIdsRemainWhenDefaultsWereClearedOrEmptied() {
        #expect(LicenseRevocationPolicy.load(defaultsIDs: nil, keychainText: "L-1\nL-2") == ["L-1", "L-2"])
        #expect(LicenseRevocationPolicy.load(defaultsIDs: [], keychainText: "L-1") == ["L-1"])
        #expect(LicenseRevocationPolicy.load(defaultsIDs: ["L-3"], keychainText: "L-1") == ["L-1", "L-3"])
        #expect(LicenseRevocationPolicy.load(defaultsIDs: nil, keychainText: nil) == [])
        #expect(LicenseRevocationPolicy.load(defaultsIDs: nil, keychainText: "") == [])
        #expect(LicenseRevocationPolicy.keychainText(ids: ["L-1", "L-2"]) == "L-1\nL-2")
    }
}
