import Foundation
import Testing
@testable import ZeusCore

/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so these tests name the scalars.
@Suite("Meeting speaker label box")
struct MeetingSpeakerLabelsBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains(" "))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\t"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\n"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{000B}"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{000C}"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\r"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{0085}"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{00A0}"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{1680}"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{2000}"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{200A}"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{2028}"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{2029}"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{202F}"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{205F}"))
        #expect(MeetingSpeakerLabelsBox.blankScalars.contains("\u{3000}"))
        #expect(!MeetingSpeakerLabelsBox.blankScalars.contains("\u{200B}"))
        #expect(!MeetingSpeakerLabelsBox.edgePunctuation.contains("\u{200B}"))
        #expect(MeetingSpeakerLabelsBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(MeetingSpeakerLabelsBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(MeetingSpeakerLabelsBox.trimmed(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func edgesDropNamedBlanksAndPunctuationButKeepAZeroWidthSpace() {
        #expect(MeetingSpeakerLabelsBox.trimmed(",;:-|()[]\u{2013}\u{2014}\u{2022}\u{00B7}Marie") == "Marie")
        #expect(MeetingSpeakerLabelsBox.trimmed("Marie,;:-|()[]") == "Marie")
        #expect(MeetingSpeakerLabelsBox.trimmed("  Marie  ") == "Marie")
        #expect(MeetingSpeakerLabelsBox.trimmed("\u{00A0}Marie\u{3000}") == "Marie")
        #expect(MeetingSpeakerLabelsBox.trimmed("Marie-Claire") == "Marie-Claire")
        #expect(MeetingSpeakerLabelsBox.trimmed(" \u{200B}Marie ") == "\u{200B}Marie")
        #expect(MeetingSpeakerLabelsBox.trimmed("Marie\u{200B}") == "Marie\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysInTheName() {
        #expect(MeetingSpeakerLabelParser.clean("\u{200B}Marie") == "\u{200B}Marie")
        #expect(MeetingSpeakerLabelParser.clean(" \u{200B}Marie ") == "\u{200B}Marie")
        #expect(MeetingSpeakerLabelParser.clean("Marie\u{200B}") == "Marie\u{200B}")
        #expect(MeetingSpeakerLabelParser.parse("\u{200B}Marie")?.name == "\u{200B}Marie")
        #expect(MeetingSpeakerLabelParser.parse("\u{200B}Marie is speaking")?.name == "\u{200B}Marie")
        #expect(MeetingSpeakerLabelParser.parse("\u{200B}Marie is speaking")?.isSpeaking == true)
    }

    @Test func aNameOfOnlyNamedBlanksIsMissing() {
        #expect(MeetingSpeakerLabelParser.clean("\u{00A0}\u{3000}") == nil)
        #expect(MeetingSpeakerLabelParser.clean(" \t\n") == nil)
        #expect(MeetingSpeakerLabelParser.clean(",;:-") == nil)
        #expect(MeetingSpeakerLabelParser.clean("\u{200B}") == nil)
        #expect(MeetingSpeakerLabelParser.clean("Mute") == nil)
        #expect(MeetingSpeakerLabelParser.clean("Participants") == nil)
        #expect(MeetingSpeakerLabelParser.clean("12345") == nil)
        #expect(MeetingSpeakerLabelParser.parse("   ") == nil)
    }

    @Test func theParserReadsEachTrimFromTheBox() {
        #expect(MeetingSpeakerLabelParser.clean(" Marie ") == "Marie")
        #expect(MeetingSpeakerLabelParser.clean("Marie   Dubois") == "Marie Dubois")
        #expect(MeetingSpeakerLabelParser.clean("Marie Dubois (Guest)") == "Marie Dubois")
        #expect(MeetingSpeakerLabelParser.clean("\u{00A0}Marie\u{00A0}") == "Marie")
        #expect(MeetingSpeakerLabelParser.clean(", Marie ,") == "Marie")
        #expect(MeetingSpeakerLabelParser.parse("Paul, muted")?.name == "Paul")
        #expect(MeetingSpeakerLabelParser.parse("Paul, muted")?.isMuted == true)
        #expect(MeetingSpeakerLabelParser.clean("\u{200B}Marie") == MeetingSpeakerLabelsBox.trimmed("\u{200B}Marie"))
    }
}
