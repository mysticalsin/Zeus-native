import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing failure recovery")
struct PointingFailureRecoveryTests {
    private func scene(_ id: String, generation: Int, objects: [String]) -> PointingFailureRecovery.Scene {
        PointingFailureRecovery.Scene(id: id, generation: generation, objectIDs: objects)
    }

    private func beat(_ id: String, index: Int = 0) -> PointingFailureRecovery.Beat {
        PointingFailureRecovery.Beat(id: id, index: index)
    }

    private func elapsed(_ recovery: PointingFailureRecovery) -> Double? {
        if case .playing(_, _, let elapsed) = recovery.phase { return elapsed }
        return nil
    }

    private func pending(_ recovery: PointingFailureRecovery) -> (PointingFailureRecovery.Beat, String)? {
        if case .awaitingRebuild(let beat, let device) = recovery.phase { return (beat, device) }
        return nil
    }

    @Test func theBeatStartsAtZero() {
        #expect(PointingFailureRecovery.beatStart == 0)
        #expect(PointingFailureRecovery.outputDeviceNotice == "Sound output changed. This sentence is starting again from the beginning.")
        #expect(PointingFailureRecovery.networkNotice(provider: "Any LLM") == "No connection to Any LLM. Check your network and try again.")
        #expect(PointingFailureRecovery.modelNotice(provider: "Any LLM") == "Any LLM does not offer the selected model. Pick another model in Settings.")
    }

    @Test func aDeviceChangeResumesFromTheBeatStart() {
        var recovery = PointingFailureRecovery()
        let committed = scene("scene-1", generation: 4, objects: ["battery", "inverter"])
        #expect(recovery.commit(committed).outcome == .accepted)
        #expect(recovery.stagePartial(objectIDs: ["motor"]).outcome == .accepted)
        let current = beat("beat-3", index: 2)
        #expect(recovery.beginBeat(current, deviceID: "speaker-a").outcome == .accepted)
        #expect(recovery.tick(elapsed: 1.25).outcome == .accepted)
        let changed = recovery.outputDeviceChanged(to: "speaker-b")
        #expect(changed.outcome == .accepted)
        #expect(changed.order == .rebuildAndResume(beat: current, deviceID: "speaker-b", at: PointingFailureRecovery.beatStart))
        #expect(changed.notice == .outputDeviceChanged("Sound output changed. This sentence is starting again from the beginning."))
        #expect(changed.committedScene == committed)
        #expect(changed.partialObjectIDs == ["motor"])
        #expect(recovery.committedScene == committed)
        #expect(recovery.partialObjectIDs == ["motor"])
        if case .rebuildAndResume(_, _, let at) = changed.order {
            #expect(at == 0)
            #expect(at != 1.25)
        } else {
            #expect(Bool(false))
        }
        #expect(pending(recovery)?.0 == current)
        #expect(pending(recovery)?.1 == "speaker-b")
        let rebuilt = recovery.playerRebuilt()
        #expect(rebuilt.outcome == .accepted)
        #expect(rebuilt.order == .none)
        #expect(elapsed(recovery) == 0.0)
        if case .playing(let playing, let device, let position) = recovery.phase {
            #expect(playing == current)
            #expect(device == "speaker-b")
            #expect(position == 0)
        } else {
            #expect(Bool(false))
        }
        #expect(recovery.committedScene == committed)
        #expect(recovery.partialObjectIDs == ["motor"])
    }

    @Test func ticksDuringRebuildDoNotAdvanceASilentClock() {
        var recovery = PointingFailureRecovery()
        let current = beat("beat-1")
        #expect(recovery.beginBeat(current, deviceID: "speaker-a").outcome == .accepted)
        #expect(recovery.tick(elapsed: 1).outcome == .accepted)
        #expect(recovery.outputDeviceChanged(to: "speaker-b").outcome == .accepted)
        let ignored = recovery.tick(elapsed: 9)
        #expect(ignored.outcome == .ignored)
        #expect(ignored.order == .none)
        #expect(pending(recovery)?.0 == current)
        #expect(pending(recovery)?.1 == "speaker-b")
        #expect(recovery.playerRebuilt().outcome == .accepted)
        #expect(elapsed(recovery) == 0.0)
        #expect(recovery.tick(elapsed: 0.25).outcome == .accepted)
        #expect(elapsed(recovery) == 0.25)
        #expect(recovery.tick(elapsed: 0).outcome == .rejectedClock)
        #expect(elapsed(recovery) == 0.25)
        #expect(recovery.playerRebuilt().outcome == .ignored)
        #expect(elapsed(recovery) == 0.25)
    }

    @Test func theSameDeviceDoesNotRestartTheClock() {
        var recovery = PointingFailureRecovery()
        let committed = scene("scene-1", generation: 1, objects: ["battery"])
        #expect(recovery.commit(committed).outcome == .accepted)
        let first = beat("beat-1")
        #expect(recovery.beginBeat(first, deviceID: "speaker-a").outcome == .accepted)
        #expect(recovery.tick(elapsed: 1.25).outcome == .accepted)
        let same = recovery.outputDeviceChanged(to: "speaker-a")
        #expect(same.outcome == .rejectedSameDevice)
        #expect(same.order == .none)
        #expect(same.notice == .none)
        #expect(elapsed(recovery) == 1.25)
        #expect(recovery.outputDeviceChanged(to: " speaker-a ").outcome == .rejectedSameDevice)
        #expect(elapsed(recovery) == 1.25)
        #expect(recovery.beginBeat(first, deviceID: "speaker-a").outcome == .ignored)
        #expect(elapsed(recovery) == 1.25)
        let next = recovery.beginBeat(beat("beat-2", index: 1), deviceID: "speaker-a")
        #expect(next.outcome == .accepted)
        #expect(next.order == .none)
        #expect(elapsed(recovery) == 0.0)
        #expect(recovery.committedScene == committed)
    }

    @Test func anIdleDeviceChangeDoesNotInventABeat() {
        var recovery = PointingFailureRecovery()
        let changed = recovery.outputDeviceChanged(to: " speaker-a ")
        #expect(changed.outcome == .accepted)
        #expect(changed.order == .none)
        #expect(changed.notice == .none)
        #expect(changed.phase == .idle)
        #expect(changed.committedScene == nil)
        #expect(recovery.deviceID == "speaker-a")
        #expect(recovery.phase == .idle)
        #expect(recovery.playerRebuilt().outcome == .ignored)
        #expect(recovery.phase == .idle)
        #expect(recovery.committedScene == nil)
    }

    @Test func aSecondDeviceChangeUsesTheNewestDevice() {
        var recovery = PointingFailureRecovery()
        let committed = scene("scene-1", generation: 2, objects: ["battery"])
        #expect(recovery.commit(committed).outcome == .accepted)
        let current = beat("beat-1")
        #expect(recovery.beginBeat(current, deviceID: "speaker-a").outcome == .accepted)
        let first = recovery.outputDeviceChanged(to: "speaker-b")
        #expect(first.outcome == .accepted)
        #expect(first.order == .rebuildAndResume(beat: current, deviceID: "speaker-b", at: 0))
        let swapped = recovery.beginBeat(beat("beat-9", index: 3), deviceID: "speaker-z")
        #expect(swapped.outcome == .ignored)
        #expect(swapped.order == .none)
        #expect(pending(recovery)?.0 == current)
        #expect(pending(recovery)?.1 == "speaker-b")
        let second = recovery.outputDeviceChanged(to: " speaker-c ")
        #expect(second.outcome == .accepted)
        #expect(second.order == .rebuildAndResume(beat: current, deviceID: "speaker-c", at: PointingFailureRecovery.beatStart))
        #expect(second.committedScene == committed)
        #expect(recovery.deviceID == "speaker-c")
        let repeated = recovery.outputDeviceChanged(to: "speaker-c")
        #expect(repeated.outcome == .ignored)
        #expect(repeated.order == .none)
        #expect(pending(recovery)?.0 == current)
        #expect(pending(recovery)?.1 == "speaker-c")
        #expect(recovery.committedScene == committed)
    }

    @Test func networkLossKeepsTheCommittedSceneAndDropsThePartial() {
        var recovery = PointingFailureRecovery()
        let committed = scene("scene-1", generation: 3, objects: ["battery"])
        #expect(recovery.commit(committed).outcome == .accepted)
        #expect(recovery.stagePartial(objectIDs: ["motor", "wheels"]).outcome == .accepted)
        #expect(recovery.beginBeat(beat("beat-1"), deviceID: "speaker-a").outcome == .accepted)
        #expect(recovery.tick(elapsed: 0.5).outcome == .accepted)
        let lost = recovery.networkLost(provider: "  Any LLM  ")
        #expect(lost.outcome == .accepted)
        #expect(lost.order == .stop)
        #expect(lost.notice == .network("No connection to Any LLM. Check your network and try again."))
        #expect(lost.committedScene == committed)
        #expect(lost.partialObjectIDs == [])
        #expect(recovery.phase == .failed(.network))
        #expect(recovery.committedScene == committed)
        #expect(recovery.partialObjectIDs == [])
        let again = recovery.networkLost(provider: "Any LLM")
        #expect(again.outcome == .ignored)
        #expect(again.order == .none)
        #expect(again.notice == .none)
        #expect(again.committedScene == committed)
        #expect(recovery.committedScene == committed)
        #expect(recovery.partialObjectIDs == [])
    }

    @Test func networkLossBeforeASceneStaysEmptyAndVisible() {
        var recovery = PointingFailureRecovery()
        let lost = recovery.networkLost(provider: "Any LLM")
        #expect(lost.outcome == .accepted)
        #expect(lost.order == .none)
        #expect(lost.notice == .network(PointingFailureRecovery.networkNotice(provider: "Any LLM")))
        #expect(lost.committedScene == nil)
        #expect(lost.partialObjectIDs == [])
        #expect(recovery.phase == .failed(.network))
        let late = recovery.commit(scene("scene-1", generation: 1, objects: ["battery"]))
        #expect(late.outcome == .rejectedFailed)
        #expect(recovery.committedScene == nil)
        #expect(recovery.beginBeat(beat("beat-1"), deviceID: "speaker-a").outcome == .rejectedFailed)
        #expect(recovery.phase == .failed(.network))
    }

    @Test func modelUnavailableKeepsTheSceneAndRefusesAnotherBeat() {
        var recovery = PointingFailureRecovery()
        let committed = scene("scene-1", generation: 5, objects: ["battery", "inverter"])
        #expect(recovery.commit(committed).outcome == .accepted)
        #expect(recovery.stagePartial(objectIDs: ["motor"]).outcome == .accepted)
        let current = beat("beat-4", index: 1)
        #expect(recovery.beginBeat(current, deviceID: "speaker-a").outcome == .accepted)
        #expect(recovery.outputDeviceChanged(to: "speaker-b").order == .rebuildAndResume(beat: current, deviceID: "speaker-b", at: 0))
        let unavailable = recovery.modelUnavailable(provider: "Any LLM")
        #expect(unavailable.outcome == .accepted)
        #expect(unavailable.order == .stop)
        #expect(unavailable.notice == .modelUnavailable("Any LLM does not offer the selected model. Pick another model in Settings."))
        #expect(unavailable.committedScene == committed)
        #expect(unavailable.partialObjectIDs == [])
        #expect(recovery.phase == .failed(.modelUnavailable))
        let refused = recovery.beginBeat(beat("beat-5"), deviceID: "speaker-b")
        #expect(refused.outcome == .rejectedFailed)
        #expect(refused.order == .none)
        #expect(recovery.committedScene == committed)
        #expect(recovery.phase == .failed(.modelUnavailable))
    }

    @Test func failureBlocksResumeCommitAndClock() {
        var recovery = PointingFailureRecovery()
        let committed = scene("scene-1", generation: 1, objects: ["battery"])
        #expect(recovery.commit(committed).outcome == .accepted)
        #expect(recovery.beginBeat(beat("beat-1"), deviceID: "speaker-a").outcome == .accepted)
        #expect(recovery.networkLost(provider: "Any LLM").order == .stop)
        let device = recovery.outputDeviceChanged(to: "speaker-b")
        #expect(device.outcome == .rejectedFailed)
        #expect(device.order == .none)
        #expect(recovery.phase == .failed(.network))
        let late = recovery.commit(scene("scene-2", generation: 9, objects: ["motor"]))
        #expect(late.outcome == .rejectedFailed)
        #expect(recovery.committedScene == committed)
        let clock = recovery.tick(elapsed: 3)
        #expect(clock.outcome == .ignored)
        #expect(clock.order == .none)
        #expect(recovery.phase == .failed(.network))
        #expect(recovery.playerRebuilt().outcome == .ignored)
        let model = recovery.modelUnavailable(provider: "Any LLM")
        #expect(model.outcome == .ignored)
        #expect(model.notice == .none)
        #expect(recovery.phase == .failed(.network))
        #expect(recovery.committedScene == committed)
        #expect(recovery.partialObjectIDs == [])
    }

    @Test func blankIdsAndABadClockAreRefused() {
        var recovery = PointingFailureRecovery()
        #expect(recovery.commit(scene("  ", generation: 1, objects: ["battery"])).outcome == .rejectedEmpty)
        #expect(recovery.committedScene == nil)
        #expect(recovery.commit(scene("scene-1", generation: 1, objects: ["battery", " "])).outcome == .rejectedEmpty)
        #expect(recovery.committedScene == nil)
        let committed = scene("scene-1", generation: 1, objects: ["battery"])
        #expect(recovery.commit(committed).outcome == .accepted)
        #expect(recovery.stagePartial(objectIDs: ["inverter"]).outcome == .accepted)
        #expect(recovery.stagePartial(objectIDs: []).outcome == .rejectedEmpty)
        #expect(recovery.stagePartial(objectIDs: ["motor", " "]).outcome == .rejectedEmpty)
        #expect(recovery.partialObjectIDs == ["inverter"])
        #expect(recovery.beginBeat(beat("  "), deviceID: "speaker-a").outcome == .rejectedEmpty)
        #expect(recovery.phase == .idle)
        #expect(recovery.beginBeat(beat("beat-1", index: -1), deviceID: "speaker-a").outcome == .rejectedScene)
        #expect(recovery.phase == .idle)
        #expect(recovery.beginBeat(beat("beat-1"), deviceID: " ").outcome == .rejectedEmpty)
        #expect(recovery.phase == .idle)
        #expect(recovery.beginBeat(beat("beat-1"), deviceID: "speaker-a").outcome == .accepted)
        #expect(recovery.tick(elapsed: .nan).outcome == .rejectedClock)
        #expect(elapsed(recovery) == 0.0)
        #expect(recovery.tick(elapsed: .infinity).outcome == .rejectedClock)
        #expect(elapsed(recovery) == 0.0)
        #expect(recovery.outputDeviceChanged(to: " ").outcome == .rejectedEmpty)
        #expect(elapsed(recovery) == 0.0)
        #expect(recovery.deviceID == "speaker-a")
        #expect(recovery.networkLost(provider: " ").outcome == .rejectedEmpty)
        #expect(recovery.phase == .playing(beat: beat("beat-1"), deviceID: "speaker-a", elapsed: 0))
        #expect(recovery.committedScene == committed)
        #expect(recovery.partialObjectIDs == ["inverter"])
        #expect(recovery.modelUnavailable(provider: "\n").outcome == .rejectedEmpty)
        #expect(recovery.committedScene == committed)
    }

    @Test func aLowerGenerationDoesNotReplaceTheCommittedScene() {
        var recovery = PointingFailureRecovery()
        #expect(recovery.commit(scene("scene-1", generation: -1, objects: ["battery"])).outcome == .rejectedScene)
        #expect(recovery.committedScene == nil)
        let committed = scene("scene-1", generation: 2, objects: ["battery"])
        #expect(recovery.commit(committed).outcome == .accepted)
        #expect(recovery.stagePartial(objectIDs: ["draft"]).outcome == .accepted)
        let older = recovery.commit(scene("scene-1", generation: 1, objects: ["motor"]))
        #expect(older.outcome == .rejectedScene)
        #expect(recovery.committedScene == committed)
        #expect(recovery.partialObjectIDs == ["draft"])
        let same = recovery.commit(scene("scene-1", generation: 2, objects: ["battery", "inverter"]))
        #expect(same.outcome == .accepted)
        #expect(same.partialObjectIDs == [])
        #expect(recovery.committedScene == scene("scene-1", generation: 2, objects: ["battery", "inverter"]))
        let newer = recovery.commit(scene("scene-2", generation: 3, objects: ["motor"]))
        #expect(newer.outcome == .accepted)
        #expect(recovery.committedScene == scene("scene-2", generation: 3, objects: ["motor"]))
    }
}
