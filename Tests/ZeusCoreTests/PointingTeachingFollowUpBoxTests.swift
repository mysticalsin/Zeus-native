import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing teaching follow-up box")
struct PointingTeachingFollowUpBoxTests {
    private func scene() -> PointingTeachingFollowUp.Scene {
        .init(partIDs: ["battery", "motor", "inverter", "shell"], motorX: -1.4, motorY: 0.33, motorZ: -0.3)
    }

    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{0009}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{000A}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{000B}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{000C}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{000D}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{0020}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{0085}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{00A0}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{1680}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2000}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2001}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2002}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2003}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2004}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2005}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2006}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2007}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2008}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2009}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{200A}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2028}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{2029}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{202F}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{205F}"))
        #expect(PointingTeachingFollowUpBox.blankScalars.contains("\u{3000}"))
        #expect(!PointingTeachingFollowUpBox.blankScalars.contains("\u{200B}"))
        #expect(PointingTeachingFollowUpBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(PointingTeachingFollowUpBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(PointingTeachingFollowUpBox.trimmed(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aZeroWidthSpaceStaysInThePhrase() {
        #expect(PointingTeachingFollowUpBox.phrase("\u{200B}") == "\u{200B}")
        #expect(PointingTeachingFollowUpBox.phrase(" \u{200B} ") == "\u{200B}")
        #expect(PointingTeachingFollowUpBox.phrase("\u{200B}.") == "\u{200B}")
        #expect(PointingTeachingFollowUpBox.phrase(" \t\n") == "")
        #expect(PointingTeachingFollowUpBox.phrase("\u{00A0}\u{3000}") == "")
    }

    @Test func aZeroWidthSpaceBeforeThePeriodStaysInTheCommand() {
        #expect(PointingTeachingFollowUpBox.phrase("show the motor\u{200B}.") == "show the motor\u{200B}")
        #expect(PointingTeachingFollowUpBox.phrase("SHOW THE MOTOR\u{200B}!") == "show the motor\u{200B}")
        #expect(PointingTeachingFollowUp.decide(utterance: "show the motor\u{200B}.", scene: scene()) == .refused(.phrase))
        let kept = PointingTeachingFollowUp.decide(utterance: "show the motor.", scene: scene())
        if case .ready(let plan) = kept {
            #expect(plan.kind == .showMotor)
        } else {
            #expect(Bool(false))
        }
    }

    @Test func aZeroWidthSpaceBesideTheWordsStays() {
        #expect(PointingTeachingFollowUpBox.trimmed("show\u{200B}") == "show\u{200B}")
        #expect(PointingTeachingFollowUpBox.trimmed("\u{200B}show") == "\u{200B}show")
        #expect(PointingTeachingFollowUpBox.phrase("show\u{200B}the motor.") == "show\u{200B}the motor")
        #expect(PointingTeachingFollowUp.decide(utterance: "\u{200B}show the motor", scene: scene()) == .refused(.phrase))
    }

    @Test func namedBlanksStillFoldTheTeachingPhrases() {
        #expect(PointingTeachingFollowUpBox.phrase("  SHOW   THE  MOTOR  ") == "show the motor")
        #expect(PointingTeachingFollowUpBox.phrase("show\nthe motor") == "show the motor")
        #expect(PointingTeachingFollowUpBox.phrase("Please show the motor.") == "please show the motor")
        #expect(PointingTeachingFollowUpBox.phrase("show\u{00A0}the\u{3000}motor") == "show the motor")
        #expect(PointingTeachingFollowUpBox.phrase("rotate it!") == "rotate it")
        #expect(PointingTeachingFollowUpBox.trimmed("\u{00A0}\u{200B}\u{3000}") == "\u{200B}")
        let shown = PointingTeachingFollowUp.decide(utterance: "show\nthe motor", scene: scene())
        if case .ready(let plan) = shown {
            #expect(plan.kind == .showMotor)
        } else {
            #expect(Bool(false))
        }
        #expect(PointingTeachingFollowUp.decide(utterance: "Please show the motor.", scene: scene()) == shown)
    }
}
