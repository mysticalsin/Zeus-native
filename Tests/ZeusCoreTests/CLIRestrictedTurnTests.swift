import Foundation
import Testing
@testable import ZeusCore

@Suite("Command-line turns stay on this Mac when control is off")
struct CLIRestrictedTurnTests {
    @Test func askAndResearchNeedThePrivacySwitch() {
        #expect(CLIGate.isSensitive(op: .ask, debugSubcommand: "", argument: ""))
        #expect(CLIGate.isSensitive(op: .research, debugSubcommand: "", argument: ""))
    }

    @Test func aRestrictedTurnDoesNotCallAProviderOrAttachMemory() {
        #expect(!RestrictedTurn.mayUseProvider(restricted: true))
        #expect(RestrictedTurn.mayUseProvider(restricted: false))
        #expect(RestrictedTurn.memory("remembered fact", restricted: true) == "")
        #expect(RestrictedTurn.memory("remembered fact", restricted: false) == "remembered fact")
        #expect(RestrictedTurn.history(["earlier"], restricted: true).isEmpty)
        #expect(RestrictedTurn.history(["earlier"], restricted: false) == ["earlier"])
    }
}
