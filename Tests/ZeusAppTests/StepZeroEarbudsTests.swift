import Testing
@testable import Zeus

@Suite("Step zero earbuds")
struct StepZeroEarbudsTests {
    @Test func aDeniedConsentTouchesNoDevice() {
        for access in [EarbudsSection.Access.denied, .restricted] {
            var trace = Trace()
            #expect(trace.step(.begin) == [.readAccess])
            #expect(trace.step(.access(access)).isEmpty)
            #expect(trace.state.accessBefore == access)
            #expect(trace.state.phase == .done)
            #expect(trace.step(.continueAsked).isEmpty)
            #expect(trace.step(.classicReturned).isEmpty)
            #expect(trace.step(.prompt(.appeared)).isEmpty)
            #expect(trace.step(.managerReported).isEmpty)
            #expect(trace.step(.battery(
                posture: .bothOut,
                key: .left,
                encoding: "integer",
                responds: true,
                valueClass: .number,
                level: .inRange
            )).isEmpty)
            #expect(trace.step(.mode(exists: true, byteSize: 4, current: 2, mask: 1, settable: true)).isEmpty)
            #expect(trace.effects == [.readAccess])
            #expect(trace.effects.contains(where: isDeviceTouch) == false)
            #expect(trace.state.battery.isEmpty)
            #expect(trace.state.wrote == false)
            #expect(trace.state.managerPrompts == nil)
        }
    }

    @Test func aPromptAtStepBMakesManagerPromptsNotMeasured() {
        var trace = Trace()
        _ = trace.step(.begin)
        _ = trace.step(.access(.notAsked))
        #expect(trace.state.phase == .gateClassic)
        #expect(trace.step(.classicReturned).isEmpty)
        #expect(trace.step(.continueAsked) == [.classicList(.main)])
        #expect(trace.step(.classicReturned).isEmpty)
        #expect(trace.state.phase == .answerClassic)
        let answered = trace.step(.prompt(.appeared))
        #expect(answered.isEmpty)
        #expect(trace.state.classicBeforeGrant == .prompted)
        #expect(trace.state.managerPrompts == .notMeasured)
        #expect(trace.state.phase == .done)
        #expect(trace.step(.continueAsked).isEmpty)
        #expect(trace.effects.contains(.startManager) == false)
        #expect(trace.effects.contains(.abandonManager) == false)
        #expect(trace.effects.contains(.compareIdentity) == false)
        #expect(trace.effects.contains(.readMode) == false)
        #expect(trace.effects.contains(where: isWrite) == false)
        #expect(trace.effects.contains(where: isRestore) == false)
        #expect(trace.effects.contains(where: isBattery) == false)
    }

    @Test func aManagerThatNeverReportsEndsAtTenSeconds() {
        #expect(EarbudsSection.managerLimitSeconds == 10)

        var trace = afterManagerStarted()
        #expect(trace.step(.waited(seconds: 9)).isEmpty)
        #expect(trace.state.phase == .awaitManager)
        #expect(trace.state.managerPrompts == nil)
        let due = trace.step(.waited(seconds: 1))
        #expect(due.first == .abandonManager)
        #expect(due.contains(.readBattery(posture: .bothOut, key: .left)))
        #expect(trace.state.managerPrompts == .notMeasured)
        #expect(trace.state.waited == 0)
        #expect(trace.state.phase == .battery)
        #expect(trace.effects.filter { $0 == .startManager }.count == 1)
        #expect(trace.effects.filter { $0 == .abandonManager }.count == 1)

        var reported = afterManagerStarted()
        _ = reported.step(.waited(seconds: 9))
        #expect(reported.step(.managerReported).isEmpty)
        #expect(reported.state.phase == .answerManager)
        #expect(reported.step(.waited(seconds: 5)).isEmpty)
        #expect(reported.effects.contains(.abandonManager) == false)
        #expect(reported.state.managerPrompts == nil)
        let hand = reported.step(.prompt(.stayedQuiet))
        #expect(hand.first == .abandonManager)
        #expect(reported.state.managerPrompts == .quiet)
    }

    @Test func theModeWriteIsRestoredWhenTheReadBackFails() {
        var failed = writable()
        #expect(failed.state.originalMode == 2)
        #expect(failed.state.targetMode == 1)
        #expect(failed.effects.contains(.writeMode(1)))
        #expect(failed.step(.writeFinished(ok: false)) == [.readModeBack])
        let restored = failed.step(.readBackFailed)
        #expect(restored == [.restoreMode(2)])
        #expect(failed.step(.restoreFinished).isEmpty)
        #expect(failed.state.restored)
        #expect(failed.state.phase == .gateWithdraw)
        #expect(failed.effects.filter(isRestore).count == 1)

        var differed = writable()
        _ = differed.step(.writeFinished(ok: true))
        #expect(differed.step(.readBack(matched: false)) == [.restoreMode(2)])
        #expect(differed.step(.readBackFailed).isEmpty)
        #expect(differed.effects.filter(isRestore).count == 1)
    }

    @Test func theModeWriteIsRestoredWhenTheReadBackTimesOut() {
        #expect(EarbudsSection.audioLimitSeconds == 2)

        var trace = writable()
        #expect(trace.step(.writeFinished(ok: true)) == [.readModeBack])
        #expect(trace.step(.waited(seconds: 1)).isEmpty)
        #expect(trace.state.phase == .awaitReadBack)
        let due = trace.step(.waited(seconds: 1))
        #expect(due == [.restoreMode(2)])
        #expect(trace.effects.filter(isRestore).count == 1)
        #expect(trace.step(.waited(seconds: 2)).isEmpty)
        #expect(trace.state.restoreTimedOut)
        #expect(trace.state.phase == .gateWithdraw)
        #expect(trace.effects.filter(isRestore).count == 1)
        #expect(trace.state.restored == false)

        var stalled = writable()
        #expect(stalled.step(.waited(seconds: 1)).isEmpty)
        #expect(stalled.state.phase == .awaitWrite)
        let gaveUp = stalled.step(.waited(seconds: 1))
        #expect(gaveUp == [.restoreMode(2)])
        #expect(stalled.effects.contains(.readModeBack) == false)
        #expect(stalled.effects.filter(isRestore).count == 1)
    }

    @Test func aMaskThatDisagreesWritesNothing() {
        #expect(EarbudsSection.maskAgrees(current: 2, mask: 0) == false)
        #expect(EarbudsSection.maskAgrees(current: 2, mask: 1) == true)
        #expect(EarbudsSection.maskAgrees(current: 3, mask: 1) == false)
        #expect(EarbudsSection.maskAgrees(current: 3, mask: 2) == true)
        #expect(EarbudsSection.maskAgrees(current: 1, mask: 0) == true)
        #expect(EarbudsSection.maskAgrees(current: 4, mask: 0) == false)
        #expect(EarbudsSection.maskAgrees(current: 4, mask: 4) == true)
        #expect(EarbudsSection.maskAgrees(current: 5, mask: 7) == false)
        #expect(EarbudsSection.replacement(current: 2, mask: 1) == 1)
        #expect(EarbudsSection.replacement(current: 1, mask: 0) == nil)

        var disagreed = atMode()
        let held = disagreed.step(.mode(exists: true, byteSize: 4, current: 2, mask: 0, settable: true))
        #expect(held.isEmpty)
        #expect(disagreed.state.maskAgrees == false)
        #expect(disagreed.state.wrote == false)
        #expect(disagreed.state.phase == .gateWithdraw)
        #expect(disagreed.effects.contains(where: isWrite) == false)
        #expect(disagreed.effects.contains(where: isRestore) == false)

        var clearBit = atMode()
        _ = clearBit.step(.mode(exists: true, byteSize: 4, current: 3, mask: 1, settable: true))
        #expect(clearBit.state.maskAgrees == false)
        #expect(clearBit.effects.contains(where: isWrite) == false)

        var noOther = atMode()
        _ = noOther.step(.mode(exists: true, byteSize: 4, current: 1, mask: 0, settable: true))
        #expect(noOther.state.maskAgrees == true)
        #expect(noOther.state.wrote == false)
        #expect(noOther.effects.contains(where: isWrite) == false)

        var wide = atMode()
        _ = wide.step(.mode(exists: true, byteSize: 8, current: 2, mask: 1, settable: true))
        #expect(wide.state.wrote == false)
        #expect(wide.effects.contains(where: isWrite) == false)
    }

    @Test func anEncodingOutsideTheTableBecomesOther() {
        #expect(EarbudsSection.ReturnType.decode("object") == .object)
        #expect(EarbudsSection.ReturnType.decode("integer") == .integer)
        #expect(EarbudsSection.ReturnType.decode("none") == .none)
        #expect(EarbudsSection.ReturnType.decode("other") == .other)
        #expect(EarbudsSection.ReturnType.decode("float") == .other)
        #expect(EarbudsSection.ReturnType.decode("c") == .other)
        #expect(EarbudsSection.ReturnType.decode("") == .other)
        #expect(EarbudsSection.ReturnType.decode("INTEGER") == .other)

        var trace = afterManagerQuiet()
        let stored = trace.step(.battery(
            posture: .bothOut,
            key: .left,
            encoding: "float",
            responds: true,
            valueClass: .number,
            level: .inRange
        ))
        #expect(stored == [.readBattery(posture: .bothOut, key: .right)])
        #expect(trace.state.battery.count == 1)
        #expect(trace.state.battery[0].returnType == .other)
        #expect(trace.state.battery[0].posture == .bothOut)
        #expect(trace.state.battery[0].key == .left)

        let ignored = trace.step(.battery(
            posture: .lidClosed,
            key: .single,
            encoding: "integer",
            responds: true,
            valueClass: .number,
            level: .zero
        ))
        #expect(ignored.isEmpty)
        #expect(trace.state.battery.count == 1)
    }

    @Test func classicCallsStayOnTheMainThreadAndHungAtFifteenSeconds() {
        #expect(EarbudsSection.classicThread == .main)
        #expect(EarbudsSection.classicLimitSeconds == 15)

        var trace = Trace()
        _ = trace.step(.begin)
        _ = trace.step(.access(.notAsked))
        #expect(trace.step(.continueAsked) == [.classicList(.main)])
        #expect(trace.step(.waited(seconds: 14)).isEmpty)
        #expect(trace.state.phase == .awaitClassic)
        #expect(trace.state.waited == 14)
        #expect(trace.step(.waited(seconds: 1)).isEmpty)
        #expect(trace.state.classicBeforeGrant == .hung)
        #expect(trace.state.phase == .done)
        #expect(trace.effects.contains(.startManager) == false)
        #expect(trace.step(.continueAsked).isEmpty)
        #expect(trace.step(.waited(seconds: 0)).isEmpty)
        #expect(trace.step(.waited(seconds: -2)).isEmpty)
    }

    @Test func theOrderIsAccessClassicManagerBatteryIdentityTimelineModeThenWithdraw() {
        #expect(EarbudsSection.batterySlots.count == 12)
        #expect(EarbudsSection.withdrawLimitSeconds == 60)
        #expect(EarbudsSection.withdrawEarlySeconds == 10)

        var trace = afterManagerQuiet()
        #expect(trace.state.phase == .battery)
        for slot in EarbudsSection.batterySlots {
            _ = trace.step(.battery(
                posture: slot.posture,
                key: slot.key,
                encoding: "integer",
                responds: false,
                valueClass: .other,
                level: .other
            ))
        }
        #expect(trace.state.battery.count == 12)
        #expect(trace.state.phase == .awaitIdentity)
        #expect(trace.effects.contains(.compareIdentity))
        #expect(trace.step(.identity(uidHasAddress: true, namesEqual: true, deviceClass: .headphones)).isEmpty)
        #expect(trace.state.deviceClass == .headphones)
        #expect(trace.state.phase == .timeline)
        _ = trace.step(.timeline(.sleep))
        _ = trace.step(.timeline(.wake))
        _ = trace.step(.timeline(.connect))
        _ = trace.step(.timeline(.disconnect))
        #expect(trace.state.timeline == [.sleep, .wake, .connect, .disconnect])
        #expect(trace.step(.timelineDone).isEmpty)
        #expect(trace.state.phase == .gateMode)
        #expect(trace.step(.continueAsked) == [.readMode])
        let wrote = trace.step(.mode(exists: true, byteSize: 4, current: 2, mask: 1, settable: true))
        #expect(wrote == [.writeMode(1)])
        #expect(trace.step(.writeFinished(ok: true)) == [.readModeBack])
        #expect(trace.step(.readBack(matched: true)) == [.restoreMode(2)])
        #expect(trace.step(.restoreFinished).isEmpty)
        #expect(trace.state.restored)
        #expect(trace.step(.continueAsked) == [.pollGrant])
        #expect(trace.state.phase == .watchingWithdraw)
        #expect(trace.step(.waited(seconds: 10)).isEmpty)
        #expect(trace.step(.grant(.denied)).isEmpty)
        #expect(trace.state.changedLive == true)
        #expect(trace.state.changedWithin == .w10s)
        #expect(trace.state.phase == .done)

        let access = trace.effects.firstIndex(of: .readAccess)
        let classic = trace.effects.firstIndex(of: .classicList(.main))
        let manager = trace.effects.firstIndex(of: .startManager)
        let battery = trace.effects.firstIndex(of: .readBattery(posture: .bothOut, key: .left))
        let identity = trace.effects.firstIndex(of: .compareIdentity)
        let mode = trace.effects.firstIndex(of: .readMode)
        let write = trace.effects.firstIndex(of: .writeMode(1))
        let restore = trace.effects.firstIndex(of: .restoreMode(2))
        let grant = trace.effects.firstIndex(of: .pollGrant)
        #expect(access != nil && classic != nil && manager != nil && battery != nil)
        #expect(identity != nil && mode != nil && write != nil && restore != nil && grant != nil)
        #expect(access! < classic!)
        #expect(classic! < manager!)
        #expect(manager! < battery!)
        #expect(battery! < identity!)
        #expect(identity! < mode!)
        #expect(mode! < write!)
        #expect(write! < restore!)
        #expect(restore! < grant!)

        var later = watching()
        _ = later.step(.waited(seconds: 11))
        #expect(later.step(.grant(.restricted)).isEmpty)
        #expect(later.state.changedWithin == .w60s)
        #expect(later.state.changedLive == true)

        var quiet = watching()
        _ = quiet.step(.waited(seconds: 59))
        #expect(quiet.state.phase == .watchingWithdraw)
        #expect(quiet.step(.waited(seconds: 1)).isEmpty)
        #expect(quiet.state.changedLive == false)
        #expect(quiet.state.changedWithin == EarbudsSection.Window.none)
        #expect(quiet.state.phase == .done)

        var quit = watching()
        #expect(quit.step(.appQuit).isEmpty)
        #expect(quit.state.appQuit)
        #expect(quit.state.phase == .done)
        #expect(quit.state.changedLive == nil)
    }
}

private struct Trace {
    var state = EarbudsSection.fresh()
    var effects: [EarbudsSection.Effect] = []

    mutating func step(_ event: EarbudsSection.Event) -> [EarbudsSection.Effect] {
        let (next, out) = EarbudsSection.reduce(state, event)
        state = next
        effects.append(contentsOf: out)
        return out
    }
}

private func isDeviceTouch(_ effect: EarbudsSection.Effect) -> Bool {
    switch effect {
    case .classicList, .startManager, .readBattery, .compareIdentity, .readMode, .writeMode, .readModeBack, .restoreMode:
        return true
    case .readAccess, .abandonManager, .pollGrant:
        return false
    }
}

private func isWrite(_ effect: EarbudsSection.Effect) -> Bool {
    if case .writeMode = effect { return true }
    return false
}

private func isRestore(_ effect: EarbudsSection.Effect) -> Bool {
    if case .restoreMode = effect { return true }
    return false
}

private func isBattery(_ effect: EarbudsSection.Effect) -> Bool {
    if case .readBattery = effect { return true }
    return false
}

private func afterManagerStarted() -> Trace {
    var trace = Trace()
    _ = trace.step(.begin)
    _ = trace.step(.access(.allowed))
    _ = trace.step(.continueAsked)
    _ = trace.step(.classicReturned)
    _ = trace.step(.prompt(.stayedQuiet))
    _ = trace.step(.continueAsked)
    return trace
}

private func afterManagerQuiet() -> Trace {
    var trace = afterManagerStarted()
    _ = trace.step(.managerReported)
    _ = trace.step(.prompt(.stayedQuiet))
    return trace
}

private func atMode() -> Trace {
    var trace = afterManagerQuiet()
    for slot in EarbudsSection.batterySlots {
        _ = trace.step(.battery(
            posture: slot.posture,
            key: slot.key,
            encoding: "none",
            responds: false,
            valueClass: .null,
            level: .other
        ))
    }
    _ = trace.step(.identity(uidHasAddress: false, namesEqual: false, deviceClass: .other))
    _ = trace.step(.timelineDone)
    _ = trace.step(.continueAsked)
    return trace
}

private func writable() -> Trace {
    var trace = atMode()
    _ = trace.step(.mode(exists: true, byteSize: 4, current: 2, mask: 1, settable: true))
    return trace
}

private func watching() -> Trace {
    var trace = writable()
    _ = trace.step(.writeFinished(ok: true))
    _ = trace.step(.readBack(matched: true))
    _ = trace.step(.restoreFinished)
    _ = trace.step(.continueAsked)
    return trace
}
