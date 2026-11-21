import Foundation
import Testing
@testable import ZeusCore

private struct FakeSignature: BundledHelperSignatureChecking {
    var team: String?
    var matches: Bool
    func mainAppTeamIdentifier() -> String? { team }
    func helperSatisfiesRequirement(at path: String, teamIdentifier: String, signingIdentifier: String) -> Bool { matches }
}

@Suite struct SupportOverrideResolverTests {
    private let home = "/Users/owner/Library/Application Support/Zeus"
    private let redirected = "/tmp/not-zeus-support"

    @Test func releaseIgnoresTheSupportDirectoryOverride() {
        let env = SupportOverrideMap(["ZEUS_SUPPORT_DIR": redirected])
        #expect(SupportOverride.supportDirectory(environment: env, build: .release, defaultDirectory: home) == home)
        #expect(SupportOverride.value("ZEUS_SUPPORT_DIR", environment: env, build: .release) == nil)
    }

    @Test func debugKeepsTheSupportDirectoryOverride() {
        let env = SupportOverrideMap(["ZEUS_SUPPORT_DIR": redirected])
        #expect(SupportOverride.supportDirectory(environment: env, build: .debug, defaultDirectory: home) == redirected)
        #expect(SupportOverride.value("ZEUS_SOCKET", environment: SupportOverrideMap(["ZEUS_SOCKET": "/tmp/zeus.sock"]), build: .debug) == "/tmp/zeus.sock")
    }

    @Test func releaseIgnoresEveryPathAndHelperOverride() {
        #expect(SupportOverride.names.contains("ZEUS_SUPPORT_DIR"))
        var values: [String: String] = [:]
        for name in SupportOverride.names { values[name] = redirected }
        let env = SupportOverrideMap(values)
        for name in SupportOverride.names {
            #expect(SupportOverride.value(name, environment: env, build: .release) == nil, "\(name)")
            #expect(SupportOverride.value(name, environment: env, build: .debug) == redirected, "\(name)")
        }
    }

    @Test func emptyAndWhitespaceOverridesAreAbsentInBothBuilds() {
        for build in [SupportOverrideBuild.debug, .release] {
            for raw in ["", " ", "\t", "\n"] {
                let env = SupportOverrideMap(["ZEUS_SUPPORT_DIR": raw, "ZEUS_SOCKET": raw])
                #expect(SupportOverride.value("ZEUS_SUPPORT_DIR", environment: env, build: build) == nil)
                #expect(SupportOverride.supportDirectory(environment: env, build: build, defaultDirectory: home) == home)
            }
            #expect(SupportOverride.value("ZEUS_LOG_DIR", environment: SupportOverrideMap([:]), build: build) == nil)
        }
    }

    @Test func theBridgeRequirementPinsTheTeamAndTheBridgeIdentifier() {
        let text = BundledHelperLaunchPolicy.requirementText(teamIdentifier: "ABCDE12345", signingIdentifier: BundledHelperLaunchPolicy.bridgeSigningIdentifier)
        #expect(text == "anchor apple generic and certificate leaf[subject.OU] = \"ABCDE12345\" and identifier \"zeus-bridge\"")
    }

    @Test func aRequirementIsNotBuiltFromAValueThatCouldAddAClause() {
        #expect(BundledHelperLaunchPolicy.requirementText(teamIdentifier: "ABCD\"E1234", signingIdentifier: "zeus-bridge") == nil)
        #expect(BundledHelperLaunchPolicy.requirementText(teamIdentifier: "ABCDE12345", signingIdentifier: "zeus-bridge\" and true") == nil)
        #expect(BundledHelperLaunchPolicy.requirementText(teamIdentifier: "", signingIdentifier: "zeus-bridge") == nil)
        #expect(BundledHelperLaunchPolicy.requirementText(teamIdentifier: "ABCDE12345", signingIdentifier: "") == nil)
    }

    @Test func launchIsRefusedWhenTheRequirementIsNotMet() {
        let checker = FakeSignature(team: "ABCDE12345", matches: false)
        let decision = BundledHelperLaunchPolicy.decide(helperPath: "/Applications/Zeus.app/Contents/Helpers/zeus-bridge",
                                                        signingIdentifier: "zeus-bridge", checker: checker)
        #expect(decision == .refuse(BundledHelperLaunchPolicy.refusalSentence))
    }

    @Test func launchIsRefusedWhenTheTeamCannotBeRead() {
        let checker = FakeSignature(team: nil, matches: true)
        let decision = BundledHelperLaunchPolicy.decide(helperPath: "/Applications/Zeus.app/Contents/Helpers/zeus-bridge",
                                                        signingIdentifier: "zeus-bridge", checker: checker)
        #expect(decision == .refuse(BundledHelperLaunchPolicy.refusalSentence))
    }

    @Test func launchIsRefusedForAnEmptyPathOrAnUnknownIdentifier() {
        let checker = FakeSignature(team: "ABCDE12345", matches: true)
        #expect(BundledHelperLaunchPolicy.decide(helperPath: "  ", signingIdentifier: "zeus-bridge", checker: checker)
                == .refuse(BundledHelperLaunchPolicy.refusalSentence))
        #expect(BundledHelperLaunchPolicy.decide(helperPath: "/tmp/evil", signingIdentifier: "evil", checker: checker)
                == .refuse(BundledHelperLaunchPolicy.refusalSentence))
        #expect(BundledHelperLaunchPolicy.decide(helperPath: "/tmp/zeus-bridge", signingIdentifier: "zeus", checker: checker)
                == .refuse(BundledHelperLaunchPolicy.refusalSentence))
    }

    @Test func launchProceedsOnlyWhenThePinnedRequirementMatches() {
        let checker = FakeSignature(team: "ABCDE12345", matches: true)
        #expect(BundledHelperLaunchPolicy.decide(helperPath: "/Applications/Zeus.app/Contents/Helpers/zeus-bridge",
                                                signingIdentifier: "zeus-bridge", checker: checker) == .launch)
    }

    @Test func developerIDRequirementUsesTheAppleAnchorAndLaunchesWhenItMatches() {
        let expected = "anchor apple generic and certificate leaf[subject.OU] = \"ABCDE12345\" and identifier \"zeus-bridge\""
        let text = BundledHelperLaunchPolicy.requirementText(anchor: .developerID(teamIdentifier: "ABCDE12345"), signingIdentifier: "zeus-bridge")
        #expect(text == expected)
        let checker = AnchorFake(anchor: .developerID(teamIdentifier: "ABCDE12345"), accepted: expected)
        #expect(BundledHelperLaunchPolicy.decide(helperPath: "/Applications/Zeus.app/Contents/Helpers/zeus-bridge",
                                                signingIdentifier: "zeus-bridge", checker: checker) == .launch)
    }

    @Test func localDevRequirementOmitsTheAppleAnchorAndLaunchesWhenTheLeafMatches() {
        let leaf = "0123456789abcdef0123456789abcdef01234567"
        let expected = "certificate leaf = H\"\(leaf)\" and identifier \"zeus-bridge\""
        let text = BundledHelperLaunchPolicy.requirementText(anchor: .localDev(leafSHA1: leaf), signingIdentifier: "zeus-bridge")
        #expect(text == expected)
        #expect(text?.contains("anchor apple generic") == false)
        let checker = AnchorFake(anchor: .localDev(leafSHA1: leaf), accepted: expected)
        #expect(BundledHelperLaunchPolicy.decide(helperPath: "/Applications/Zeus.app/Contents/Helpers/zeus-bridge",
                                                signingIdentifier: "zeus-bridge", checker: checker) == .launch)
    }

    @Test func aMissingAnchorStillRefuses() {
        let checker = AnchorFake(anchor: nil, accepted: "")
        #expect(BundledHelperLaunchPolicy.decide(helperPath: "/Applications/Zeus.app/Contents/Helpers/zeus-bridge",
                                                signingIdentifier: "zeus-bridge", checker: checker)
                == .refuse(BundledHelperLaunchPolicy.refusalSentence))
    }
}

private struct AnchorFake: BundledHelperAnchorChecking {
    var anchor: HelperSigningAnchor?
    var accepted: String
    func signingAnchor() -> HelperSigningAnchor? { anchor }
    func helperSatisfies(anchor: HelperSigningAnchor, signingIdentifier: String, at path: String) -> Bool {
        BundledHelperLaunchPolicy.requirementText(anchor: anchor, signingIdentifier: signingIdentifier) == accepted
    }
}

@Suite struct BridgePublishTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-bridge-publish-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aRejectedStageLeavesThePreviousBridgeAndRegistration() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("zeus-bridge")
        let registration = root.appendingPathComponent("com.zeus.bridge.json")
        let staged = root.appendingPathComponent("zeus-bridge.new")
        try Data("previous-bridge".utf8).write(to: destination)
        try Data("previous-registration".utf8).write(to: registration)
        try Data("rejected-stage".utf8).write(to: staged)
        let outcome = BundledHelperPublish.replaceIfAccepted(staged: staged, destination: destination, registration: registration,
                                                             accept: { _ in false }, writeRegistration: { throw TestWrite.failed })
        guard case .failure(.rejected) = outcome else {
            Issue.record("expected the stage to be rejected")
            return
        }
        #expect(try Data(contentsOf: destination) == Data("previous-bridge".utf8))
        #expect(try Data(contentsOf: registration) == Data("previous-registration".utf8))
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test func anAcceptedStageReplacesTheBridgeAndThenWritesTheRegistration() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("zeus-bridge")
        let registration = root.appendingPathComponent("com.zeus.bridge.json")
        let staged = root.appendingPathComponent("zeus-bridge.new")
        try Data("previous-bridge".utf8).write(to: destination)
        try Data("previous-registration".utf8).write(to: registration)
        try Data("new-bridge".utf8).write(to: staged)
        let outcome = BundledHelperPublish.replaceIfAccepted(staged: staged, destination: destination, registration: registration,
                                                             accept: { _ in true }, writeRegistration: {
                                                                 try Data("new-registration".utf8).write(to: registration)
                                                             })
        guard case .success = outcome else {
            Issue.record("expected the stage to be published")
            return
        }
        #expect(try Data(contentsOf: destination) == Data("new-bridge".utf8))
        #expect(try Data(contentsOf: registration) == Data("new-registration".utf8))
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }
}

private enum TestWrite: Error { case failed }

@Suite struct HookRefreshPolicyTests {
    @Test func aFailedHookCheckLeavesPriorEntries() {
        let prior = #"{"Stop":"/Applications/Zeus.app/Contents/Helpers/zeus-hook","other":"/usr/bin/true"}"#
        let effect = HookRefreshPolicy.effect(decision: .refuse(BundledHelperLaunchPolicy.refusalSentence),
                                              current: prior,
                                              publishedPath: "/Applications/Zeus.app/Contents/Helpers/zeus-hook")
        #expect(effect == .leave)
    }

    @Test func aPassingCheckRewritesOnlyWhenThePublishedPathIsMissing() {
        let path = "/Applications/Zeus.app/Contents/Helpers/zeus-hook"
        let stale = #"{"Stop":"/Users/tony/Library/Application Support/Zeus/bin/zeus-hook"}"#
        let current = #"{"Stop":"\#(path)"}"#
        #expect(HookRefreshPolicy.effect(decision: .launch, current: stale, publishedPath: path) == .rewriteToPublishedPath)
        #expect(HookRefreshPolicy.effect(decision: .launch, current: current, publishedPath: path) == .leave)
    }
}

@Suite struct NativeHostRegistrationTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-host-reg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeHosts(_ directory: URL, zeusPath: String) throws {
        let zeus: [String: String] = ["name": "com.zeus.bridge", "path": zeusPath, "type": "stdio"]
        let other: [String: String] = ["name": "com.other.host", "path": "/Library/Application Support/Other/host", "type": "stdio"]
        let zeusData = try JSONSerialization.data(withJSONObject: zeus, options: [.sortedKeys])
        let otherData = try JSONSerialization.data(withJSONObject: other, options: [.sortedKeys])
        try zeusData.write(to: directory.appendingPathComponent(NativeHostRegistration.zeusHostFileName))
        try otherData.write(to: directory.appendingPathComponent("com.other.host.json"))
    }

    @Test func aRefusedBundledPathRemovesTheHostRegistration() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = "/Applications/Zeus.app/Contents/Helpers/zeus-bridge"
        try writeHosts(root, zeusPath: bundled)
        let bridgeBinary = root.appendingPathComponent("zeus-bridge")
        try Data("support-bridge".utf8).write(to: bridgeBinary)
        try NativeHostRegistration.reconcile(decision: .refuse(BundledHelperLaunchPolicy.refusalSentence),
                                              checkedPath: bundled, hostsDirectory: root)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(NativeHostRegistration.zeusHostFileName).path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("com.other.host.json").path))
        #expect(try Data(contentsOf: bridgeBinary) == Data("support-bridge".utf8))
    }

    @Test func aLegacyUserWritablePathIsRemovedOnRefusal() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = "/Applications/Zeus.app/Contents/Helpers/zeus-bridge"
        let legacy = "/Users/tony/Library/Application Support/Zeus/bin/zeus-bridge"
        try writeHosts(root, zeusPath: legacy)
        try NativeHostRegistration.reconcile(decision: .refuse(BundledHelperLaunchPolicy.refusalSentence),
                                              checkedPath: bundled, hostsDirectory: root)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(NativeHostRegistration.zeusHostFileName).path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("com.other.host.json").path))
    }

    @Test func aRefusalLeavesARegistrationThatNamesNeitherPath() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = "/Applications/Zeus.app/Contents/Helpers/zeus-bridge"
        try writeHosts(root, zeusPath: "/usr/local/libexec/zeus-bridge")
        let zeusFile = root.appendingPathComponent(NativeHostRegistration.zeusHostFileName)
        let before = try Data(contentsOf: zeusFile)
        try NativeHostRegistration.reconcile(decision: .refuse(BundledHelperLaunchPolicy.refusalSentence),
                                              checkedPath: bundled, hostsDirectory: root)
        #expect(try Data(contentsOf: zeusFile) == before)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("com.other.host.json").path))
    }

    @Test func aValidSignatureKeepsTheHostRegistration() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = "/Applications/Zeus.app/Contents/Helpers/zeus-bridge"
        try writeHosts(root, zeusPath: bundled)
        let zeusFile = root.appendingPathComponent(NativeHostRegistration.zeusHostFileName)
        let before = try Data(contentsOf: zeusFile)
        try NativeHostRegistration.reconcile(decision: .launch, checkedPath: bundled, hostsDirectory: root)
        #expect(try Data(contentsOf: zeusFile) == before)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("com.other.host.json").path))
    }
}
