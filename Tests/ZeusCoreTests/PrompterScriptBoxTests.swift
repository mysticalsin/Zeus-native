import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a prompter script line. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Prompter script box")
struct PrompterScriptBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PrompterScriptBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PrompterScriptBox.blankScalars.count == 5)
        #expect(PrompterScriptBox.blankScalars.contains(" "))
        #expect(PrompterScriptBox.blankScalars.contains("\t"))
        #expect(PrompterScriptBox.blankScalars.contains("\n"))
        #expect(PrompterScriptBox.blankScalars.contains("\r"))
        #expect(PrompterScriptBox.blankScalars.contains("\u{00A0}"))
        #expect(!PrompterScriptBox.blankScalars.contains("\u{200B}"))
        #expect(!PrompterScriptBox.blankScalars.contains("\u{000B}"))
        #expect(!PrompterScriptBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedText() {
        #expect(PrompterScriptBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(PrompterScriptBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(PrompterScriptBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(PrompterScriptBox.trimmedText("\u{200B}Hello") == "\u{200B}Hello")
        #expect(PrompterScriptBox.trimmedText("Hello\u{200B}") == "Hello\u{200B}")
        #expect(PrompterScriptBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(PrompterScriptBox.trimmedText("") == "")
        #expect(PrompterScriptBox.trimmedText("\u{000B}Hello") == "\u{000B}Hello")
        #expect(PrompterScriptBox.trimmedText("\u{3000}Hello") == "\u{3000}Hello")
        #expect(PrompterScriptBox.trimmedText(" \tHello\r\n") == "Hello")
        #expect(PrompterScriptBox.trimmedText("\u{00A0}Hello\u{00A0}") == "Hello")
        #expect(PrompterScriptBox.trimmedText("Hello\u{00A0}there") == "Hello\u{00A0}there")
    }

    @Test func aZeroWidthSpaceStaysInTheImportedScript() {
        let zwsp = "\u{200B}"
        #expect(PrompterFollowBox.inline(zwsp) == zwsp)
        #expect(PrompterFollowBox.inline(" \(zwsp) ") == zwsp)
        #expect(PrompterFollowBox.inline("\t\(zwsp)\n") == zwsp)
        #expect(PrompterFollowBox.inline("\(zwsp)Hello") == "\(zwsp)Hello")
        #expect(PrompterFollowBox.inline("Hello\(zwsp)") == "Hello\(zwsp)")
        #expect(PrompterFollowBox.inline(" \t\n\r\u{00A0}") == "")
        #expect(PrompterFollowBox.inline("\u{000B}Hello") == "\u{000B}Hello")
        #expect(PrompterFollowBox.inline("\u{3000}Hello") == "\u{3000}Hello")
        #expect(PrompterFollowBox.inline(" \tHello\r\n") == "Hello")
        #expect(PrompterFollowBox.inline("\u{00A0}Hello\u{00A0}") == "Hello")
        #expect(PrompterFollowBox.inline("Hello\u{00A0}there") == "Hello\u{00A0}there")
        #expect(PrompterFollowBox.importScript(from: zwsp, isMarkdown: true) == zwsp)
        #expect(PrompterFollowBox.importScript(from: " \(zwsp) ", isMarkdown: true) == zwsp)
        #expect(PrompterFollowBox.importScript(from: "#\(zwsp)", isMarkdown: true) == "# \(zwsp)")
        #expect(PrompterFollowBox.importScript(from: "#\(zwsp)Intro", isMarkdown: true) == "# \(zwsp)Intro")
        #expect(PrompterFollowBox.importScript(from: " \t\n\r\u{00A0}", isMarkdown: true) == "")
        #expect(PrompterFollowBox.importScript(from: "#\u{00A0}Intro\u{00A0}", isMarkdown: true) == "# Intro")
        #expect(PrompterFollowBox.importScript(from: "\u{00A0}Hello\u{00A0}", isMarkdown: true) == "Hello")
        #expect(PrompterFollowBox.importScript(from: "\u{3000}Hello", isMarkdown: true) == "\u{3000}Hello")
        #expect(PrompterFollowBox.importScript(from: "\u{000B}Hello", isMarkdown: true) == "\u{000B}Hello")
        #expect(PrompterFollowBox.importScript(from: " \tHello\r\n", isMarkdown: true) == "Hello")
        #expect(PrompterFollowBox.importScript(from: "> \(zwsp)", isMarkdown: true) == zwsp)
        #expect(PrompterImport.script(from: zwsp, isMarkdown: true) == zwsp)
    }
}
