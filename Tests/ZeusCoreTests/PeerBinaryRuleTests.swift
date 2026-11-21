import Foundation
import Testing
@testable import ZeusCore
#if canImport(Darwin)
import Darwin
#endif

/// Who a socket peer IS (signature and location), not what its file is called.
/// Pure rule tests plus disposable AF_UNIX peers. No app, no network, no permissions.
@Suite("Peer binary identity rule")
struct PeerBinaryRuleTests {
    private let bundle = "/Applications/Zeus.app"
    private let helpers = "/Applications/Zeus.app/Contents/Helpers"
    private let appBinary = "/Applications/Zeus.app/Contents/MacOS/Zeus"

    /// `anchored` is what the adapter reports after checking the running code against the requirement built from the
    /// server's identity. A real team or certificate peer meets it; a program that only claims the team does not.
    private func signature(valid: Bool = true, identifier: String? = "Zeus", team: String? = nil, adHoc: Bool = false,
                           certificate: String? = nil, cdHash: String? = nil, anchored: Bool? = nil) -> CodeSignature {
        let real = !adHoc && ((team?.isEmpty == false) || (certificate?.isEmpty == false))
        return CodeSignature(isValid: valid, identifier: identifier, teamIdentifier: team, isAdHoc: adHoc,
                             certificateHash: certificate, cdHash: cdHash, satisfiesIdentityRequirement: anchored ?? real)
    }

    private func decide(own: CodeSignature?, peer: CodeSignature?, path: String?, bundle: String? = "/Applications/Zeus.app",
                        directory: String? = "/Applications/Zeus.app/Contents/Helpers", hashes: Set<String> = [],
                        peerBundleHelpers: Set<String> = [], installedHelpers: String? = nil,
                        expectedPeerIdentifier: String? = nil, trustShippingBundle: Bool = false) -> PeerVerdict {
        PeerBinaryRule.decide(own: own, peer: peer, peerExecutablePath: path, ownBundlePath: bundle,
                              ownExecutableDirectory: directory, ownBundleCDHashes: hashes,
                              peerBundleHelperIdentifiers: peerBundleHelpers, installedHelpersDirectory: installedHelpers,
                              expectedPeerIdentifier: expectedPeerIdentifier, trustShippingBundle: trustShippingBundle)
    }

    // MARK: Team signed (release builds)

    @Test func aTeamSignedAppTrustsOnlyPeersFromTheSameTeam() {
        let own = signature(team: "ABCDE12345")
        #expect(decide(own: own, peer: signature(team: "ABCDE12345"), path: "/Users/me/bin/zeus") == .allow,
                "the installed copy of the zeus command lives outside the bundle and is still ours")
        #expect(!decide(own: own, peer: signature(team: "ZZZZZ99999"), path: appBinary).isAllowed, "another team, even inside our bundle path")
        #expect(!decide(own: own, peer: signature(team: nil), path: appBinary).isAllowed, "no team")
        #expect(!decide(own: own, peer: signature(team: nil, adHoc: true), path: appBinary).isAllowed, "ad hoc")
        #expect(!decide(own: own, peer: signature(team: "ABCDE12345", adHoc: true), path: appBinary).isAllowed, "ad hoc never counts as a team")
        #expect(!decide(own: own, peer: signature(valid: false, team: "ABCDE12345"), path: appBinary).isAllowed, "a broken signature")
        #expect(!decide(own: own, peer: nil, path: appBinary).isAllowed, "no signature at all")
    }

    @Test func anEmptyTeamIdentifierIsNotATeam() {
        let own = signature(team: "")
        let peer = signature(team: "")
        // Own has no real team, so the location rule decides and this path is outside the bundle.
        #expect(!decide(own: own, peer: peer, path: "/tmp/Zeus/Zeus").isAllowed)
        #expect(decide(own: own, peer: peer, path: appBinary) == .allow)
    }

    @Test func aMissingOrBrokenOwnSignatureRefusesEveryone() {
        #expect(!decide(own: nil, peer: signature(team: "ABCDE12345"), path: appBinary).isAllowed)
        #expect(!decide(own: signature(valid: false, team: "ABCDE12345"), peer: signature(team: "ABCDE12345"), path: appBinary).isAllowed)
    }

    // MARK: Ad hoc or locally signed (development builds, the test host)

    @Test func aLocalBuildTrustsPeersInsideItsOwnBundle() {
        let own = signature(adHoc: true)
        #expect(decide(own: own, peer: signature(adHoc: true), path: appBinary) == .allow)
        #expect(decide(own: own, peer: signature(adHoc: true), path: helpers + "/zeus") == .allow)
    }

    @Test func aLocalBuildTrustsPeersInTheSameBuildProductsDirectory() {
        let own = signature(adHoc: true)
        let products = "/work/.build/arm64-apple-macosx/debug"
        #expect(decide(own: own, peer: signature(adHoc: true), path: products + "/Zeus", bundle: nil, directory: products) == .allow)
        #expect(!decide(own: own, peer: signature(adHoc: true), path: "/work/.build/arm64-apple-macosx/release/Zeus", bundle: nil, directory: products).isAllowed)
    }

    @Test func aSameNamedBinaryOutsideTheBundleIsRefused() {
        let own = signature(adHoc: true)
        let copy = signature(adHoc: true)
        #expect(!decide(own: own, peer: copy, path: "/tmp/Zeus").isAllowed, "same file name, elsewhere")
        #expect(!decide(own: own, peer: copy, path: "/tmp/Zeus/Contents/MacOS/Zeus").isAllowed, "a folder named like the app")
        #expect(!decide(own: own, peer: copy, path: "/Users/me/Downloads/Zeus.app/Contents/MacOS/Zeus").isAllowed, "another copy of the app")
    }

    @Test func containmentIsPerPathComponentNotPerPrefix() {
        let own = signature(adHoc: true)
        let peer = signature(adHoc: true)
        #expect(!decide(own: own, peer: peer, path: "/Applications/Zeus.app.evil/Contents/MacOS/Zeus").isAllowed)
        #expect(!decide(own: own, peer: peer, path: "/Applications/Zeus.application").isAllowed)
        #expect(!decide(own: own, peer: peer, path: "/Applications/Zeus.app").isAllowed, "the bundle folder itself is not an executable inside it")
    }

    @Test func aPathWithTraversalOrNoRootIsRefused() {
        let own = signature(adHoc: true)
        let peer = signature(adHoc: true)
        #expect(!decide(own: own, peer: peer, path: "/Applications/Zeus.app/../../tmp/evil").isAllowed)
        #expect(!decide(own: own, peer: peer, path: "Zeus.app/Contents/MacOS/Zeus").isAllowed)
        #expect(!decide(own: own, peer: peer, path: "").isAllowed)
        #expect(!decide(own: own, peer: peer, path: nil).isAllowed)
    }

    @Test func aBrokenOrMissingPeerSignatureIsRefusedEvenInsideTheBundle() {
        let own = signature(adHoc: true)
        #expect(!decide(own: own, peer: signature(valid: false, adHoc: true), path: appBinary).isAllowed)
        #expect(!decide(own: own, peer: nil, path: appBinary).isAllowed)
    }

    @Test func aCopyOfABundledHelperIsTrustedByItsCodeDirectoryHash() {
        let own = signature(adHoc: true)
        let hashes: Set<String> = ["aa11", "bb22"]
        #expect(decide(own: own, peer: signature(adHoc: true, cdHash: "bb22"), path: "/Users/me/Library/Application Support/Zeus/bin/zeus", hashes: hashes) == .allow)
        #expect(!decide(own: own, peer: signature(adHoc: true, cdHash: "cc33"), path: "/Users/me/bin/zeus", hashes: hashes).isAllowed)
        #expect(!decide(own: own, peer: signature(adHoc: true, cdHash: nil), path: "/Users/me/bin/zeus", hashes: hashes).isAllowed)
        #expect(!decide(own: own, peer: signature(adHoc: true, cdHash: ""), path: "/Users/me/bin/zeus", hashes: [""]).isAllowed, "an empty hash never matches")
    }

    @Test func aLocalIdentityTrustsBinariesSignedWithTheSameCertificate() {
        let own = signature(certificate: "cert-1")
        #expect(decide(own: own, peer: signature(certificate: "cert-1"), path: "/Users/me/Library/Application Support/Zeus/bin/zeus-bridge") == .allow)
        #expect(!decide(own: own, peer: signature(certificate: "cert-2"), path: "/Users/me/bin/zeus-bridge").isAllowed)
        #expect(!decide(own: own, peer: signature(adHoc: true, certificate: nil), path: "/Users/me/bin/zeus-bridge").isAllowed)
        #expect(!decide(own: signature(adHoc: true), peer: signature(certificate: "cert-1"), path: "/Users/me/bin/x").isAllowed,
                "an ad hoc app has no certificate to compare")
    }

    // MARK: The installed bridge (a loose copy in Application Support) and the app that shipped it

    private let installedBin = "/Users/me/Library/Application Support/Zeus/bin"
    private let devApp = "/Users/me/zeus/dist/Zeus.app/Contents/MacOS/Zeus"

    /// `zeus-bridge` as Chrome starts it: no bundle around it, running from the folder the app copied it into.
    private func bridge(team: String? = nil, certificate: String? = nil, adHoc: Bool = true, cdHash: String? = "bridge-1") -> CodeSignature {
        signature(identifier: "zeus-bridge", team: team, adHoc: adHoc, certificate: certificate, cdHash: cdHash)
    }

    private func decideForBridge(own: CodeSignature, peer: CodeSignature, path: String?, peerBundleHelpers: Set<String> = [],
                                 expectedPeerIdentifier: String? = nil) -> PeerVerdict {
        decide(own: own, peer: peer, path: path, bundle: nil, directory: installedBin,
               peerBundleHelpers: peerBundleHelpers, installedHelpers: installedBin, expectedPeerIdentifier: expectedPeerIdentifier,
               trustShippingBundle: true)
    }

    private let appIdentifier = "app.zeus.mac"

    @Test func anAdHocInstalledBridgeTrustsTheAppThatShipsABridgeOfItsName() {
        let app = signature(identifier: appIdentifier, adHoc: true, cdHash: "app-1")
        #expect(decideForBridge(own: bridge(), peer: app, path: devApp, peerBundleHelpers: ["zeus-bridge", "zeus-hook"],
                                expectedPeerIdentifier: appIdentifier) == .allow, "an ad hoc build inside its own bundle")
        #expect(decideForBridge(own: bridge(), peer: app, path: "/Applications/Zeus.app/Contents/MacOS/Zeus",
                                peerBundleHelpers: ["zeus-bridge"], expectedPeerIdentifier: appIdentifier) == .allow, "wherever the app is installed")
    }

    @Test func anAdHocInstalledBridgeRefusesAnAppWhoseBundleShipsNoBridgeOfItsName() {
        let app = signature(identifier: appIdentifier, adHoc: true, cdHash: "app-1")
        #expect(!decideForBridge(own: bridge(), peer: app, path: devApp, peerBundleHelpers: ["zeus-hook"]).isAllowed, "another helper only")
        #expect(!decideForBridge(own: bridge(), peer: app, path: devApp, peerBundleHelpers: []).isAllowed, "no helpers")
        #expect(!decideForBridge(own: signature(identifier: nil, adHoc: true), peer: app, path: devApp, peerBundleHelpers: ["zeus-bridge"]).isAllowed,
                "the bridge has no name to match")
        #expect(!decideForBridge(own: signature(identifier: "", adHoc: true), peer: app, path: devApp, peerBundleHelpers: [""]).isAllowed,
                "an empty name never matches")
    }

    @Test func theBundleHelpersOnlyCountForAPeerThatRunsInsideThatBundle() {
        let app = signature(identifier: appIdentifier, adHoc: true, cdHash: "app-1")
        #expect(!decideForBridge(own: bridge(), peer: app, path: "/tmp/Zeus", peerBundleHelpers: ["zeus-bridge"]).isAllowed, "a loose binary has no bundle")
        #expect(!decideForBridge(own: bridge(), peer: app, path: nil, peerBundleHelpers: ["zeus-bridge"]).isAllowed)
        #expect(!decideForBridge(own: bridge(), peer: signature(valid: false, adHoc: true), path: devApp, peerBundleHelpers: ["zeus-bridge"]).isAllowed,
                "a broken peer signature")
    }

    @Test func aSameNamedBinaryOutsideTheBundleIsRefusedByTheInstalledBridge() {
        let copy = signature(identifier: appIdentifier, adHoc: true, cdHash: "copy-1")
        for path in ["/tmp/Zeus", "/tmp/Zeus/Contents/MacOS/Zeus", installedBin + "/Zeus", "/Users/me/Downloads/Zeus"] {
            #expect(!decideForBridge(own: bridge(), peer: copy, path: path, peerBundleHelpers: ["zeus-bridge"],
                                     expectedPeerIdentifier: appIdentifier).isAllowed, "\(path)")
        }
    }

    @Test func aLongRunningBridgeAcceptsTheSameAppAfterItWasRebuiltOrRestarted() {
        // The bridge was started by Chrome with build 1 of itself (cdhash bridge-1) and keeps that identity. The app has since
        // been rebuilt twice: a new cdhash for the app, a new bridge in its Helpers. Nothing that names one build may decide.
        let running = bridge(cdHash: "bridge-1")
        for build in ["app-1", "app-2", "app-3"] {
            let app = signature(identifier: appIdentifier, adHoc: true, cdHash: build)
            #expect(decideForBridge(own: running, peer: app, path: devApp, peerBundleHelpers: ["zeus-bridge", "zeus-hook"],
                                    expectedPeerIdentifier: appIdentifier) == .allow, "\(build)")
        }
    }

    @Test func aTeamSignedBridgeAcceptsANewBuildOfTheSameAppAndNoOtherTeam() {
        let running = bridge(team: "ABCDE12345", adHoc: false, cdHash: "bridge-1")
        let installed = "/Applications/Zeus.app/Contents/MacOS/Zeus"
        for build in ["app-1", "app-2"] {
            let app = signature(identifier: appIdentifier, team: "ABCDE12345", cdHash: build)
            #expect(decideForBridge(own: running, peer: app, path: installed, expectedPeerIdentifier: appIdentifier) == .allow,
                    "an updated app of the same team (\(build)), wherever it lives, with no helper hashes read")
        }
        let other = signature(identifier: appIdentifier, team: "ZZZZZ99999", cdHash: "app-9")
        #expect(!decideForBridge(own: running, peer: other, path: installed, peerBundleHelpers: ["zeus-bridge"],
                                 expectedPeerIdentifier: appIdentifier).isAllowed, "another team with the same bundle identifier")
        #expect(!decideForBridge(own: running, peer: signature(identifier: appIdentifier, adHoc: true), path: installed,
                                 peerBundleHelpers: ["zeus-bridge"], expectedPeerIdentifier: appIdentifier).isAllowed, "ad hoc copy of the app")
    }

    @Test func aTeamSignedBridgeRefusesAProgramOfTheSameTeamThatIsNotTheApp() {
        let running = bridge(team: "ABCDE12345", adHoc: false)
        let sibling = signature(identifier: "com.example.other-tool", team: "ABCDE12345")
        #expect(!decideForBridge(own: running, peer: sibling, path: "/Applications/Other.app/Contents/MacOS/Other",
                                 expectedPeerIdentifier: appIdentifier).isAllowed, "same team, another bundle identifier")
        #expect(!decideForBridge(own: running, peer: signature(identifier: nil, team: "ABCDE12345"), path: devApp,
                                 expectedPeerIdentifier: appIdentifier).isAllowed, "no identifier at all")
        #expect(decideForBridge(own: running, peer: sibling, path: "/Applications/Other.app/Contents/MacOS/Other") == .allow,
                "a server that names no identifier keeps the team rule alone")
    }

    @Test func aLocallySignedBridgeIgnoresAnAdHocAppInAnAssembledBundle() {
        // /tmp/X.app with an ad hoc program and a copy of the (readable) installed bridge must not stand in for the certificate.
        let assembled = "/tmp/X.app/Contents/MacOS/Zeus"
        let ownLocal = bridge(certificate: "cert-1", adHoc: false)
        let adHocApp = signature(identifier: appIdentifier, adHoc: true, cdHash: "app-x")
        #expect(!decideForBridge(own: ownLocal, peer: adHocApp, path: assembled, peerBundleHelpers: ["zeus-bridge"],
                                 expectedPeerIdentifier: appIdentifier).isAllowed)
        let realApp = signature(identifier: appIdentifier, certificate: "cert-1", cdHash: "app-2")
        #expect(decideForBridge(own: ownLocal, peer: realApp, path: devApp, expectedPeerIdentifier: appIdentifier) == .allow,
                "the same certificate still decides, with no helpers read")
        let otherCert = signature(identifier: appIdentifier, certificate: "cert-2", cdHash: "app-3")
        #expect(!decideForBridge(own: ownLocal, peer: otherCert, path: devApp, peerBundleHelpers: ["zeus-bridge"],
                                 expectedPeerIdentifier: appIdentifier).isAllowed, "another certificate")
    }

    @Test func theExpectedIdentifierAppliesToEveryKindOfOwnSignature() {
        let app = signature(identifier: "Zeus", adHoc: true)
        #expect(!decide(own: signature(adHoc: true), peer: app, path: appBinary, expectedPeerIdentifier: appIdentifier).isAllowed)
        #expect(decide(own: signature(adHoc: true), peer: app, path: appBinary, expectedPeerIdentifier: "Zeus") == .allow)
        #expect(decide(own: signature(adHoc: true), peer: app, path: appBinary) == .allow)
    }

    @Test func anInstalledProgramNeverTrustsItsOwnFolderAsABuildProductsFolder() {
        // Application Support is writable by any program of this user, so a same-named binary dropped there proves nothing.
        let inFolder = installedBin + "/Zeus"
        #expect(!decideForBridge(own: bridge(certificate: "cert-1", adHoc: false), peer: signature(adHoc: true), path: inFolder).isAllowed,
                "ad hoc copy beside the installed bridge")
        #expect(!decideForBridge(own: bridge(certificate: "cert-1", adHoc: false), peer: signature(certificate: "cert-2"), path: inFolder).isAllowed,
                "another certificate beside the installed bridge")
        #expect(!decideForBridge(own: bridge(), peer: signature(adHoc: true), path: inFolder).isAllowed)
        #expect(!decideForBridge(own: bridge(), peer: signature(adHoc: true), path: installedBin + "/sub/Zeus").isAllowed)
        #expect(decideForBridge(own: bridge(certificate: "cert-1", adHoc: false), peer: signature(certificate: "cert-1"), path: devApp) == .allow,
                "the same certificate still decides")
    }

    @Test func aFolderInsideTheInstalledFolderIsNotTrustedEither() {
        let own = signature(adHoc: true)
        let peer = signature(adHoc: true)
        let deeper = installedBin + "/build"
        #expect(!PeerBinaryRule.decide(own: own, peer: peer, peerExecutablePath: deeper + "/Zeus", ownBundlePath: nil,
                                       ownExecutableDirectory: deeper, installedHelpersDirectory: installedBin).isAllowed)
        #expect(PeerBinaryRule.decide(own: own, peer: peer, peerExecutablePath: "/work/.build/debug/Zeus", ownBundlePath: nil,
                                      ownExecutableDirectory: "/work/.build/debug", installedHelpersDirectory: installedBin) == .allow,
                "a build products folder elsewhere is still trusted")
    }

    // MARK: The identity is anchored, not claimed

    @Test func aTeamPeerThatOnlyClaimsTheTeamIsRefused() {
        // A self-signed certificate can carry the team identifier as its organizational unit. Signing information shows
        // the claim; only a check against Apple's chain proves it. The adapter reports that check as `anchored`.
        let own = signature(team: "ABCDE12345")
        let forged = signature(team: "ABCDE12345", anchored: false)
        #expect(!decide(own: own, peer: forged, path: appBinary).isAllowed, "inside the bundle path")
        #expect(!decide(own: own, peer: forged, path: "/tmp/Zeus").isAllowed, "outside it")
        #expect(!decide(own: own, peer: forged, path: appBinary, expectedPeerIdentifier: appIdentifier).isAllowed, "with the app identifier")
        #expect(decide(own: own, peer: signature(team: "ABCDE12345", anchored: true), path: "/tmp/Zeus") == .allow, "the real team")
    }

    @Test func aTeamSignedBridgeRefusesAForgedTeamPeer() {
        let running = bridge(team: "ABCDE12345", adHoc: false)
        let forged = signature(identifier: appIdentifier, team: "ABCDE12345", cdHash: "forged", anchored: false)
        #expect(!decideForBridge(own: running, peer: forged, path: "/Applications/Zeus.app/Contents/MacOS/Zeus",
                                 peerBundleHelpers: ["zeus-bridge"], expectedPeerIdentifier: appIdentifier).isAllowed)
    }

    @Test func aCertificatePeerThatIsNotAnchoredToTheCertificateIsRefused() {
        let own = signature(certificate: "cert-1")
        let path = "/Users/me/Library/Application Support/Zeus/bin/zeus-bridge"
        #expect(decide(own: own, peer: signature(certificate: "cert-1", anchored: true), path: path) == .allow)
        #expect(!decide(own: own, peer: signature(certificate: "cert-1", anchored: false), path: path).isAllowed,
                "the hash read from signing information alone is not enough")
    }

    @Test func theRequirementNamesTheAppleChainTheTeamAndTheIdentifier() {
        let team = PeerRequirement.text(ownTeam: "ABCDE12345", ownLeafSHA1: nil, ownIsAdHoc: false, peerIdentifier: nil)
        #expect(team == "anchor apple generic and certificate leaf[subject.OU] = \"ABCDE12345\"")
        let named = PeerRequirement.text(ownTeam: "ABCDE12345", ownLeafSHA1: nil, ownIsAdHoc: false, peerIdentifier: "app.zeus.mac")
        #expect(named == "anchor apple generic and certificate leaf[subject.OU] = \"ABCDE12345\" and identifier \"app.zeus.mac\"")
    }

    @Test func aTeamRequirementIgnoresTheCertificateOfAnAppThatHasATeam() {
        let sha1 = String(repeating: "ab", count: 20)
        let text = PeerRequirement.text(ownTeam: "ABCDE12345", ownLeafSHA1: sha1, ownIsAdHoc: false, peerIdentifier: nil)
        #expect(text?.contains("anchor apple generic") == true)
        #expect(text?.contains("H\"") == false)
    }

    @Test func aLocalIdentityRequirementNamesTheExactCertificate() {
        let sha1 = String(repeating: "ab", count: 20)
        #expect(PeerRequirement.text(ownTeam: nil, ownLeafSHA1: sha1, ownIsAdHoc: false, peerIdentifier: nil) == "certificate leaf = H\"\(sha1)\"")
        #expect(PeerRequirement.text(ownTeam: "", ownLeafSHA1: sha1.uppercased(), ownIsAdHoc: false, peerIdentifier: "app.zeus.mac")
                == "certificate leaf = H\"\(sha1)\" and identifier \"app.zeus.mac\"", "case is normalised and an empty team is no team")
    }

    @Test func noRequirementExistsWhenTheOwnerHasNoIdentityToName() {
        let sha1 = String(repeating: "ab", count: 20)
        #expect(PeerRequirement.text(ownTeam: nil, ownLeafSHA1: nil, ownIsAdHoc: false, peerIdentifier: nil) == nil, "no certificate")
        #expect(PeerRequirement.text(ownTeam: nil, ownLeafSHA1: sha1, ownIsAdHoc: true, peerIdentifier: nil) == nil, "ad hoc")
        #expect(PeerRequirement.text(ownTeam: nil, ownLeafSHA1: "abc", ownIsAdHoc: false, peerIdentifier: nil) == nil, "a short hash")
        #expect(PeerRequirement.text(ownTeam: nil, ownLeafSHA1: String(repeating: "zz", count: 20), ownIsAdHoc: false, peerIdentifier: nil) == nil, "not hex")
    }

    @Test func aMalformedTeamOrIdentifierNeverReachesTheRequirementText() {
        for team in ["ABC\" or true", "AB CD", "ABCDE12345\" and identifier \"x", "", "a/b"] {
            #expect(PeerRequirement.text(ownTeam: team, ownLeafSHA1: nil, ownIsAdHoc: false, peerIdentifier: nil) == nil, "\(team)")
        }
        for identifier in ["app\" or anchor apple", "a b", "x\\y", ""] {
            #expect(PeerRequirement.text(ownTeam: "ABCDE12345", ownLeafSHA1: nil, ownIsAdHoc: false, peerIdentifier: identifier) == nil, "\(identifier)")
        }
    }

    // MARK: The shipping-bundle allowance is the bridge's alone

    @Test func aServerThatDoesNotOptInRefusesAnAssembledBundle() {
        // A loose ad hoc Zeus (a SwiftPM build) serving the command socket must not accept /tmp/X.app holding a re-signed helper.
        let assembled = signature(identifier: appIdentifier, adHoc: true, cdHash: "x")
        let loose = signature(identifier: "Zeus", adHoc: true)
        #expect(!decide(own: loose, peer: assembled, path: "/tmp/X.app/Contents/MacOS/Zeus", bundle: nil, directory: installedBin,
                        peerBundleHelpers: ["Zeus"], installedHelpers: installedBin).isAllowed)
        #expect(decide(own: loose, peer: assembled, path: "/tmp/X.app/Contents/MacOS/Zeus", bundle: nil, directory: installedBin,
                       peerBundleHelpers: ["Zeus"], installedHelpers: installedBin, trustShippingBundle: true) == .allow,
                "the bridge opts in and keeps the allowance")
    }

    // MARK: Helpers

    @Test func theBundleIsTheNearestAppFolderAboveTheExecutable() {
        #expect(AppBundleLocator.bundlePath(forExecutable: "/Applications/Zeus.app/Contents/MacOS/Zeus") == "/Applications/Zeus.app")
        #expect(AppBundleLocator.bundlePath(forExecutable: "/Applications/Zeus.app/Contents/Helpers/zeus-bridge") == "/Applications/Zeus.app")
        #expect(AppBundleLocator.bundlePath(forExecutable: "/work/.build/debug/Zeus") == nil)
        #expect(AppBundleLocator.bundlePath(forExecutable: "/Users/me/Library/Application Support/Zeus/bin/zeus-bridge") == nil)
        #expect(AppBundleLocator.bundlePath(forExecutable: "/tmp/Fake.app") == nil, "the executable itself is not a bundle folder")
        #expect(AppBundleLocator.bundlePath(forExecutable: "relative/Zeus.app/Contents/MacOS/Zeus") == nil)
    }

    @Test func pathContainmentIsStrict() {
        #expect(PathContainment.isInside("/a/b/c", root: "/a/b"))
        #expect(PathContainment.isInside("/a/b/c/", root: "/a/b/"))
        #expect(!PathContainment.isInside("/a/b", root: "/a/b"))
        #expect(!PathContainment.isInside("/a/bc", root: "/a/b"))
        #expect(!PathContainment.isInside("/a/b/../x", root: "/a/b"))
        #expect(!PathContainment.isInside("a/b/c", root: "/a/b"))
        #expect(!PathContainment.isInside("/a/b/c", root: "/"), "the filesystem root is never a trusted folder")
        #expect(!PathContainment.isInside("/a/b/c", root: ""))
    }

    @Test func onlyTheNamedProgramPolicyNeedsASignedPeer() {
        #expect(PeerPolicy.sameUserExecutable(["Zeus"]).requiresSignedApp)
        #expect(!PeerPolicy.sameUser.requiresSignedApp)
    }

    // MARK: The real adapter, on this process

    #if canImport(Darwin)
    private func pairToken() throws -> Data {
        var pair: [Int32] = [0, 0]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer { close(pair[0]); close(pair[1]) }
        return try #require(PeerCheck.identify(fd: pair[0])?.auditToken)
    }

    @Test func theKernelGivesAnAuditTokenForAConnectedPair() throws {
        #expect(try pairToken().count == 32)
    }

    @Test func aProcessIsTrustedAsItsOwnApp() throws {
        let verdict = PeerSigning.verifyApp(auditToken: try pairToken())
        #expect(verdict == .allow, "\(verdict)")
    }

    @Test func theAppIdentifierIsEnforcedWhenTheServerNamesOne() throws {
        let token = try pairToken()
        let own = try #require(PeerSigning.captureOwnIdentity())
        #expect(!PeerSigning.verifyApp(auditToken: token, expectedPeerIdentifier: "no.such.app").isAllowed, "another bundle identifier")
        if let identifier = own.identifier, !identifier.isEmpty {
            #expect(PeerSigning.verifyApp(auditToken: token, expectedPeerIdentifier: identifier) == .allow)
        }
    }

    @Test func theBridgeVerifierDemandsTheAppsBundleIdentifier() throws {
        #expect(ChromeSocketPeers.expectedPeerIdentifier == ZeusPaths.bundleIdentifier)
        let own = try #require(PeerSigning.captureOwnIdentity())
        // This test host is validly signed and trusted as its own app, but it is not the Zeus app.
        try #require(own.identifier != ZeusPaths.bundleIdentifier)
        #expect(!ChromeSocketPeers.verifier(try pairToken()).isAllowed)
        #expect(!ChromeSocketPeers.verifier(nil).isAllowed)
    }

    @Test func readingTheOwnIdentityEarlyKeepsItForLater() throws {
        let first = try #require(PeerSigning.captureOwnIdentity())
        let second = try #require(PeerSigning.captureOwnIdentity())
        #expect(first == second, "read once, then kept, so a replaced file on disk cannot change it")
        #expect(first.isValid)
    }

    @Test func aMalformedOrUnknownTokenIsRefused() {
        #expect(!PeerSigning.verifyApp(auditToken: nil).isAllowed)
        #expect(!PeerSigning.verifyApp(auditToken: Data()).isAllowed)
        #expect(!PeerSigning.verifyApp(auditToken: Data(repeating: 0, count: 31)).isAllowed)
        #expect(!PeerSigning.verifyApp(auditToken: Data(repeating: 0xFF, count: 32)).isAllowed)
    }
    #endif

    /// A missing token is refused. Where this platform has no code signature, capture returns nil
    /// and a signature check stays denied.
    @Test func aPlatformWithoutCodeSignaturesDoesNotInventAnIdentity() {
        #if canImport(Darwin)
        #expect(!PeerSigning.verifyApp(auditToken: nil).isAllowed)
        #else
        #expect(PeerSigning.captureOwnIdentity() == nil)
        #expect(!PeerSigning.verifyApp(auditToken: nil).isAllowed)
        #expect(!PeerSigning.verifyApp(auditToken: Data(repeating: 0xAB, count: 32)).isAllowed)
        #endif
    }
}

/// The server asks the verifier before it reads a byte, and hands the handler a lazy verdict.
@Suite("Socket peer verification wiring", .serialized)
struct PeerVerificationWiringTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var tokens: [Int?] = []
        func bump(token: Data? = nil) { lock.withLock { count += 1; tokens.append(token?.count) } }
        var value: Int { lock.withLock { count } }
        var tokenSizes: [Int?] { lock.withLock { tokens } }
    }

    private func socketPath(_ name: String) throws -> (URL, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-peerv-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, root.appendingPathComponent(name).path)
    }

    private var ownName: String {
        (PeerCheck.executablePath(pid: getpid()).map { ($0 as NSString).lastPathComponent }) ?? "unknown"
    }

    @Test func aNamedProgramPolicyAlsoNeedsTheSignatureVerifierToAgree() async throws {
        let (root, path) = try socketPath("a.sock")
        defer { try? FileManager.default.removeItem(at: root) }
        let handled = Counter(), asked = Counter()
        let server = UnixSocketServer(path: path, peerPolicy: .sameUserExecutable([ownName]), peerVerifier: { token in
            asked.bump(token: token)
            return .deny("not this app")
        }) { _, reply in
            handled.bump()
            reply(Data("{}".utf8))
        }
        try server.start()
        defer { server.stop() }
        let reply = await Task.detached { UnixSocket.request(path: path, payload: Data("{}".utf8), expectReply: true, timeout: 2) }.value
        #expect(reply == nil)
        #expect(handled.value == 0, "the handler never sees a refused peer's bytes")
        #expect(asked.value == 1)
        #if canImport(Darwin)
        #expect(asked.tokenSizes == [32], "the verifier gets the kernel's audit token, not a pid")
        #else
        #expect(asked.tokenSizes == [nil], "without an audit token the verifier is still asked, and it has nothing it can trust")
        #endif
    }

    @Test func aNamedProgramPolicyAdmitsAPeerTheVerifierAccepts() async throws {
        let (root, path) = try socketPath("b.sock")
        defer { try? FileManager.default.removeItem(at: root) }
        let server = UnixSocketServer(path: path, peerPolicy: .sameUserExecutable([ownName]), peerVerifier: { _ in .allow }) { _, reply in
            reply(Data("{\"ok\":true}".utf8))
        }
        try server.start()
        defer { server.stop() }
        let reply = await Task.detached { UnixSocket.request(path: path, payload: Data("{}".utf8), expectReply: true, timeout: 2) }.value
        #expect(reply == Data("{\"ok\":true}".utf8))
    }

    @Test func theSameUserPolicyNeverRunsTheVerifierUnlessTheHandlerAsks() async throws {
        let (root, path) = try socketPath("c.sock")
        defer { try? FileManager.default.removeItem(at: root) }
        let asked = Counter()
        let server = UnixSocketServer(path: path, peerVerifier: { _ in asked.bump(); return .allow }) { _, reply in
            reply(Data("{}".utf8))
        }
        try server.start()
        defer { server.stop() }
        _ = await Task.detached { UnixSocket.request(path: path, payload: Data("{}".utf8), expectReply: true, timeout: 2) }.value
        #expect(asked.value == 0, "no idle cost: the signature is only read when a command needs it")
    }

    @Test func aHandlerCanAskWhetherThePeerIsTheAppAndTheAnswerIsCached() async throws {
        let (root, path) = try socketPath("d.sock")
        defer { try? FileManager.default.removeItem(at: root) }
        let asked = Counter()
        let server = UnixSocketServer(path: path, peerVerifier: { _ in asked.bump(); return .deny("not the app") }, contextHandler: { _, peer, reply in
            let first = peer.verifiedApp(), second = peer.verifiedApp()
            reply(Data((first == second && !first.isAllowed ? "refused" : "odd").utf8))
        })
        try server.start()
        defer { server.stop() }
        let reply = await Task.detached { UnixSocket.request(path: path, payload: Data("{}".utf8), expectReply: true, timeout: 2) }.value
        #expect(reply == Data("refused".utf8))
        #expect(asked.value == 1)
    }

    @Test func aHandlerSeesAnAllowedVerdictWhenTheVerifierAccepts() async throws {
        let (root, path) = try socketPath("e.sock")
        defer { try? FileManager.default.removeItem(at: root) }
        let server = UnixSocketServer(path: path, peerVerifier: { _ in .allow }, contextHandler: { _, peer, reply in
            reply(Data((peer.verifiedApp().isAllowed ? "app" : "other").utf8))
        })
        try server.start()
        defer { server.stop() }
        let reply = await Task.detached { UnixSocket.request(path: path, payload: Data("{}".utf8), expectReply: true, timeout: 2) }.value
        #expect(reply == Data("app".utf8))
    }

    private final class FirstCallGate: @unchecked Sendable {
        private let lock = NSLock()
        private let release = DispatchSemaphore(value: 0)
        private var calls = 0
        /// Blocks the first caller until `open()`; every later caller passes at once.
        func pass() { if lock.withLock({ calls += 1; return calls == 1 }) { _ = release.wait(timeout: .now() + 10) } }
        var entered: Int { lock.withLock { calls } }
        func open() { release.signal() }
    }

    @Test func aSlowSignatureCheckDoesNotHoldUpAnotherConnection() async throws {
        let (root, path) = try socketPath("f.sock")
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = FirstCallGate()
        let server = UnixSocketServer(path: path, peerPolicy: .sameUserExecutable([ownName]), peerVerifier: { _ in
            gate.pass()
            return .allow
        }) { _, reply in reply(Data("{\"ok\":true}".utf8)) }
        try server.start()
        defer { server.stop() }
        let slow = Task.detached { UnixSocket.request(path: path, payload: Data("{}".utf8), expectReply: true, timeout: 8) }
        for _ in 0..<200 where gate.entered == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(gate.entered == 1, "the first peer is being checked")
        let second = await Task.detached { UnixSocket.request(path: path, payload: Data("{}".utf8), expectReply: true, timeout: 2) }.value
        #expect(second == Data("{\"ok\":true}".utf8), "the second peer is not queued behind the first check")
        gate.open()
        #expect(await slow.value == Data("{\"ok\":true}".utf8), "the slow peer is admitted once its check passes")
    }
}
