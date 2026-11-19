import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The app-side wiring of "Allow command-line control": the function `CommandCenter.handle` asks before it runs
/// anything, with a stub peer and a stub switch. No Keychain, no socket, no capture.
@Suite("Command-line gate wiring")
struct CLIAccessWiringTests {
    private final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func bump() { lock.withLock { count += 1 } }
    }

    private func peer(_ verdict: PeerVerdict, asked: Asked = Asked()) -> PeerContext {
        PeerContext { asked.bump(); return verdict }
    }

    private func admission(_ op: ZeusCommand.Op, _ sub: String = "", _ argument: String = "", peer: PeerContext?, on: Bool) -> CLIAccess.Admission {
        CLIAccess.admission(op: op, debugSubcommand: sub, argument: argument, peer: peer, gateEnabled: { on })
    }

    @Test func aSensitiveCommandIsRefusedWhenTheSwitchIsOnButThePeerIsRejected() {
        let result = admission(.listen, peer: peer(.deny("copied binary")), on: true)
        #expect(result.refusal == CLIAccess.peerRefusal)
        #expect(!result.raisesCue, "a refused capture never raises the cue")
        for sub in ["screenshot", "second-brain-lookup", "learn", "dictate-file"] {
            #expect(admission(.debug, sub, "x", peer: peer(.deny("copied binary")), on: true).refusal == CLIAccess.peerRefusal, "\(sub)")
        }
    }

    @Test func aSensitiveCommandIsRefusedWhenThereIsNoPeerAtAll() {
        for op in [ZeusCommand.Op.listen, .browse, .code, .term] {
            let result = admission(op, peer: nil, on: true)
            #expect(result.refusal == CLIAccess.peerRefusal, "\(op)")
            #expect(!result.raisesCue)
        }
        #expect(admission(.debug, "screenshot", "/tmp/x", peer: nil, on: true).refusal == CLIAccess.peerRefusal)
    }

    @Test func theSwitchOffRefusesBeforeThePeerIsEverRead() {
        let asked = Asked()
        let result = admission(.listen, peer: peer(.allow, asked: asked), on: false)
        #expect(result.refusal == CLIAccess.refusal)
        #expect(!result.raisesCue)
        #expect(asked.value == 0)
    }

    @Test func anAllowedCapturingCommandRaisesTheCueAndOthersDoNot() {
        let ok = peer(.allow)
        #expect(admission(.listen, peer: ok, on: true) == CLIAccess.Admission(refusal: nil, raisesCue: true))
        #expect(admission(.debug, "record", "--seconds 5", peer: ok, on: true) == CLIAccess.Admission(refusal: nil, raisesCue: true))
        #expect(admission(.debug, "screenshot", "/tmp/x", peer: ok, on: true) == CLIAccess.Admission(refusal: nil, raisesCue: false))
        #expect(admission(.browse, peer: ok, on: true) == CLIAccess.Admission(refusal: nil, raisesCue: false))
    }

    @Test func aCommandThatIsNotSensitiveNeedsNeitherTheSwitchNorThePeer() {
        let asked = Asked()
        let result = admission(.status, peer: peer(.deny("anything"), asked: asked), on: false)
        #expect(result == CLIAccess.Admission(refusal: nil, raisesCue: false))
        #expect(asked.value == 0, "no signature is read for a read-only command")
    }

    // MARK: Where a screenshot may go

    private func scratch() throws -> (String, () -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-gate-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let real = try #require(DebugOutputPath.realPath(root.path))
        return (real, { try? FileManager.default.removeItem(at: root) })
    }

    @Test func aScreenshotPathOutsideTheAllowedFoldersIsRefused() throws {
        let (caches, cleanup) = try scratch()
        defer { cleanup() }
        for path in ["/tmp/x", "/Users/Shared/x.png", "\(caches)/elsewhere/x", "relative/x", caches + "/../x"] {
            let plan = CLIAccess.screenshotPlan(argument: path, cachesDirectory: caches, environment: [:])
            #expect((try? plan.get()) == nil, "\(path)")
        }
    }

    @Test func aScreenshotPathInsideTheAppCachesFolderIsAccepted() throws {
        let (caches, cleanup) = try scratch()
        defer { cleanup() }
        let inside = DebugOutputPath.appCachesFolder(cachesDirectory: caches) + "/DebugScreenshots/x"
        let accepted = try #require(try? CLIAccess.screenshotPlan(argument: inside + " --window notch", cachesDirectory: caches, environment: [:]).get())
        #expect(accepted.path.hasSuffix("/DebugScreenshots/x"))
        #expect(accepted.filter == "notch")
        let byDefault = try #require(try? CLIAccess.screenshotPlan(argument: "", cachesDirectory: caches, environment: [:], token: "t1").get())
        #expect(byDefault.path.hasSuffix("/DebugScreenshots/zeus-screenshot-t1"))
    }

    @Test func aBroadFolderChosenAtLaunchDoesNotWidenTheScreenshotFolders() throws {
        let (caches, cleanup) = try scratch()
        defer { cleanup() }
        let home = NSHomeDirectory()
        let environment = [DebugOutputPath.ownerFolderVariable: home]
        let plan = CLIAccess.screenshotPlan(argument: home + "/.zshrc", cachesDirectory: caches, environment: environment)
        #expect((try? plan.get()) == nil)
    }
}
