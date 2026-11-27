import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a debug audio path. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Debug audio path box")
struct DebugAudioPathBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(DebugAudioPathBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(DebugAudioPathBox.blankScalars.count == 5)
        #expect(DebugAudioPathBox.blankScalars.contains(" "))
        #expect(DebugAudioPathBox.blankScalars.contains("\t"))
        #expect(DebugAudioPathBox.blankScalars.contains("\n"))
        #expect(DebugAudioPathBox.blankScalars.contains("\r"))
        #expect(DebugAudioPathBox.blankScalars.contains("\u{00A0}"))
        #expect(!DebugAudioPathBox.blankScalars.contains("\u{200B}"))
        #expect(!DebugAudioPathBox.blankScalars.contains("\u{000B}"))
        #expect(!DebugAudioPathBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInAPath() {
        #expect(DebugAudioPathBox.trimmedPath("\u{200B}") == "\u{200B}")
        #expect(DebugAudioPathBox.trimmedPath(" \u{200B} ") == "\u{200B}")
        #expect(DebugAudioPathBox.trimmedPath("\t\u{200B}\n") == "\u{200B}")
        #expect(DebugAudioPathBox.trimmedPath("\u{200B}clip.wav") == "\u{200B}clip.wav")
        #expect(DebugAudioPathBox.trimmedPath("clip.wav\u{200B}") == "clip.wav\u{200B}")
        #expect(DebugAudioPathBox.trimmedPath(" \t\n\r\u{00A0}") == "")
        #expect(DebugAudioPathBox.trimmedPath("\u{000B}clip.wav") == "\u{000B}clip.wav")
        #expect(DebugAudioPathBox.trimmedPath("\u{3000}clip.wav") == "\u{3000}clip.wav")
        #expect(DebugAudioPathBox.trimmedPath(" \t/abs/x.wav\r\n") == "/abs/x.wav")
        #expect(DebugAudioPathBox.trimmedPath("\u{00A0}clip.wav\u{00A0}") == "clip.wav")
    }

    @Test func aZeroWidthSpaceDoesNotResolveAsAPlainClip() {
        #expect(DebugAudioPath.resolve("clip.wav", workingDirectory: "/tmp/qa") == "/tmp/qa/clip.wav")
        #expect(DebugAudioPath.resolve("/abs/x.wav") == "/abs/x.wav")
        #expect(DebugAudioPath.resolve(" \t/abs/x.wav\n") == "/abs/x.wav")
        #expect(DebugAudioPath.resolve("\u{00A0}clip.wav\u{00A0}", workingDirectory: "/tmp/qa") == "/tmp/qa/clip.wav")
        #expect(DebugAudioPath.resolve(" \t\n\r\u{00A0}") == "")
        let zwspClip = DebugAudioPath.resolve("\u{200B}clip.wav", workingDirectory: "/tmp/qa")
        #expect(zwspClip.contains("\u{200B}"))
        #expect(zwspClip != "/tmp/qa/clip.wav")
        let onlyZwsp = DebugAudioPath.resolve("\u{200B}", workingDirectory: "/tmp/qa")
        #expect(onlyZwsp.contains("\u{200B}"))
        #expect(onlyZwsp != "")
        let verticalTab = DebugAudioPath.resolve("\u{000B}clip.wav", workingDirectory: "/tmp/qa")
        #expect(verticalTab.contains("\u{000B}"))
        #expect(verticalTab != "/tmp/qa/clip.wav")
        let ideographic = DebugAudioPath.resolve("\u{3000}clip.wav", workingDirectory: "/tmp/qa")
        #expect(ideographic.contains("\u{3000}"))
        #expect(ideographic != "/tmp/qa/clip.wav")
        let hiddenAbsolute = DebugAudioPath.resolve("\u{200B}/abs/x.wav", workingDirectory: "/tmp/qa")
        #expect(hiddenAbsolute.contains("\u{200B}"))
        #expect(hiddenAbsolute != "/abs/x.wav")
    }
}
