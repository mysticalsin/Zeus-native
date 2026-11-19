import Foundation
import Testing
import ZeusCore

@Suite("Allow all permission sweep")
struct PermissionSweepTests {
    private typealias S = PermissionSweep
    private typealias Access = [S.Item: S.Access]

    /// A fresh Mac: nothing allowed, nothing asked.
    private let fresh: Access = [:]

    private func all(_ value: S.Access) -> Access {
        Dictionary(uniqueKeysWithValues: S.Item.allCases.map { ($0, value) })
    }

    private func start(_ access: Access, resumed: S.Progress? = nil) -> (S.State, [S.Effect]) {
        S.reduce(S.State(), .start(access: access, resumed: resumed, now: 100))
    }

    @Test func inPlacePromptsComeFirstThenSystemSettingsWithScreenRecordingLast() {
        let order = S.plan(fresh).map(\.item)
        #expect(order == [.microphone, .speech, .camera, .calendar, .reminders, .notifications, .location, .automation,
                          .accessibility, .inputMonitoring, .fullDiskAccess, .screenRecording])
        #expect(S.plan(fresh).prefix(8).allSatisfy { $0.route == .prompt })
        #expect(S.plan(fresh).suffix(4).allSatisfy { $0.route == .settings })
    }

    @Test func startingAsksTheFirstPromptAndShowsTheGuide() {
        let (state, effects) = start(fresh)
        #expect(state.phase == .prompting(.microphone))
        #expect(effects.contains(.ask(.microphone)))
        #expect(effects.contains(.showGuide(.microphone)))
        #expect(effects.contains(.startPolling))
        #expect(effects.contains(.save(S.Progress(visited: [.microphone], needsRestart: false, savedAt: 100))))
    }

    @Test func alreadyAllowedItemsAreSkipped() {
        var access = fresh
        access[.microphone] = .allowed
        access[.speech] = .allowed
        access[.camera] = .allowed
        let (state, effects) = start(access)
        #expect(state.phase == .prompting(.calendar))
        #expect(!effects.contains(.ask(.microphone)))
        #expect(!S.plan(access).map(\.item).contains(.camera))
    }

    @Test func everythingAllowedFinishesAtOnceWithoutAsking() {
        let (state, effects) = start(all(.allowed))
        #expect(state.phase == .finished(needsRestart: false))
        #expect(effects == [.clearProgress])
        #expect(S.progressLine(all(.allowed)) == "12 of 12 allowed")
    }

    @Test func aRefusedPromptGoesToItsSettingsPaneInstead() {
        var access = fresh
        access[.camera] = .denied
        let plan = S.plan(access)
        #expect(plan.first { $0.item == .camera }?.route == .settings)
        // Refused prompts wait until every prompt that can still ask has asked.
        #expect(plan.firstIndex { $0.item == .camera }! > plan.firstIndex { $0.item == .automation }!)
    }

    @Test func aPromptAnswerMovesToTheNextPrompt() {
        let (state, _) = start(fresh)
        var access = fresh
        access[.microphone] = .allowed
        access[.speech] = .allowed
        let (next, effects) = S.reduce(state, .promptAnswered(.microphone, access: access, now: 101))
        // Speech was answered by the same voice prompt: it is not asked again.
        #expect(next.phase == .prompting(.camera))
        #expect(effects.contains(.ask(.camera)))
        #expect(!effects.contains(.ask(.speech)))
        #expect(!effects.contains(.startPolling))
    }

    @Test func aPromptRefusedDuringTheSweepIsNotSentToSettingsOrAskedAgain() {
        var state = start(fresh).0
        var access = fresh
        access[.microphone] = .denied
        access[.speech] = .denied
        var asked: [S.Item] = [.microphone]
        var guided: [S.Item] = []
        var effects: [S.Effect] = []
        (state, effects) = S.reduce(state, .promptAnswered(.microphone, access: access, now: 101))
        while state.isRunning {
            for effect in effects {
                if case .ask(let item) = effect { asked.append(item) }
                if case .openSettings(let item, _) = effect { guided.append(item) }
            }
            (state, effects) = S.reduce(state, .skip(access: access, now: 102))
        }
        #expect(!asked.dropFirst().contains(.microphone))
        #expect(!asked.contains(.speech))
        #expect(!guided.contains(.microphone))
        #expect(!guided.contains(.speech))
        #expect(Set(asked).count == asked.count)
    }

    @Test func aSettingsStepRequestsOpensThePaneAndAdvancesWhenTheSwitchFlips() {
        var access = all(.allowed)
        access[.accessibility] = .notAsked
        access[.inputMonitoring] = .notAsked
        let (state, effects) = start(access)
        #expect(state.phase == .guiding(.accessibility))
        #expect(effects.contains(.openSettings(.accessibility, request: true)))
        #expect(effects.contains(.showGuide(.accessibility)))
        #expect(effects.contains(.startPolling))

        let (same, none) = S.reduce(state, .poll(access: access, now: 101))
        #expect(same == state)
        #expect(none.isEmpty)

        // Accessibility is enough for keys from other apps, so Input Monitoring reads allowed too.
        access[.accessibility] = .allowed
        access[.inputMonitoring] = .allowed
        let (done, finish) = S.reduce(state, .poll(access: access, now: 102))
        #expect(done.phase == .finished(needsRestart: false))
        #expect(finish == [.hideGuide, .stopPolling, .clearProgress])
    }

    @Test func fullDiskAccessOpensItsPaneWithoutARequestCall() {
        var access = all(.allowed)
        access[.fullDiskAccess] = .notAsked
        let (_, effects) = start(access)
        #expect(effects.contains(.openSettings(.fullDiskAccess, request: false)))
        #expect(S.guideText(.guiding(.fullDiskAccess)).contains("+"))
    }

    @Test func aPromptWithoutACompletionAdvancesWhenThePollSeesTheAnswer() {
        var access = all(.allowed)
        access[.location] = .notAsked
        let (state, _) = start(access)
        #expect(state.phase == .prompting(.location))
        #expect(S.reduce(state, .poll(access: access, now: 101)).0 == state)
        access[.location] = .denied
        #expect(S.reduce(state, .poll(access: access, now: 102)).0.phase == .finished(needsRestart: false))
    }

    @Test func aLateAnswerForAnEarlierPromptChangesNothing() {
        let (state, _) = start(fresh)
        var access = fresh
        access[.microphone] = .allowed
        let (atSpeech, _) = S.reduce(state, .poll(access: access, now: 101))
        #expect(atSpeech.phase == .prompting(.speech))
        let (same, effects) = S.reduce(atSpeech, .promptAnswered(.microphone, access: access, now: 102))
        #expect(same == atSpeech)
        #expect(effects.isEmpty)
    }

    @Test func skipMovesOnAndCancelStopsEverything() {
        let (state, _) = start(fresh)
        let (skipped, _) = S.reduce(state, .skip(access: fresh, now: 101))
        #expect(skipped.phase == .prompting(.speech))
        let (cancelled, effects) = S.reduce(skipped, .cancel)
        #expect(cancelled.phase == .cancelled)
        #expect(effects == [.hideGuide, .stopPolling, .clearProgress])
        #expect(S.reduce(cancelled, .poll(access: fresh, now: 102)).1.isEmpty)
    }

    @Test func pressingAllowAllAgainWhileRunningDoesNothing() {
        let (state, _) = start(fresh)
        let (same, effects) = S.reduce(state, .start(access: fresh, resumed: nil, now: 101))
        #expect(same == state)
        #expect(effects.isEmpty)
    }

    @Test func screenRecordingDoneWithoutAGrantAsksForARestart() {
        var access = all(.allowed)
        access[.screenRecording] = .notAsked
        let (state, effects) = start(access)
        #expect(effects.contains(.openSettings(.screenRecording, request: true)))
        let (done, _) = S.reduce(state, .done(access: access, now: 101))
        #expect(done.phase == .finished(needsRestart: true))
        #expect(S.guideText(done.phase) == "Restart Zeus to finish Screen Recording.")
    }

    @Test func noRestartWhenScreenRecordingReadsAllowedOrWasSkipped() {
        var access = all(.allowed)
        access[.screenRecording] = .notAsked
        let (state, _) = start(access)
        #expect(S.reduce(state, .skip(access: access, now: 101)).0.phase == .finished(needsRestart: false))
        access[.screenRecording] = .allowed
        #expect(S.reduce(state, .done(access: access, now: 101)).0.phase == .finished(needsRestart: false))
    }

    @Test func afterARelaunchTheSweepResumesWithoutAskingVisitedItemsAgain() {
        var access = fresh
        for item in S.Item.allCases.prefix(8) { access[item] = .denied }
        let saved = S.Progress(visited: Array(S.Item.allCases.prefix(9)), needsRestart: false, savedAt: 50)
        #expect(S.shouldResume(saved, now: 100))
        let (state, effects) = start(access, resumed: saved)
        // The refused prompts and Accessibility were already handled before Zeus reopened.
        #expect(state.phase == .guiding(.inputMonitoring))
        #expect(!effects.contains { if case .ask = $0 { return true }; return false })
        #expect(!effects.contains(.openSettings(.accessibility, request: true)))
    }

    @Test func resumingWithNothingLeftFinishesQuietly() {
        let saved = S.Progress(visited: S.Item.allCases, needsRestart: true, savedAt: 50)
        var access = all(.allowed)
        access[.screenRecording] = .allowed
        let (state, effects) = start(access, resumed: saved)
        #expect(state.phase == .finished(needsRestart: false))
        #expect(effects == [.clearProgress])
    }

    @Test func oldOrMissingProgressIsNotResumed() {
        #expect(!S.shouldResume(nil, now: 100))
        let old = S.Progress(visited: [.microphone], needsRestart: false, savedAt: 0)
        #expect(!S.shouldResume(old, now: S.resumeWindow + 1))
    }

    @Test func progressRoundTripsThroughJSON() throws {
        let progress = S.Progress(visited: [.microphone, .screenRecording], needsRestart: true, savedAt: 12)
        let data = try JSONEncoder().encode(progress)
        let decoded = try JSONDecoder().decode(S.Progress.self, from: data)
        #expect(decoded == progress)
    }

    @Test func aFullSweepOnAFreshMacVisitsEveryItemExactlyOnce() {
        var (state, effects) = start(fresh)
        var visited: [S.Item] = []
        var access = fresh
        while state.isRunning {
            for effect in effects {
                if case .showGuide(let item) = effect { visited.append(item) }
            }
            let item = state.current!
            access[item] = .allowed
            if item == .accessibility { access[.inputMonitoring] = .allowed }
            (state, effects) = S.reduce(state, .poll(access: access, now: 200))
        }
        // Input Monitoring comes with Accessibility, so the guide never stops there.
        #expect(visited == S.Item.allCases.filter { $0 != .inputMonitoring })
        #expect(state.phase == .finished(needsRestart: false))
        #expect(S.allowedCount(access) == S.Item.allCases.count)
    }

    @Test func userTextHasNoEmDash() {
        let phases: [S.Phase] = S.Item.allCases.flatMap { [.prompting($0), .guiding($0)] }
            + [.finished(needsRestart: true), .finished(needsRestart: false)]
        let texts = phases.map(S.guideText) + S.Item.allCases.map(\.title)
        #expect(texts.allSatisfy { !$0.contains("\u{2014}") })
    }
}
