import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the transcript trim in `AgentRouter.route`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
/// The rest trim after a matched lead still uses `CharacterSet.whitespaces`.
@Suite("Agent router transcript box")
struct AgentRouterTranscriptBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(AgentRouterTranscriptBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(AgentRouterTranscriptBox.blankScalars.count == 5)
        #expect(AgentRouterTranscriptBox.blankScalars.contains(" "))
        #expect(AgentRouterTranscriptBox.blankScalars.contains("\t"))
        #expect(AgentRouterTranscriptBox.blankScalars.contains("\n"))
        #expect(AgentRouterTranscriptBox.blankScalars.contains("\r"))
        #expect(AgentRouterTranscriptBox.blankScalars.contains("\u{00A0}"))
        #expect(!AgentRouterTranscriptBox.blankScalars.contains("\u{200B}"))
        #expect(!AgentRouterTranscriptBox.blankScalars.contains("\u{000B}"))
        #expect(!AgentRouterTranscriptBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedTranscript() {
        #expect(AgentRouterTranscriptBox.trimmedTranscript("\u{200B}") == "\u{200B}")
        #expect(AgentRouterTranscriptBox.trimmedTranscript(" \u{200B} ") == "\u{200B}")
        #expect(AgentRouterTranscriptBox.trimmedTranscript("\t\u{200B}\n") == "\u{200B}")
        #expect(AgentRouterTranscriptBox.trimmedTranscript("\u{200B}ask") == "\u{200B}ask")
        #expect(AgentRouterTranscriptBox.trimmedTranscript("ask\u{200B}") == "ask\u{200B}")
        #expect(AgentRouterTranscriptBox.trimmedTranscript(" \t\n\r\u{00A0}") == "")
        #expect(AgentRouterTranscriptBox.trimmedTranscript("") == "")
        #expect(AgentRouterTranscriptBox.trimmedTranscript("\u{000B}ask") == "\u{000B}ask")
        #expect(AgentRouterTranscriptBox.trimmedTranscript("\u{3000}ask") == "\u{3000}ask")
        #expect(AgentRouterTranscriptBox.trimmedTranscript(" \task\r\n") == "ask")
        #expect(AgentRouterTranscriptBox.trimmedTranscript("\u{00A0}ask\u{00A0}") == "ask")
        #expect(AgentRouterTranscriptBox.trimmedTranscript("ask") == "ask")
        #expect(AgentRouterTranscriptBox.trimmedTranscript("a\u{200B}b") == "a\u{200B}b")
        #expect(AgentRouterTranscriptBox.trimmedTranscript("\nask") == "ask")
        #expect(AgentRouterTranscriptBox.trimmedTranscript("\rask") == "ask")
    }

    @Test func aZeroWidthSpaceStaysOnARoutedTranscript() {
        let agents = AgentProfile.builtIn
        #expect(AgentRouter.route(" \u{200B}ask Scout to look", agents: agents) == nil)
        #expect(AgentRouter.route("\u{200B}ask Scout to look", agents: agents) == nil)
        #expect(AgentRouter.route("\u{000B}ask Scout to look", agents: agents) == nil)
        #expect(AgentRouter.route("\u{3000}ask Scout to look", agents: agents) == nil)
        #expect(AgentRouter.route("ask Scout\u{200B} to look", agents: agents) == nil)
        #expect(AgentRouter.route("\nask Scout to look\r", agents: agents)?.agent.name == "Scout")
        #expect(AgentRouter.route("\nask Scout to look\r", agents: agents)?.request == "look")
        #expect(AgentRouter.route("\u{00A0}ask Scout to look\u{00A0}", agents: agents)?.request == "look")
        #expect(AgentRouter.route(" \t\n\r\u{00A0}", agents: agents) == nil)
        #expect(AgentRouter.route("  ask Scout to look  ", agents: agents)?.agent.name == "Scout")
        #expect(AgentRouter.route("  ask Scout to look  ", agents: agents)?.request == "look")
        #expect(AgentRouter.route("ask Scout to look\u{000B}", agents: agents)?.request == "look\u{000B}")
        #expect(AgentRouter.route("ask Scout to \u{200B}look", agents: agents)?.request == "look")
        #expect(AgentRouter.route("ask Scout to \u{3000}look", agents: agents)?.request == "look")
        #expect(AgentRouter.route("ask Scout to \u{000B}look", agents: agents)?.request == "\u{000B}look")
        let remembered = AgentRouter.route("  Scribe, remember that I sign emails as Tony  ", agents: agents)
        #expect(remembered?.agent.name == "Scribe")
        #expect(remembered?.remember == "I sign emails as Tony")
        #expect(remembered?.request == "remember that I sign emails as Tony")
    }
}
