import Foundation
import Testing
@testable import ZeusCore

/// A release version is one, two or three components of ASCII digits. Pre-release text,
/// a sign, a build suffix and a non-numeric component are not a release.
@Suite("Update version parsing")
struct UpdateVersionParseTests {
    @Test func releaseVersionsKeepTheirNumericComponents() {
        #expect(ZeusVersion(parsing: "0") == ZeusVersion(major: 0, minor: 0, patch: 0))
        #expect(ZeusVersion(parsing: "0.0") == ZeusVersion(major: 0, minor: 0, patch: 0))
        #expect(ZeusVersion(parsing: "0.0.0") == ZeusVersion(major: 0, minor: 0, patch: 0))
        #expect(ZeusVersion(parsing: "2") == ZeusVersion(major: 2, minor: 0, patch: 0))
        #expect(ZeusVersion(parsing: "2.0") == ZeusVersion(major: 2, minor: 0, patch: 0))
        #expect(ZeusVersion(parsing: "2.0.0") == ZeusVersion(major: 2, minor: 0, patch: 0))
        #expect(ZeusVersion(parsing: "  2.0.0\n") == ZeusVersion(major: 2, minor: 0, patch: 0))
        #expect(ZeusVersion(parsing: "10.20.30") == ZeusVersion(major: 10, minor: 20, patch: 30))
        #expect(ZeusVersion(parsing: "02.03.04") == ZeusVersion(major: 2, minor: 3, patch: 4))
        #expect(ZeusVersion(parsing: "9223372036854775807") == ZeusVersion(major: 9223372036854775807, minor: 0, patch: 0))
    }

    @Test func preReleaseAndNonNumericComponentsAreRejected() {
        let rejected = [
            "", "   ", "2.0.0-rc1", "2.0.0-rc.1", "2.0.0-alpha", "2.0.0-alpha.1",
            "2.0.0+build", "2.0.0+build.5", "2.0.0-rc1+build", "v2.0.0", "2.0.0a",
            "2..0", "2.0.", ".2.0", ".", "2.0.0.1", "-1.0.0", "2.-1.0", "2.0.-1",
            "a.b.c", "2. 0.0", "+1", "1e2", "2.0.0-", "9223372036854775808",
            "999999999999999999999", "٢.0.0",
        ]
        for text in rejected {
            #expect(ZeusVersion(parsing: text) == nil, "\(text)")
        }
        #expect(ZeusVersion(parsing: "2.0.0-rc1") != ZeusVersion(major: 2, minor: 0, patch: 0))
    }

    @Test func aPreReleaseFeedVersionIsNotAnOffer() throws {
        let prerelease = Data(#"{"version":"2.0.0-rc1","downloadURL":"https://zeus.example.com/Zeus.dmg"}"#.utf8)
        #expect(FeedUpdateFetcher.offer(from: prerelease) == nil)
        let stable = Data(#"{"version":"2.0.0","downloadURL":"https://zeus.example.com/Zeus.dmg"}"#.utf8)
        let offer = try #require(FeedUpdateFetcher.offer(from: stable))
        #expect(offer.latest == ZeusVersion(major: 2, minor: 0, patch: 0))
        #expect(offer.downloadURL?.absoluteString == "https://zeus.example.com/Zeus.dmg")
    }
}
