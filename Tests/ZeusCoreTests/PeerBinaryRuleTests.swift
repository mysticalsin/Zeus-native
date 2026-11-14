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

    private func signature(valid: Bool = true, identifier: String? = "Zeus", team: String? = nil, adHoc: Bool = false,
                           certificate: String? = nil, cdHash: String? = nil) -> CodeSignature {
        CodeSignature(isValid: valid, identifier: identifier, teamIdentifier: team, isAdHoc: adHoc,
                      certificateHash: certificate, cdHash: cdHash)
    }

    private func decide(own: CodeSignature?, peer: CodeSignature?, path: String?, bundle: String? = "/Applications/Zeus.app",
                        directory: String? = "/Applications/Zeus.app/Contents/Helpers", hashes: Set<String> = [],
                        peerBundleHashes: Set<String> = [], installedHelpers: String? = nil) -> PeerVerdict {
        PeerBinaryRule.decide(own: own, peer: peer, peerExecutablePath: path, ownBundlePath: bundle,
                              ownExecutableDirectory: directory, ownBundleCDHashes: hashes,
                              peerBundleCDHashes: peerBundleHashes, installedHelpersDirectory: installedHelpers)
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
    private func bridge(certificate: String? = nil, adHoc: Bool = true, cdHash: String? = "bridge-1") -> CodeSignature {
        signature(identifier: "zeus-bridge", adHoc: adHoc, certificate: certificate, cdHash: cdHash)
    }

    private func decideForBridge(own: CodeSignature, peer: CodeSignature, path: String?, peerBundleHashes: Set<String> = []) -> PeerVerdict {
        decide(own: own, peer: peer, path: path, bundle: nil, directory: installedBin,
               peerBundleHashes: peerBundleHashes, installedHelpers: installedBin)
    }

    @Test func anAdHocInstalledBridgeTrustsTheAppThatShipsAnExactCopyOfIt() {
        let app = signature(adHoc: true, cdHash: "app-1")
        #expect(decideForBridge(own: bridge(), peer: app, path: devApp, peerBundleHashes: ["bridge-1", "hook-1"]) == .allow)
        #expect(decideForBridge(own: bridge(), peer: app, path: "/Applications/Zeus.app/Contents/MacOS/Zeus", peerBundleHashes: ["bridge-1"]) == .allow,
                "wherever the app is installed")
    }

    @Test func anAdHocInstalledBridgeRefusesAnAppWhoseBundleHoldsAnotherBuildOfIt() {
        let app = signature(adHoc: true, cdHash: "app-1")
        #expect(!decideForBridge(own: bridge(), peer: app, path: devApp, peerBundleHashes: ["bridge-2", "hook-1"]).isAllowed, "a different build")
        #expect(!decideForBridge(own: bridge(), peer: app, path: devApp, peerBundleHashes: []).isAllowed, "no helper hashes")
        #expect(!decideForBridge(own: bridge(cdHash: nil), peer: app, path: devApp, peerBundleHashes: ["bridge-1"]).isAllowed, "the bridge has no hash")
        #expect(!decideForBridge(own: bridge(cdHash: ""), peer: app, path: devApp, peerBundleHashes: [""]).isAllowed, "an empty hash never matches")
    }

    @Test func theBundleHashesOnlyCountForAPeerThatRunsInsideThatBundle() {
        let app = signature(adHoc: true, cdHash: "app-1")
        #expect(!decideForBridge(own: bridge(), peer: app, path: "/tmp/Zeus", peerBundleHashes: ["bridge-1"]).isAllowed, "a loose binary has no bundle")
        #expect(!decideForBridge(own: bridge(), peer: app, path: nil, peerBundleHashes: ["bridge-1"]).isAllowed)
        #expect(!decideForBridge(own: bridge(), peer: signature(valid: false, adHoc: true), path: devApp, peerBundleHashes: ["bridge-1"]).isAllowed,
                "a broken peer signature")
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

    @Test func aMalformedOrUnknownTokenIsRefused() {
        #expect(!PeerSigning.verifyApp(auditToken: nil).isAllowed)
        #expect(!PeerSigning.verifyApp(auditToken: Data()).isAllowed)
        #expect(!PeerSigning.verifyApp(auditToken: Data(repeating: 0, count: 31)).isAllowed)
        #expect(!PeerSigning.verifyApp(auditToken: Data(repeating: 0xFF, count: 32)).isAllowed)
    }
    #endif
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
        #if canImport(Darwin)
        return (PeerCheck.executablePath(pid: getpid()).map { ($0 as NSString).lastPathComponent }) ?? "unknown"
        #else
        return "unknown"
        #endif
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
        #expect(asked.tokenSizes == [32], "the verifier gets the kernel's audit token, not a pid")
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
}
