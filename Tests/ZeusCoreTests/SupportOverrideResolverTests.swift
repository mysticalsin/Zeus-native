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
}
