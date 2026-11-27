import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in an agent avatar name. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Bot avatar box")
struct BotAvatarSpecBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(BotAvatarSpecBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(BotAvatarSpecBox.blankScalars.count == 5)
        #expect(BotAvatarSpecBox.blankScalars.contains(" "))
        #expect(BotAvatarSpecBox.blankScalars.contains("\t"))
        #expect(BotAvatarSpecBox.blankScalars.contains("\n"))
        #expect(BotAvatarSpecBox.blankScalars.contains("\r"))
        #expect(BotAvatarSpecBox.blankScalars.contains("\u{00A0}"))
        #expect(!BotAvatarSpecBox.blankScalars.contains("\u{200B}"))
        #expect(!BotAvatarSpecBox.blankScalars.contains("\u{000B}"))
        #expect(!BotAvatarSpecBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInATrimmedName() {
        #expect(BotAvatarSpecBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(BotAvatarSpecBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(BotAvatarSpecBox.trimmed("\t\u{200B}\n") == "\u{200B}")
        #expect(BotAvatarSpecBox.trimmed("\u{200B}Claude") == "\u{200B}Claude")
        #expect(BotAvatarSpecBox.trimmed("Claude\u{200B}") == "Claude\u{200B}")
        #expect(BotAvatarSpecBox.trimmed(" \t\n\r\u{00A0}") == "")
        #expect(BotAvatarSpecBox.trimmed("") == "")
        #expect(BotAvatarSpecBox.trimmed("\u{000B}Claude") == "\u{000B}Claude")
        #expect(BotAvatarSpecBox.trimmed("\u{3000}Claude") == "\u{3000}Claude")
        #expect(BotAvatarSpecBox.trimmed(" \tClaude\r\n") == "Claude")
        #expect(BotAvatarSpecBox.trimmed("\u{00A0}Claude\u{00A0}") == "Claude")
        #expect(BotAvatarSpecBox.trimmed("too\u{00A0}many") == "too\u{00A0}many")
    }

    @Test func aZeroWidthSpaceStaysInTheAgentShapeAndTheLabel() {
        #expect(BotAvatarSpec.hash("\u{200B}") != BotAvatarSpec.hash(""))
        #expect(BotAvatarSpec.hash("\u{200B}claude") != BotAvatarSpec.hash("claude"))
        #expect(BotAvatarSpec.hash("claude\u{200B}") != BotAvatarSpec.hash("claude"))
        #expect(BotAvatarSpec.hash("\u{000B}claude") != BotAvatarSpec.hash("claude"))
        #expect(BotAvatarSpec.hash("\u{3000}claude") != BotAvatarSpec.hash("claude"))
        #expect(BotAvatarSpec.hash("  claude ") == BotAvatarSpec.hash("claude"))
        #expect(BotAvatarSpec.hash("\u{00A0}Claude\u{00A0}") == BotAvatarSpec.hash("claude"))
        #expect(BotAvatarSpec.hash(" \t\n\r\u{00A0}") == BotAvatarSpec.hash(""))
        #expect(BotAvatarSpec.type(forAgent: "\u{00A0}Claude\u{00A0}") == BotAvatarSpec.type(forAgent: "Claude"))
        #expect(BotAvatarSpec.seed(forAgent: "\u{200B}") >= 0)
        #expect(BotAvatarSpec.seed(forAgent: "\u{200B}") < 1)
        #expect(BotAvatarSpec.accessibilityLabel(agent: "\u{200B}", state: .default) == "\u{200B} avatar, idle")
        #expect(BotAvatarSpec.accessibilityLabel(agent: " \u{200B} ", state: .working) == "\u{200B} avatar, working")
        #expect(BotAvatarSpec.accessibilityLabel(agent: "\u{000B}Ada", state: .default) == "\u{000B}Ada avatar, idle")
        #expect(BotAvatarSpec.accessibilityLabel(agent: "\u{3000}Ada", state: .sleeping) == "\u{3000}Ada avatar, sleeping")
        #expect(BotAvatarSpec.accessibilityLabel(agent: " \t\n\r\u{00A0}", state: .default) == "Agent avatar, idle")
        #expect(BotAvatarSpec.accessibilityLabel(agent: "\u{00A0}Ada\u{00A0}", state: .working) == "Ada avatar, working")
        #expect(BotAvatarSpec.accessibilityLabel(agent: nil, state: .default) == "Agent avatar, idle")
        #expect(BotAvatarSpec.accessibilityLabel(agent: "  Ada  ", state: .default) == "Ada avatar, idle")
    }
}
