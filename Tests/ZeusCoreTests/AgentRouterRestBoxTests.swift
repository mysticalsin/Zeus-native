import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the rest trim after a matched lead in `AgentRouter.route`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
/// The transcript trim in `AgentRouter.route` still uses `CharacterSet.whitespacesAndNewlines`.
/// The note trim in `AgentMemory.remember` still uses `CharacterSet.whitespacesAndNewlines`.
@Suite("Agent router rest box")
struct AgentRouterRestBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(AgentRouterRestBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(AgentRouterRestBox.blankScalars.count == 5)
        #expect(AgentRouterRestBox.blankScalars.contains(" "))
        #expect(AgentRouterRestBox.blankScalars.contains("\t"))
        #expect(AgentRouterRestBox.blankScalars.contains("\n"))
        #expect(AgentRouterRestBox.blankScalars.contains("\r"))
        #expect(AgentRouterRestBox.blankScalars.contains("\u{00A0}"))
        #expect(!AgentRouterRestBox.blankScalars.contains("\u{200B}"))
        #expect(!AgentRouterRestBox.blankScalars.contains("\u{000B}"))
        #expect(!AgentRouterRestBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedRest() {
        #expect(AgentRouterRestBox.trimmedRest("\u{200B}") == "\u{200B}")
        #expect(AgentRouterRestBox.trimmedRest(" \u{200B} ") == "\u{200B}")
        #expect(AgentRouterRestBox.trimmedRest("\t\u{200B}\n") == "\u{200B}")
        #expect(AgentRouterRestBox.trimmedRest("\u{200B}look") == "\u{200B}look")
        #expect(AgentRouterRestBox.trimmedRest("look\u{200B}") == "look\u{200B}")
        #expect(AgentRouterRestBox.trimmedRest(" \t\n\r\u{00A0}") == "")
        #expect(AgentRouterRestBox.trimmedRest("") == "")
        #expect(AgentRouterRestBox.trimmedRest("\u{000B}look") == "\u{000B}look")
        #expect(AgentRouterRestBox.trimmedRest("\u{3000}look") == "\u{3000}look")
        #expect(AgentRouterRestBox.trimmedRest(" \tlook\r\n") == "look")
        #expect(AgentRouterRestBox.trimmedRest("\u{00A0}look\u{00A0}") == "look")
        #expect(AgentRouterRestBox.trimmedRest("look") == "look")
        #expect(AgentRouterRestBox.trimmedRest("a\u{200B}b") == "a\u{200B}b")
        #expect(AgentRouterRestBox.trimmedRest("\nlook") == "look")
        #expect(AgentRouterRestBox.trimmedRest("\rlook") == "look")
    }

    @Test func aZeroWidthSpaceStaysOnARoutedRest() {
        let agents = AgentProfile.builtIn
        #expect(AgentRouter.route("ask Scout to \u{200B}look", agents: agents)?.agent.name == "Scout")
        #expect(AgentRouter.route("ask Scout to \u{200B}look", agents: agents)?.request == "\u{200B}look")
        #expect(AgentRouter.route("ask Scout to look\u{200B}x", agents: agents)?.request == "look\u{200B}x")
        #expect(AgentRouter.route("ask Scout to  \u{200B}look", agents: agents)?.request == "\u{200B}look")
        #expect(AgentRouter.route("ask Scout to \u{3000}look", agents: agents)?.request == "\u{3000}look")
        #expect(AgentRouter.route("ask Scout to \u{000B}look", agents: agents)?.request == "\u{000B}look")
        #expect(AgentRouter.route("ask Scout to \nlook", agents: agents)?.request == "look")
        #expect(AgentRouter.route("ask Scout to \rlook", agents: agents)?.request == "look")
        #expect(AgentRouter.route("ask Scout to \u{00A0}look", agents: agents)?.request == "look")
        #expect(AgentRouter.route("  ask Scout to look  ", agents: agents)?.agent.name == "Scout")
        #expect(AgentRouter.route("  ask Scout to look  ", agents: agents)?.request == "look")
        #expect(AgentRouter.route("Scribe, \u{200B}remember that Tony", agents: agents)?.request == "\u{200B}remember that Tony")
        #expect(AgentRouter.route("Scribe, \u{200B}remember that Tony", agents: agents)?.remember == nil)
        let remembered = AgentRouter.route("  Scribe, remember that I sign emails as Tony  ", agents: agents)
        #expect(remembered?.agent.name == "Scribe")
        #expect(remembered?.remember == "I sign emails as Tony")
        #expect(remembered?.request == "remember that I sign emails as Tony")
    }
}
