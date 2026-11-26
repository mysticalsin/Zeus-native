import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing failure recovery box")
struct PointingFailureRecoveryBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{0009}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{000A}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{000B}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{000C}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{000D}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{0020}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{0085}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{00A0}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{1680}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2000}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2001}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2002}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2003}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2004}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2005}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2006}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2007}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2008}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2009}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{200A}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2028}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{2029}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{202F}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{205F}"))
        #expect(PointingFailureRecoveryBox.blankScalars.contains("\u{3000}"))
        #expect(!PointingFailureRecoveryBox.blankScalars.contains("\u{200B}"))
        #expect(PointingFailureRecoveryBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(PointingFailureRecoveryBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(PointingFailureRecoveryBox.trimmed(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aZeroWidthSpaceStaysInAName() {
        #expect(PointingFailureRecoveryBox.kept("\u{200B}") == "\u{200B}")
        #expect(PointingFailureRecoveryBox.kept(" \u{200B} ") == "\u{200B}")
        #expect(PointingFailureRecoveryBox.kept("\u{200B}Any LLM") == "\u{200B}Any LLM")
        #expect(PointingFailureRecoveryBox.kept("Any LLM\u{200B}") == "Any LLM\u{200B}")
        #expect(PointingFailureRecoveryBox.kept("  Any LLM  ") == "Any LLM")
        #expect(PointingFailureRecoveryBox.kept(" \t\n") == nil)
        #expect(PointingFailureRecoveryBox.kept("\u{00A0}\u{3000}") == nil)
        #expect(PointingFailureRecoveryBox.kept("") == nil)
    }

    @Test func aZeroWidthProviderIsARealName() {
        var network = PointingFailureRecovery()
        let lost = network.networkLost(provider: "\u{200B}")
        #expect(lost.outcome == .accepted)
        #expect(lost.order == .none)
        #expect(lost.notice == .network(PointingFailureRecovery.networkNotice(provider: "\u{200B}")))
        #expect(network.phase == .failed(.network))

        var blank = PointingFailureRecovery()
        #expect(blank.networkLost(provider: " \t\n").outcome == .rejectedEmpty)
        #expect(blank.phase == .idle)

        var model = PointingFailureRecovery()
        let unavailable = model.modelUnavailable(provider: " \u{200B} ")
        #expect(unavailable.outcome == .accepted)
        #expect(unavailable.notice == .modelUnavailable(PointingFailureRecovery.modelNotice(provider: "\u{200B}")))
        #expect(model.phase == .failed(.modelUnavailable))
    }

    @Test func aZeroWidthSceneIdIsStored() {
        var recovery = PointingFailureRecovery()
        let committed = recovery.commit(.init(id: "\u{200B}", generation: 1, objectIDs: ["\u{200B}"]))
        #expect(committed.outcome == .accepted)
        #expect(recovery.committedScene?.id == "\u{200B}")
        #expect(recovery.committedScene?.objectIDs == ["\u{200B}"])
        let partial = recovery.stagePartial(objectIDs: ["motor", "\u{200B}"])
        #expect(partial.outcome == .accepted)
        #expect(recovery.partialObjectIDs == ["motor", "\u{200B}"])

        var spaces = PointingFailureRecovery()
        #expect(spaces.commit(.init(id: "  ", generation: 1, objectIDs: ["battery"])).outcome == .rejectedEmpty)
        #expect(spaces.committedScene == nil)
        #expect(spaces.commit(.init(id: "scene-1", generation: 1, objectIDs: ["battery", " "])).outcome == .rejectedEmpty)
    }

    @Test func namedBlanksAroundAnIdAreRemoved() {
        #expect(PointingFailureRecoveryBox.kept("\u{00A0}beat-1\u{3000}") == "beat-1")
        #expect(PointingFailureRecoveryBox.kept("\u{200B}beat-1") == "\u{200B}beat-1")
        #expect(PointingFailureRecoveryBox.kept("\tbeat-1\n") == "beat-1")

        var recovery = PointingFailureRecovery()
        let began = recovery.beginBeat(.init(id: "\u{00A0}beat-1\u{3000}", index: 0), deviceID: "\tspeaker-a\n")
        #expect(began.outcome == .accepted)
        #expect(recovery.phase == .playing(beat: .init(id: "beat-1", index: 0), deviceID: "speaker-a", elapsed: 0))
        #expect(recovery.deviceID == "speaker-a")
        #expect(recovery.outputDeviceChanged(to: " speaker-a ").outcome == .rejectedSameDevice)
        let moved = recovery.outputDeviceChanged(to: "\u{200B}")
        #expect(moved.outcome == .accepted)
        #expect(moved.order == .rebuildAndResume(beat: .init(id: "beat-1", index: 0), deviceID: "\u{200B}", at: 0))
    }
}
