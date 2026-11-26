import Testing
@testable import ZeusCore

/// The window flow in `docs/STEP-ZERO-PROBE-PLAN.md`. No clock, no window, no process.
@Suite("Step zero flow")
struct StepZeroFlowTests {
    private let developerOrder: [StepZeroFlow.Part] = [
        .sealBeforeSpawn, .helperLine, .systemSourceSkip,
        .lockScreen, .lockLook, .lockPlayerQuiet, .lockPlayerAsk, .lockPlayerScript,
        .killTest,
        .earbudsPaired, .earbudsManager, .earbudsMode,
        .focusRead, .focusTool,
        .soundSwitch, .soundNetwork,
        .musicNotice,
    ]

    @Test func theLimitsMatchTheTable() {
        #expect(StepZeroFlow.continueDeadMilliseconds == 1500)
        #expect(row(.helperLine, seconds: 5, onExpiry: .moveOn, record: .timedOut, restore: false))
        #expect(row(.bluetoothManager, seconds: 10, onExpiry: .moveOn, record: .notMeasured, restore: false))
        #expect(row(.bluetoothClassic, seconds: 15, onExpiry: .stop, record: .hung, restore: false))
        #expect(row(.signatureCheck, seconds: 10, onExpiry: .stop, record: .refusal, restore: false))
        #expect(row(.coreAudio, seconds: 2, onExpiry: .moveOn, record: .stepFailed, restore: true))
        #expect(row(.automationQuiet, seconds: 2, onExpiry: .moveOn, record: .timedOut, restore: false))
        #expect(row(.automationAsk, seconds: 60, onExpiry: .moveOn, record: .timedOut, restore: false))
        #expect(row(.playerScript, seconds: 3, onExpiry: .moveOn, record: .verbNo, restore: false))
        #expect(row(.toolStart, seconds: 5, onExpiry: .moveOn, record: .timedOut, restore: false))
        #expect(row(.stopAndRestore, seconds: 5, onExpiry: .stop, record: .timedOut, restore: false))
        #expect(row(.lockCard, seconds: 120, onExpiry: .moveOn, record: .destroyed, restore: false))
        #expect(row(.looking, seconds: 300, onExpiry: .moveOn, record: .destroyed, restore: false))
        #expect(row(.speakerBrowse, seconds: 20, onExpiry: .moveOn, record: .cancelled, restore: false))
        #expect(row(.musicNotice, seconds: 15, onExpiry: .moveOn, record: .timedOut, restore: false))
    }

    @Test func noRunWithoutAContinuePressed() {
        let (opened, opening) = StepZeroFlow.begin(.developerID)
        #expect(runs(opening).isEmpty)
        #expect(opening == [.arm(StepZeroFlow.continueDeadMilliseconds)])

        let (ignoredContinue, continueEffects) = StepZeroFlow.reduce(opened, .continuePressed)
        #expect(ignoredContinue == opened)
        #expect(continueEffects.isEmpty)

        let (ignoredFinish, finishEffects) = StepZeroFlow.reduce(opened, .partFinished(.sealBeforeSpawn))
        #expect(ignoredFinish == opened)
        #expect(finishEffects.isEmpty)

        let (ignoredTimeout, timeoutEffects) = StepZeroFlow.reduce(opened, .partTimedOut(.sealBeforeSpawn))
        #expect(ignoredTimeout == opened)
        #expect(timeoutEffects.isEmpty)

        let (ignoredHand, handEffects) = StepZeroFlow.reduce(opened, .handAnswered(.lockLook, .done))
        #expect(ignoredHand == opened)
        #expect(handEffects.isEmpty)

        let (live, armedEffects) = StepZeroFlow.reduce(opened, .armed)
        #expect(armedEffects.isEmpty)
        #expect(live.armed)

        let (_, skipEffects) = StepZeroFlow.reduce(live, .skipPressed)
        #expect(runs(skipEffects).isEmpty)
        #expect(skipEffects == [.journal(.skipped(.sealBeforeSpawn))])

        let (resumed, resumeEffects) = StepZeroFlow.reduce(opened, .resumed(.init(owesRestore: true)))
        #expect(resumeEffects.isEmpty)
        #expect(runs(resumeEffects).isEmpty)
        #expect(resumed.current == .putBack)

        let (ran, started) = StepZeroFlow.reduce(live, .continuePressed)
        #expect(runs(started) == [.sealBeforeSpawn])
        #expect(started.contains(.run(.sealBeforeSpawn, StepZeroFlow.Part.sealBeforeSpawn.limit)))
        let (afterFinish, finished) = StepZeroFlow.reduce(ran, .partFinished(.sealBeforeSpawn))
        #expect(runs(finished).isEmpty)
        #expect(afterFinish.current == .helperLine)

        let runningHelper = at(.helperLine, .running(.helperLine))
        let (afterTimeout, timed) = StepZeroFlow.reduce(runningHelper, .partTimedOut(.helperLine))
        #expect(runs(timed).isEmpty)
        #expect(afterTimeout.current == .systemSourceSkip)

        let looking = at(.lockLook, .yourTurn(.lockLook))
        let (_, handed) = StepZeroFlow.reduce(looking, .handAnswered(.lockLook, .yes))
        #expect(runs(handed).isEmpty)
        #expect(handed.contains(.journal(.hand(.lockLook, .yes))))
    }

    @Test func aPressBeforeArmedIsDropped() {
        let (opened, _) = StepZeroFlow.begin(.developerID)
        let (continued, continueEffects) = StepZeroFlow.reduce(opened, .continuePressed)
        let (skipped, skipEffects) = StepZeroFlow.reduce(opened, .skipPressed)
        #expect(continued == opened)
        #expect(skipped == opened)
        #expect(continueEffects.isEmpty)
        #expect(skipEffects.isEmpty)
        #expect(opened.phase(.systemSource) == .asking(.sealBeforeSpawn))
    }

    @Test func skipRecordsSkippedAndMovesOn() {
        let (opened, _) = StepZeroFlow.begin(.developerID)
        let (live, _) = StepZeroFlow.reduce(opened, .armed)
        let (next, effects) = StepZeroFlow.reduce(live, .skipPressed)
        #expect(effects == [.journal(.skipped(.sealBeforeSpawn))])
        #expect(runs(effects).isEmpty)
        #expect(next.outcomes[.sealBeforeSpawn] == .skipped)
        #expect(next.current == .helperLine)
        #expect(next.phase(.systemSource) == .asking(.helperLine))

        let (second, _) = StepZeroFlow.reduce(next, .skipPressed)
        let (third, last) = StepZeroFlow.reduce(second, .skipPressed)
        #expect(last == [.journal(.skipped(.systemSourceSkip))])
        #expect(third.phase(.systemSource) == .skipped)
        #expect(third.current == .lockScreen)
        #expect(third.phase(.lockScreen) == .asking(.lockScreen))

        let (ran, _) = StepZeroFlow.reduce(live, .continuePressed)
        let (finished, _) = StepZeroFlow.reduce(ran, .partFinished(.sealBeforeSpawn))
        let (skippedHelper, _) = StepZeroFlow.reduce(finished, .skipPressed)
        let (partial, _) = StepZeroFlow.reduce(skippedHelper, .skipPressed)
        #expect(partial.outcomes[.sealBeforeSpawn] == .finished)
        #expect(partial.phase(.systemSource) == .partial)
        #expect(partial.current == .lockScreen)
    }

    @Test func aSectionWithAPromptShowsItsSentenceFirst() {
        let (opened, effects) = StepZeroFlow.begin(.developerID)
        #expect(opened.phase(.systemSource) == .asking(.sealBeforeSpawn))
        #expect(StepZeroFlow.Part.sealBeforeSpawn.line == StepZeroFlow.systemSourceLine)
        #expect(StepZeroFlow.systemSourceLine == "This reads what any app on this Mac is playing, pauses it, moves the position, and shows the word Zeus in the Mac's own now-playing display for up to three seconds. Each is put back.")
        #expect(StepZeroFlow.result(for: opened.phase(.systemSource)).word == "Not run")
        #expect(StepZeroFlow.result(for: opened.phase(.systemSource)).symbol == "circle")
        #expect(runs(effects).isEmpty)
        #expect(opened.phase(.lockScreen) == .notRun)
    }

    @Test func aResumedJournalWithAnOwedRestoreShowsPutBackFirst() {
        let (opened, _) = StepZeroFlow.begin(.adHoc)
        let (back, effects) = StepZeroFlow.reduce(opened, .resumed(.init(owesRestore: true)))
        #expect(effects.isEmpty)
        #expect(back.armed == false)
        #expect(back.owesRestore)
        #expect(back.current == .putBack)
        #expect(back.phase(.putBack) == .asking(.putBack))
        #expect(back.phase(.systemSource) == .notRun)
        #expect(back.phase(.earbuds) == .notRun)
        #expect(StepZeroFlow.Part.putBack.line == "The last run ended early. This puts your earbuds' listening mode back and stops one helper process.")

        let (held, none) = StepZeroFlow.reduce(back, .continuePressed)
        #expect(held == back)
        #expect(none.isEmpty)

        let (live, _) = StepZeroFlow.reduce(back, .armed)
        let (_, started) = StepZeroFlow.reduce(live, .continuePressed)
        #expect(runs(started) == [.putBack])
        #expect(started.contains(.run(.putBack, StepZeroFlow.Part.putBack.limit)))
        #expect(started.contains(.journal(.started(.putBack))))
        #expect(!started.contains(.writeReport))
        #expect(StepZeroFlow.Part.putBack.limit.seconds == 5)
        #expect(StepZeroFlow.Part.putBack.limit.onExpiry == .stop)

        let (plain, plainEffects) = StepZeroFlow.reduce(opened, .resumed(.init(owesRestore: false)))
        #expect(plainEffects.isEmpty)
        #expect(plain.current == .sealBeforeSpawn)
        #expect(plain.phase(.putBack) == .notRun)
    }

    @Test func everyPartHasALimit() {
        var seen = Set<StepZeroFlow.LimitRow>()
        for part in StepZeroFlow.Part.allCases {
            let limit = part.limit
            #expect(limit.seconds > 0)
            #expect(limit.row == part.row)
            #expect(limit == StepZeroFlow.limit(for: part.row))
            #expect(StepZeroFlow.Part.representative(for: part.row).row == part.row)
            seen.insert(part.row)
        }
        #expect(seen == Set(StepZeroFlow.LimitRow.allCases))
        let order = StepZeroFlow.sectionOrder(owesRestore: false).flatMap(\.parts)
        #expect(order == developerOrder)
        #expect(StepZeroFlow.sectionOrder(owesRestore: true).first == .putBack)
        #expect(Array(StepZeroFlow.sectionOrder(owesRestore: true).dropFirst()) == developerOrder.map(\.section).reduce(into: [StepZeroFlow.Section]()) { rows, section in
            if rows.last != section { rows.append(section) }
        })
    }

    @Test func partTimedOutFollowsEachRowOfTheLimitsTable() {
        for row in StepZeroFlow.LimitRow.allCases {
            let part = StepZeroFlow.Part.representative(for: row)
            #expect(part.row == row)
            let phase: StepZeroFlow.Phase = part.kind == .hand ? .yourTurn(part) : .running(part)
            let state = at(part, phase)
            let (next, effects) = StepZeroFlow.reduce(state, .partTimedOut(part))
            let limit = part.limit
            #expect(effects.contains(.journal(.timedOut(part, record: limit.record, restoreStillTried: limit.restoreStillTried))))
            #expect(runs(effects).isEmpty)
            switch limit.onExpiry {
            case .stop:
                #expect(next.phase(part.section) == .stopped)
                #expect(next.current == part)
                #expect(!effects.contains(.writeReport))
            case .moveOn:
                #expect(next.phase(part.section) != .stopped)
            }
        }

        let (helper, helperEffects) = StepZeroFlow.reduce(at(.helperLine, .running(.helperLine)), .partTimedOut(.helperLine))
        #expect(helper.current == .systemSourceSkip)
        #expect(helper.phase(.systemSource) == .asking(.systemSourceSkip))
        #expect(helper.outcomes[.helperLine] == .timedOut)
        #expect(helperEffects.contains(.journal(.timedOut(.helperLine, record: .timedOut, restoreStillTried: false))))

        let (card, _) = StepZeroFlow.reduce(at(.lockScreen, .running(.lockScreen)), .partTimedOut(.lockScreen))
        #expect(card.phase(.lockScreen) == .yourTurn(.lockLook))
        #expect(card.current == .lockLook)

        let (looked, lookedEffects) = StepZeroFlow.reduce(at(.lockLook, .yourTurn(.lockLook)), .partTimedOut(.lockLook))
        #expect(looked.phase(.lockScreen) == .asking(.lockPlayerQuiet))
        #expect(lookedEffects.contains(.journal(.timedOut(.lockLook, record: .destroyed, restoreStillTried: false))))

        let (classic, classicEffects) = StepZeroFlow.reduce(at(.earbudsPaired, .running(.earbudsPaired)), .partTimedOut(.earbudsPaired))
        #expect(classic.phase(.earbuds) == .stopped)
        #expect(classicEffects.contains(.journal(.timedOut(.earbudsPaired, record: .hung, restoreStillTried: false))))
        #expect(!classicEffects.contains(.writeReport))

        let (audio, audioEffects) = StepZeroFlow.reduce(at(.earbudsMode, .running(.earbudsMode)), .partTimedOut(.earbudsMode))
        #expect(audio.phase(.earbuds) == .partial)
        #expect(audio.current == .focusRead)
        #expect(audioEffects.contains(.journal(.timedOut(.earbudsMode, record: .stepFailed, restoreStillTried: true))))
        #expect(!audioEffects.contains(.writeReport))

        let (seal, sealEffects) = StepZeroFlow.reduce(at(.sealBeforeSpawn, .running(.sealBeforeSpawn)), .partTimedOut(.sealBeforeSpawn))
        #expect(seal.phase(.systemSource) == .stopped)
        #expect(sealEffects.contains(.journal(.timedOut(.sealBeforeSpawn, record: .refusal, restoreStillTried: false))))

        let (music, musicEffects) = StepZeroFlow.reduce(at(.musicNotice, .running(.musicNotice)), .partTimedOut(.musicNotice))
        #expect(music.phase(.musicPosition) == .partial)
        #expect(music.current == nil)
        #expect(musicEffects.contains(.writeReport))
        #expect(runs(musicEffects).isEmpty)

        let (restore, restoreEffects) = StepZeroFlow.reduce(at(.putBack, .running(.putBack)), .partTimedOut(.putBack))
        #expect(restore.phase(.putBack) == .stopped)
        #expect(restore.phase(.systemSource) == .notRun)
        #expect(restoreEffects.contains(.journal(.timedOut(.putBack, record: .timedOut, restoreStillTried: false))))
        #expect(!restoreEffects.contains(.writeReport))
    }

    @Test func anAdHocBuildCannotReachAPartOutsideSystemSource() {
        for signing: StepZeroFlow.Signing in [.adHoc, .localIdentity, .unread] {
            var (state, _) = StepZeroFlow.begin(signing)
            #expect(state.current == .sealBeforeSpawn)
            #expect(state.phase(.lockScreen) == .notRun)
            #expect(state.phase(.earbuds) == .notRun)
            #expect(state.phase(.musicPosition) == .notRun)

            let crafted = at(.earbudsPaired, .asking(.earbudsPaired), signing: signing)
            let (held, none) = StepZeroFlow.reduce(crafted, .continuePressed)
            #expect(held == crafted)
            #expect(none.isEmpty)
            let (heldSkip, skipNone) = StepZeroFlow.reduce(crafted, .skipPressed)
            #expect(heldSkip == crafted)
            #expect(skipNone.isEmpty)

            var reports = 0
            for part in [StepZeroFlow.Part.sealBeforeSpawn, .helperLine, .systemSourceSkip] {
                #expect(state.current == part)
                let (live, _) = StepZeroFlow.reduce(state, .armed)
                let (ran, started) = StepZeroFlow.reduce(live, .continuePressed)
                #expect(runs(started) == [part])
                let (next, finished) = StepZeroFlow.reduce(ran, .partFinished(part))
                #expect(runs(finished).isEmpty)
                if finished.contains(.writeReport) { reports += 1 }
                state = next
            }
            #expect(reports == 1)
            #expect(state.phase(.systemSource) == .done)
            #expect(state.phase(.lockScreen) == .notRun)
            #expect(state.phase(.killTest) == .notRun)
            #expect(state.phase(.earbuds) == .notRun)
            #expect(state.phase(.focus) == .notRun)
            #expect(state.phase(.soundOutput) == .notRun)
            #expect(state.phase(.musicPosition) == .notRun)
            #expect(state.current == nil)
        }
    }

    @Test func resultWordsStayInsideTheFixedList() {
        let samples: [(StepZeroFlow.Phase, String, String)] = [
            (.notRun, "Not run", "circle"),
            (.asking(.sealBeforeSpawn), "Not run", "circle"),
            (.running(.helperLine), "Running", "arrow.triangle.2.circlepath"),
            (.yourTurn(.lockLook), "Your turn", "hand.point.up.left"),
            (.done, "Done", "checkmark.circle"),
            (.partial, "Partly done", "circle.lefthalf.filled"),
            (.skipped, "Skipped", "forward"),
            (.stopped, "Stopped", "exclamationmark.triangle"),
        ]
        for (phase, word, symbol) in samples {
            #expect(StepZeroFlow.result(for: phase) == .init(word: word, symbol: symbol))
        }

        var found: [String] = []
        for section in StepZeroFlow.Section.allCases {
            found.append(section.title)
        }
        for part in StepZeroFlow.Part.allCases {
            found.append(part.line)
        }
        for (_, word, symbol) in samples {
            found.append(word)
            found.append(symbol)
        }
        #expect(Set(found) == Set(StepZeroFlow.visibleCopy))
        #expect(Set(StepZeroFlow.visibleCopy).count == StepZeroFlow.visibleCopy.count)
        #expect(StepZeroFlow.visibleCopy.count == 38)
        for line in StepZeroFlow.visibleCopy {
            #expect(!line.contains("\u{2014}"))
            #expect(!line.contains("\u{2013}"))
        }
        #expect(StepZeroFlow.lockInstruction == "Lock the Mac. Unlock it when the card has shown.")
        #expect(StepZeroFlow.readNowLine == "Read now")
        #expect(StepZeroFlow.skipLine == "This skips to the next track and back in your music player. The player may count one skip.")
        #expect(StepZeroFlow.musicLine == "This watches the notices Music posts while you play, pause, skip and scrub.")
    }

    @Test func aDeveloperIDRunWritesTheReportAtTheEnd() {
        var (state, opening) = StepZeroFlow.begin(.developerID)
        #expect(opening == [.arm(StepZeroFlow.continueDeadMilliseconds)])
        #expect(StepZeroFlow.sectionOrder(owesRestore: false).flatMap(\.parts) == developerOrder)
        var reports = 0
        var runCount = 0
        for part in developerOrder {
            #expect(state.current == part)
            if part.kind == .hand {
                #expect(state.phase(part.section) == .yourTurn(part))
                let (next, effects) = StepZeroFlow.reduce(state, .handAnswered(part, .done))
                #expect(runs(effects).isEmpty)
                if effects.contains(.writeReport) { reports += 1 }
                state = next
                continue
            }
            #expect(state.phase(part.section) == .asking(part))
            let (live, armedEffects) = StepZeroFlow.reduce(state, .armed)
            #expect(armedEffects.isEmpty)
            let (ran, started) = StepZeroFlow.reduce(live, .continuePressed)
            #expect(runs(started) == [part])
            #expect(started.contains(.run(part, part.limit)))
            runCount += 1
            let (next, finished) = StepZeroFlow.reduce(ran, .partFinished(part))
            #expect(runs(finished).isEmpty)
            if finished.contains(.writeReport) { reports += 1 }
            state = next
        }
        #expect(runCount == 16)
        #expect(reports == 1)
        #expect(state.current == nil)
        #expect(state.phase(.systemSource) == .done)
        #expect(state.phase(.lockScreen) == .done)
        #expect(state.phase(.killTest) == .done)
        #expect(state.phase(.earbuds) == .done)
        #expect(state.phase(.focus) == .done)
        #expect(state.phase(.soundOutput) == .done)
        #expect(state.phase(.musicPosition) == .done)
        #expect(state.phase(.putBack) == .notRun)
    }

    private func row(
        _ row: StepZeroFlow.LimitRow,
        seconds: Int,
        onExpiry: StepZeroFlow.Expiry,
        record: StepZeroFlow.Record,
        restore: Bool
    ) -> Bool {
        StepZeroFlow.limit(for: row) == .init(
            row: row,
            seconds: seconds,
            onExpiry: onExpiry,
            record: record,
            restoreStillTried: restore
        )
    }

    private func runs(_ effects: [StepZeroFlow.Effect]) -> [StepZeroFlow.Part] {
        effects.compactMap { effect in
            if case .run(let part, _) = effect { return part }
            return nil
        }
    }

    private func at(
        _ part: StepZeroFlow.Part,
        _ phase: StepZeroFlow.Phase,
        signing: StepZeroFlow.Signing = .developerID
    ) -> StepZeroFlow.State {
        let owes = part.section == .putBack
        var phases: [StepZeroFlow.Section: StepZeroFlow.Phase] = [:]
        for section in StepZeroFlow.Section.allCases {
            phases[section] = .notRun
        }
        for section in StepZeroFlow.sectionOrder(owesRestore: owes) {
            if section == part.section { break }
            if StepZeroFlow.canReach(section, signing: signing) {
                phases[section] = .done
            }
        }
        phases[part.section] = phase
        return .init(
            signing: signing,
            armed: true,
            owesRestore: owes,
            phases: phases,
            outcomes: [:],
            current: part
        )
    }
}
