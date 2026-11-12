import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor @Suite struct BrainWarmSchedulerTests {
    private func scheduler(clock: Box) -> (BrainWarmScheduler, Log) {
        let log = Log()
        let scheduler = BrainWarmScheduler()
        scheduler.now = { clock.date }
        scheduler.warm = { targets in log.calls.append(targets) }
        return (scheduler, log)
    }

    final class Box { var date = Date(timeIntervalSince1970: 2_000_000) }
    final class Log { var calls: [Set<BrainWarmPlan.Target>] = [] }

    @Test func doesNothingUntilZeusIsUsed() async {
        let clock = Box()
        let (scheduler, log) = scheduler(clock: clock)
        await scheduler.tick()
        #expect(log.calls.isEmpty)
    }

    @Test func warmsAfterActivityThenWaitsForTheNextInterval() async {
        let clock = Box()
        let (scheduler, log) = scheduler(clock: clock)
        scheduler.noteActivity()
        await scheduler.tick()
        #expect(log.calls == [[.localModel, .cloudConnection]])
        clock.date.addTimeInterval(60)
        await scheduler.tick()
        #expect(log.calls.count == 1, "too soon to ping again")
        clock.date.addTimeInterval(BrainWarmPlan.cloudInterval)
        scheduler.noteActivity()
        await scheduler.tick()
        #expect(log.calls.last == [.cloudConnection])
    }

    @Test func launchAndWakeStyleTicksWithoutActivityWarmNothing() async {
        let clock = Box()
        let (scheduler, log) = scheduler(clock: clock)
        await scheduler.tick()
        clock.date.addTimeInterval(BrainWarmPlan.checkEvery * 3)
        await scheduler.tick()
        #expect(log.calls.isEmpty)
    }

    @Test func talkKeyDownWarmsBothTargets() async {
        let clock = Box()
        let (scheduler, log) = scheduler(clock: clock)
        scheduler.noteActivity()
        await scheduler.tick()
        #expect(log.calls == [[.localModel, .cloudConnection]])
    }

    @Test func stopsPingingOnceZeusGoesQuiet() async {
        let clock = Box()
        let (scheduler, log) = scheduler(clock: clock)
        scheduler.noteActivity()
        await scheduler.tick()
        clock.date.addTimeInterval(BrainWarmPlan.activeWindow + 600)
        await scheduler.tick()
        #expect(log.calls.count == 1)
    }

    @MainActor private final class ActionLog {
        var local = 0
        var cloud = 0
        var selectionReads = 0
        var voices: [String] = []
        var speeds: [Double] = []
        var selection = BrainWarmActions.VoiceSelection(
            provider: .kokoro, ready: true, paused: false, voice: "synthetic-voice", speed: 0.9)

        var actions: BrainWarmActions {
            BrainWarmActions(localModel: { self.local += 1 },
                             cloudConnection: { self.cloud += 1 },
                             voiceSelection: { self.selectionReads += 1; return self.selection },
                             renderVoice: { voice, speed in self.voices.append(voice); self.speeds.append(speed) })
        }
    }

    @Test func cloudOnlyWarmDoesNotInspectVoiceSettingsOrRenderLocalVoice() async {
        let log = ActionLog()
        await log.actions.run([])
        #expect(log.local == 0 && log.cloud == 0 && log.selectionReads == 0)
        await log.actions.run([.cloudConnection])
        #expect(log.cloud == 1 && log.local == 0)
        #expect(log.selectionReads == 0 && log.voices.isEmpty)
    }

    @Test func localAndStartupWarmOnlyTheSelectedReadyKokoroVoice() async {
        let log = ActionLog()
        await log.actions.run([.localModel])
        #expect(log.local == 1 && log.cloud == 0)
        #expect(log.voices == ["synthetic-voice"] && log.speeds == [0.9])
        await log.actions.warmSelectedVoice() // The launch route uses this same selected-only action.
        #expect(log.voices == ["synthetic-voice", "synthetic-voice"])
        #expect(log.local == 1 && log.cloud == 0)
    }

    @Test func unselectedUnreadyAndPausedVoicesNeverWarmAsFallbacks() async {
        let log = ActionLog()
        for provider in VoiceTTSProvider.allCases where provider != .kokoro {
            log.selection = .init(provider: provider, ready: true, paused: false, voice: "unused", speed: 1)
            await log.actions.run([.localModel, .cloudConnection])
            await log.actions.warmSelectedVoice()
        }
        log.selection = .init(provider: .kokoro, ready: false, paused: false, voice: "missing", speed: 1)
        await log.actions.warmSelectedVoice()
        log.selection = .init(provider: .kokoro, ready: true, paused: true, voice: "paused", speed: 1)
        await log.actions.warmSelectedVoice()
        #expect(log.local == 3 && log.cloud == 3)
        #expect(log.voices.isEmpty && log.speeds.isEmpty)
    }

    @Test func canceledWarmStartsNoProvidersOrVoiceRender() async {
        let log = ActionLog()
        let task = Task { @MainActor in
            await log.actions.run([.localModel, .cloudConnection])
            await log.actions.warmSelectedVoice()
        }
        task.cancel()
        await task.value
        #expect(log.local == 0 && log.cloud == 0 && log.selectionReads == 0 && log.voices.isEmpty)
    }
}
