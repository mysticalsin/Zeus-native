import Foundation
import Testing
@testable import ZeusCore

@Suite("Todo voice box")
struct TodoVoiceBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(TodoVoiceBox.blankScalars.contains(" "))
        #expect(TodoVoiceBox.blankScalars.contains("\t"))
        #expect(TodoVoiceBox.blankScalars.contains("\n"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{000B}"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{000C}"))
        #expect(TodoVoiceBox.blankScalars.contains("\r"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{0085}"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{00A0}"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{1680}"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{2000}"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{200A}"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{2028}"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{2029}"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{202F}"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{205F}"))
        #expect(TodoVoiceBox.blankScalars.contains("\u{3000}"))
        #expect(!TodoVoiceBox.blankScalars.contains("\u{200B}"))
        #expect(TodoVoiceBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(TodoVoiceBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(TodoVoiceBox.trimmed(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aLeadingZeroWidthSpaceIsNotACommand() {
        #expect(TodoVoiceBox.parse("\u{200B}add these to-dos: call Ana") == nil)
        #expect(TodoVoice.parse("\u{200B}add these to-dos: call Ana") == nil)
        #expect(TodoVoiceBox.parse("\u{200B}what do I have today?") == .today)
        #expect(TodoVoiceBox.trimmed("\u{200B}add these to-dos: call Ana", also: [".", "!", "?"]) == "\u{200B}add these to-dos: call Ana")
        #expect(TodoVoiceBox.parse("  add these to-dos: call Ana  ") == .add(["call Ana"]))
        #expect(TodoVoice.parse("\u{00A0}what do I have today?\u{00A0}") == .today)
        #expect(TodoVoice.parse("\u{3000}give me my daily brief\u{3000}") == .brief)
    }

    @Test func aZeroWidthSpaceStaysOnTheItem() {
        #expect(TodoVoiceBox.split("\u{200B}call Ana") == ["\u{200B}call Ana"])
        #expect(TodoVoiceBox.parse("add tasks: \u{200B}call Ana") == .add(["\u{200B}call Ana"]))
        #expect(TodoVoice.parse("add tasks: \u{200B}call Ana") == .add(["\u{200B}call Ana"]))
        #expect(TodoVoiceBox.parse("add tasks: \u{200B}x") == .add(["\u{200B}x"]))
        #expect(TodoVoiceBox.split("  \n\u{00A0} ") == [])
        #expect(TodoVoice.split("call Ana tomorrow, send the invoice Friday and book the dentist")
            == ["call Ana tomorrow", "send the invoice Friday", "book the dentist"])
    }

    @Test func spokenPhrasesStillSelectTheCommand() {
        #expect(TodoVoice.parse("Add these to-dos: call Ana tomorrow, send the invoice Friday and book the dentist")
            == .add(["call Ana tomorrow", "send the invoice Friday", "book the dentist"]))
        #expect(TodoVoice.parse("remind me to water the plants") == .add(["water the plants"]))
        #expect(TodoVoice.parse("ajoute ces tâches : appeler Marie et payer le loyer") == .add(["appeler Marie", "payer le loyer"]))
        #expect(TodoVoice.parse("adiciona comprar pão e ligar para o João") == .add(["comprar pão", "ligar para o João"]))
        #expect(TodoVoice.parse("what do I have today?") == .today)
        #expect(TodoVoice.parse("give me my daily brief") == .brief)
        #expect(TodoVoice.parse("open Safari") == nil)
        #expect(TodoVoice.parse("todoist is great") == nil)
        #expect(TodoVoice.parse("add to-do to call Anna") == .add(["call Anna"]))
        #expect(TodoVoice.stripLeadingTo("to call Anna") == "call Anna")
        #expect(TodoVoiceBox.stripLeadingTo("  to call Anna  ") == "call Anna")
        #expect(TodoVoice.stripLeadingTo("\u{200B}to call Anna") == "\u{200B}to call Anna")
    }

    @Test func aStopMarkDropsAndAZeroWidthSpaceStaysOnTheRemainder() {
        #expect(TodoVoiceBox.parse("i finished the report.") == .complete("the report"))
        #expect(TodoVoice.parse("i finished the report\u{200B}") == .complete("the report\u{200B}"))
        #expect(TodoVoiceBox.parse("i did the dishes!") == .complete("the dishes"))
        #expect(TodoVoiceBox.trimmedRemainder(" the report\u{200B}.") == "the report\u{200B}")
        #expect(TodoVoiceBox.trimmedRemainder("  the report. ") == "the report")
        #expect(TodoVoiceBox.parse("   ") == nil)
        #expect(TodoVoice.parse("\u{200B}") == nil)
    }
}
