import Foundation
import Testing
import ZeusCore

@Suite("Earbud battery and listening mode")
struct EarbudStatusSourceTests {
    private let source = GuardedEarbudStatusSource()

    private func input(
        enabled: Bool = true,
        access: BluetoothAccess = .allowed,
        sessionActive: Bool = true,
        now: TimeInterval = 100,
        major: Int = ListeningModeRelease.verifiedMajor,
        minor: Int = ListeningModeRelease.verifiedMinor,
        book: EarbudBatteryBook = EarbudBatteryBook()
    ) -> EarbudStatusInput {
        EarbudStatusInput(
            enabled: enabled,
            access: access,
            sessionActive: sessionActive,
            now: now,
            releaseMajor: major,
            releaseMinor: minor,
            book: book
        )
    }

    @Test func missingBatteryKeysHideAndUnknownIsNotZero() {
        var missing = ScriptedEarbudProbe()
        missing.batteryResult = EarbudBatteryReading(routeOpen: false, values: [:], answering: [])
        missing.modeResult = ListeningModeSample(symbolPresent: false, byteSize: 0, rawMode: nil, rawMask: nil, bluetoothTransport: false)
        let closed = source.evaluate(input(), probe: &missing)
        #expect(closed.report.visibleParts.isEmpty)
        #expect(closed.report.levels.isEmpty)
        #expect(closed.report.mode == .hidden)
        #expect(missing.batteryCalls == 1)
        #expect(missing.writes == 0)

        var zeros = ScriptedEarbudProbe()
        zeros.batteryResult = EarbudBatteryReading(
            routeOpen: true,
            values: [.left: 0, .right: nil, .cradle: 255, .single: -1],
            answering: [.left, .right]
        )
        let report = source.evaluate(input(), probe: &zeros).report
        #expect(report.visibleParts == [.left, .right, .cradle])
        for part in report.visibleParts {
            #expect(EarbudLevelText.display(report.levels[part] ?? .unknown) == "unknown")
            #expect(report.levels[part]?.percent == nil)
        }
        #expect(!report.accessibilitySummary.contains("0 percent"))
        #expect(!report.accessibilitySummary.split(separator: " ").contains("0%"))
    }

    @Test func rawValuesOutsideOneToOneHundredNeverBecomeZero() {
        for raw in -20...255 {
            let level = EarbudLevelReading.interpret(raw)
            let text = EarbudLevelText.display(level)
            #expect(text != "0%")
            #expect(!text.contains("0 percent"))
            if let percent = level.percent {
                #expect((1...100).contains(percent))
                #expect(text == "\(percent)%")
            } else {
                #expect(text == "unknown")
            }
        }
        #expect(EarbudLevelReading.interpret(nil) == .unknown)
        #expect(EarbudLevelReading.interpret(1) == .fresh(1))
        #expect(EarbudLevelReading.interpret(100) == .fresh(100))
    }

    @Test func aHostileZeroStillReadsUnknown() {
        #expect(EarbudLevelText.display(.fresh(0)) == "unknown")
        #expect(EarbudLevelText.display(.lastKnown(0)) == "unknown")
        #expect(EarbudLevelText.display(.fresh(101)) == "unknown")
        #expect(EarbudLevelText.display(.lastKnown(-4)) == "unknown")
    }

    @Test func theSettingOffFailsClosedAndNeverTouchesTheProbe() {
        var probe = ScriptedEarbudProbe()
        probe.batteryResult = EarbudBatteryReading(routeOpen: true, values: [.left: 80], answering: [.left, .right])
        for access in [BluetoothAccess.notAsked, .allowed, .denied, .restricted] {
            var local = probe
            let evaluation = source.evaluate(input(enabled: false, access: access), probe: &local)
            #expect(local.batteryCalls == 0)
            #expect(local.modeCalls == 0)
            #expect(local.writes == 0)
            #expect(evaluation.report.consultedPrivateKeys == false)
            #expect(evaluation.report.visibleParts.isEmpty)
            #expect(evaluation.report.mode == .hidden)
            #expect(evaluation.book.memory.isEmpty)
        }
    }

    @Test func privateNamesStayBehindTheSetting() {
        #expect(EarbudPrivateSymbols.batteryKeyNames(settingEnabled: false, accessAllowed: true).isEmpty)
        #expect(EarbudPrivateSymbols.batteryKeyNames(settingEnabled: true, accessAllowed: false).isEmpty)
        #expect(EarbudPrivateSymbols.listeningModeSelectors(settingEnabled: false).isEmpty)
        let names = EarbudPrivateSymbols.batteryKeyNames(settingEnabled: true, accessAllowed: true)
        let selectors = EarbudPrivateSymbols.listeningModeSelectors(settingEnabled: true)
        #expect(names.count == 4)
        #expect(Set(names).count == 4)
        #expect(selectors.count == 2)
        #expect(Set(selectors).count == 2)
        for name in names {
            #expect(!name.isEmpty)
            #expect(!name.contains("0%"))
        }
    }

    @Test func privateNamesLiveOnlyInTheBatterySource() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let names = EarbudPrivateSymbols.batteryKeyNames(settingEnabled: true, accessAllowed: true)
        let selectors = EarbudPrivateSymbols.listeningModeSelectors(settingEnabled: true).map { String(format: "0x%x", $0) }
        let needles = names + selectors
        let sources = try swiftFiles(under: root.appendingPathComponent("Sources"))
        var hits: [String] = []
        for url in sources {
            let text = try String(contentsOf: url, encoding: .utf8)
            for needle in needles where text.contains(needle) {
                hits.append(url.path.replacingOccurrences(of: root.path + "/", with: "") + ":" + needle)
            }
        }
        let outside = hits.filter { !$0.hasPrefix("Sources/ZeusCore/Settings/Sections/Battery/") }
        #expect(outside.isEmpty, "\(outside)")
        #expect(!hits.isEmpty)
    }

    @Test func bluetoothNotAskedDoesNotReadPrivateKeys() {
        var probe = ScriptedEarbudProbe()
        let evaluation = source.evaluate(input(access: .notAsked), probe: &probe)
        #expect(probe.batteryCalls == 0)
        #expect(probe.modeCalls == 0)
        #expect(evaluation.report.consultedPrivateKeys == false)
        #expect(evaluation.report.levels.isEmpty)
    }

    @Test func aDeniedGrantHidesBatteryAndStillAllowsTheModeRoute() {
        var probe = ScriptedEarbudProbe()
        probe.modeResult = boundMode(raw: 1, mask: 3)
        let report = source.evaluate(input(access: .denied), probe: &probe).report
        #expect(probe.batteryCalls == 0)
        #expect(probe.modeCalls == 1)
        #expect(probe.keysSeen.isEmpty)
        #expect(report.levels.isEmpty)
        #expect(report.mode != .hidden)
    }

    @Test func anInactiveSessionReadsNothing() {
        var probe = ScriptedEarbudProbe()
        let evaluation = source.evaluate(input(sessionActive: false), probe: &probe)
        #expect(probe.batteryCalls == 0)
        #expect(probe.modeCalls == 0)
        #expect(evaluation.report.consultedPrivateKeys == false)
    }

    @Test func aFreshReadingReplacesMemoryAndAnInvalidPartDoesNot() {
        var book = EarbudBatteryBook()
        book = book.merging([.left: 80, .right: 70], now: 10)
        book = book.merging([.left: 0, .right: 75], now: 12)
        #expect(book.level(.left, now: 12) == .lastKnown(80))
        #expect(book.level(.right, now: 12) == .fresh(75))
        #expect(book.level(.left, now: 10 + EarbudBatteryBook.lastKnownLifetime) == .lastKnown(80))
        #expect(book.level(.left, now: 10 + EarbudBatteryBook.lastKnownLifetime + 0.001) == .unknown)
        #expect(book.level(.cradle, now: 12) == .unknown)
    }

    @Test func onePieceAndTwoPieceLayouts() {
        #expect(EarbudParts.layout(answering: [.left]) == [.left, .right, .cradle])
        #expect(EarbudParts.layout(answering: [.right, .cradle]) == [.left, .right, .cradle])
        #expect(EarbudParts.layout(answering: [.single]) == [.single])
        #expect(EarbudParts.layout(answering: [.single, .left]) == [.left, .right, .cradle])
        #expect(EarbudParts.layout(answering: []) == [])
        #expect(EarbudParts.layout(answering: [.cradle]) == [])
    }

    @Test func theSourceShowsFreshLevelsAndHidesAMissingPart() {
        var probe = ScriptedEarbudProbe()
        probe.batteryResult = EarbudBatteryReading(
            routeOpen: true,
            values: [.left: 80, .right: nil],
            answering: [.left, .right]
        )
        probe.modeResult = ListeningModeSample(symbolPresent: false, byteSize: 0, rawMode: nil, rawMask: nil, bluetoothTransport: false)
        let evaluation = source.evaluate(input(), probe: &probe)
        #expect(evaluation.report.visibleParts == [.left, .right, .cradle])
        #expect(evaluation.report.levels[.left] == .fresh(80))
        #expect(evaluation.report.levels[.right] == .unknown)
        #expect(evaluation.report.levels[.cradle] == .unknown)
        #expect(evaluation.report.mode == .hidden)
        #expect(probe.keysSeen == EarbudPrivateSymbols.batteryKeyNames(settingEnabled: true, accessAllowed: true))
        #expect(!evaluation.report.accessibilitySummary.contains("0 percent"))
        #expect(!evaluation.report.accessibilitySummary.split(separator: " ").contains("0%"))
    }

    @Test func aReleaseBelowTheFloorHidesTheModeAndDoesNotWrite() {
        var probe = ScriptedEarbudProbe()
        probe.modeResult = boundMode(raw: 2, mask: 3)
        let below = source.evaluate(input(major: 27, minor: 1), probe: &probe)
        #expect(probe.modeCalls == 0)
        #expect(below.report.mode == .hidden)
        var editor = ScriptedEarbudProbe()
        let commit = ListeningModeEditor.set(.noiseCancelling, gateOpen: true, releaseMajor: 15, releaseMinor: 0, probe: &editor)
        #expect(commit == .hidden)
        #expect(editor.writes == 0)
        #expect(editor.modeCalls == 0)
    }

    @Test func modeSymbolsThatDoNotBindStayHidden() {
        let samples = [
            ListeningModeSample(symbolPresent: false, byteSize: 4, rawMode: 1, rawMask: 3, bluetoothTransport: true),
            ListeningModeSample(symbolPresent: true, byteSize: 8, rawMode: 1, rawMask: 3, bluetoothTransport: true),
            ListeningModeSample(symbolPresent: true, byteSize: 4, rawMode: 9, rawMask: 3, bluetoothTransport: true),
            ListeningModeSample(symbolPresent: true, byteSize: 4, rawMode: 2, rawMask: 2, bluetoothTransport: true),
            ListeningModeSample(symbolPresent: true, byteSize: 4, rawMode: 1, rawMask: 3, bluetoothTransport: false),
            ListeningModeSample(symbolPresent: true, byteSize: 4, rawMode: 1, rawMask: nil, bluetoothTransport: true),
            ListeningModeSample(symbolPresent: true, byteSize: 4, rawMode: 1, rawMask: 0, bluetoothTransport: true),
        ]
        for sample in samples {
            var probe = ScriptedEarbudProbe()
            probe.modeResult = sample
            probe.batteryResult = EarbudBatteryReading(routeOpen: false, values: [:], answering: [])
            let row = source.evaluate(input(), probe: &probe).report.mode
            #expect(row == .hidden, "bound \(sample)")
        }
    }

    @Test func aTrustedMaskShowsOnlyTheModesTheDeviceHas() {
        #expect(ListeningModeCode.mode(1) == .off)
        #expect(ListeningModeCode.mode(2) == .noiseCancelling)
        #expect(ListeningModeCode.mode(3) == .transparency)
        #expect(ListeningModeCode.mode(4) == .adaptive)
        #expect(ListeningModeCode.mode(0) == nil)
        #expect(ListeningModeCode.mode(5) == nil)
        #expect(ListeningModeCode.mode(UInt32.max) == nil)
        #expect(ListeningModeCode.code(.off) == 1)
        #expect(ListeningModeCode.code(.adaptive) == 4)
        var probe = ScriptedEarbudProbe()
        probe.batteryResult = EarbudBatteryReading(routeOpen: false, values: [:], answering: [])
        probe.modeResult = boundMode(raw: 4, mask: 7)
        guard case .shown(let current, let choices) = source.evaluate(input(), probe: &probe).report.mode else {
            Issue.record("adaptive row hidden")
            return
        }
        #expect(current == .adaptive)
        #expect(choices.map(\.mode) == [.off, .noiseCancelling, .transparency])
        #expect(!choices.map(\.mode).contains(.adaptive))
    }

    @Test func readBackAfterEverySetShowsTheValueThatWasRead() {
        var probe = ScriptedEarbudProbe()
        probe.modeResult = boundMode(raw: 1, mask: 3)
        probe.writeRaw = 2
        let commit = ListeningModeEditor.set(.noiseCancelling, gateOpen: true, releaseMajor: 27, releaseMinor: 2, probe: &probe)
        #expect(commit == .shown(.noiseCancelling))
        #expect(probe.writes == 1)
        #expect(probe.modeCalls >= 2)
    }

    @Test func aReadBackThatDiffersShowsTheReadValueAndDoesNotWriteAgain() {
        var probe = ScriptedEarbudProbe()
        probe.modeResult = boundMode(raw: 1, mask: 3)
        probe.writeRaw = 1
        let commit = ListeningModeEditor.set(.noiseCancelling, gateOpen: true, releaseMajor: 27, releaseMinor: 2, probe: &probe)
        #expect(commit == .refused(asked: .noiseCancelling, read: .off))
        #expect(probe.writes == 1)
    }

    @Test func aClosedGateAndACurrentModeDoNotWrite() {
        var closed = ScriptedEarbudProbe()
        #expect(ListeningModeEditor.set(.off, gateOpen: false, releaseMajor: 27, releaseMinor: 2, probe: &closed) == .hidden)
        #expect(closed.writes == 0)
        #expect(closed.modeCalls == 0)
        var current = ScriptedEarbudProbe()
        current.modeResult = boundMode(raw: 2, mask: 3)
        #expect(ListeningModeEditor.set(.noiseCancelling, gateOpen: true, releaseMajor: 27, releaseMinor: 2, probe: &current) == .unchanged)
        #expect(current.writes == 0)
        var adaptive = ScriptedEarbudProbe()
        adaptive.modeResult = boundMode(raw: 1, mask: 3)
        #expect(ListeningModeEditor.set(.adaptive, gateOpen: true, releaseMajor: 27, releaseMinor: 2, probe: &adaptive) == .unchanged)
        #expect(adaptive.writes == 0)
    }

    @Test func theEarbudSettingIsOffByDefaultAndImportCannotTurnItOn() {
        #expect(BatteryEarbudSetting.defaultEnabled == false)
        #expect(BatteryEarbudSetting.key == "battery.earbuds")
        #expect(BatteryEarbudSetting.enabled(requested: true, origin: .importFile, currently: false) == false)
        #expect(BatteryEarbudSetting.enabled(requested: false, origin: .importFile, currently: true) == false)
        #expect(BatteryEarbudSetting.enabled(requested: true, origin: .person, currently: false) == true)
        #expect(BatteryEarbudSetting.enabled(requested: true, origin: .restore, currently: false) == true)
        #expect(BatteryLightsSetting.key == "lights.battery")
        #expect(BatteryLightsSetting.defaultEnabled == true)
    }

    private func boundMode(raw: UInt32, mask: UInt32) -> ListeningModeSample {
        ListeningModeSample(symbolPresent: true, byteSize: 4, rawMode: raw, rawMask: mask, bluetoothTransport: true)
    }

    private func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }
}

@Suite("Earbud consent")
struct EarbudConsentTests {
    private func reduce(_ state: EarbudConsent.State, _ event: EarbudConsent.Event) -> (EarbudConsent.State, [EarbudConsent.Effect]) {
        EarbudConsent.reduce(state, event)
    }

    @Test func theBluetoothPromptAppearsOnlyWhenTheUserTurnsItOn() {
        for access in [BluetoothAccess.notAsked, .allowed, .denied, .restricted] {
            for enabled in [false, true] {
                let (_, effects) = reduce(.init(), .restore(enabled: enabled, access: access))
                #expect(!effects.contains(.promptForBluetooth))
            }
        }
        let (prompting, prompt) = reduce(.init(), .userSet(enabled: true, access: .notAsked))
        #expect(prompting.phase == .prompting)
        #expect(prompt == [.promptForBluetooth])
        let (again, second) = reduce(prompting, .userSet(enabled: true, access: .notAsked))
        #expect(again.phase == .prompting)
        #expect(second.isEmpty)
        let (watching, read) = reduce(prompting, .accessAnswered(.allowed))
        #expect(watching.phase == .watching)
        #expect(read == [.readStatus])
        #expect(!read.contains(.promptForBluetooth))
    }

    @Test func allowedDeniedAndOffDoNotPrompt() {
        let (watching, read) = reduce(.init(), .userSet(enabled: true, access: .allowed))
        #expect(watching.phase == .watching)
        #expect(read == [.readStatus])
        let (denied, none) = reduce(.init(), .userSet(enabled: true, access: .denied))
        #expect(denied.phase == .denied)
        #expect(none.isEmpty)
        let (restricted, quiet) = reduce(.init(), .userSet(enabled: true, access: .restricted))
        #expect(restricted.phase == .denied)
        #expect(quiet.isEmpty)
        let (off, stopped) = reduce(watching, .userSet(enabled: false, access: .allowed))
        #expect(off.phase == .off)
        #expect(stopped == [.stopWatching])
        #expect(!stopped.contains(.promptForBluetooth))
    }

    @Test func aStoredOnValueWaitsInsteadOfPrompting() {
        let (waiting, effects) = reduce(.init(), .restore(enabled: true, access: .notAsked))
        #expect(waiting.phase == .waiting)
        #expect(effects.isEmpty)
        let (prompting, prompt) = reduce(waiting, .userSet(enabled: true, access: .notAsked))
        #expect(prompt == [.promptForBluetooth])
        #expect(prompting.phase == .prompting)
    }

    @Test func aLateAnswerAfterTheSessionLeavesIsDropped() {
        let (prompting, _) = reduce(.init(), .userSet(enabled: true, access: .notAsked))
        let (paused, stopped) = reduce(prompting, .session(active: false, access: .notAsked))
        #expect(paused.phase == .paused)
        #expect(stopped == [.stopWatching])
        let (still, late) = reduce(paused, .accessAnswered(.allowed))
        #expect(still.phase == .paused)
        #expect(late.isEmpty)
        let (back, read) = reduce(paused, .session(active: true, access: .notAsked))
        #expect(back.phase == .waiting)
        #expect(read.isEmpty)
    }

    @Test func returningWithAGrantReadsAndDoesNotPrompt() {
        let (watching, _) = reduce(.init(), .restore(enabled: true, access: .allowed))
        #expect(watching.phase == .watching)
        let (paused, _) = reduce(watching, .session(active: false, access: .allowed))
        let (back, effects) = reduce(paused, .session(active: true, access: .allowed))
        #expect(back.phase == .watching)
        #expect(effects == [.readStatus])
    }

    @Test func aMissingRouteFailsClosed() {
        let (watching, _) = reduce(.init(), .userSet(enabled: true, access: .allowed))
        let (closed, effects) = reduce(watching, .routeChecked(open: false))
        #expect(closed.phase == .unavailable)
        #expect(effects == [.stopWatching])
        let (open, read) = reduce(closed, .routeChecked(open: true))
        #expect(open.phase == .watching)
        #expect(read == [.readStatus])
    }

    @Test func turningOffFromEveryPhaseStopsWithoutPrompting() {
        let phases: [EarbudConsent.Phase] = [.off, .waiting, .prompting, .denied, .watching, .unavailable, .paused]
        for phase in phases {
            let (_, effects) = reduce(.init(phase: phase), .userSet(enabled: false, access: .allowed))
            #expect(!effects.contains(.promptForBluetooth))
            #expect(!effects.contains(.readStatus))
            if phase == .off {
                #expect(effects.isEmpty)
            } else {
                #expect(effects == [.stopWatching])
            }
        }
    }
}

private struct ScriptedEarbudProbe: EarbudProbe {
    var batteryCalls = 0
    var modeCalls = 0
    var writes = 0
    var keysSeen: [String] = []
    var selectorsSeen: [UInt32] = []
    var batteryResult = EarbudBatteryReading(routeOpen: true, values: [.left: 50], answering: [.left])
    var modeResult = ListeningModeSample(symbolPresent: true, byteSize: 4, rawMode: 1, rawMask: 3, bluetoothTransport: true)
    var writeRaw: UInt32?

    mutating func battery(keys: [String]) -> EarbudBatteryReading {
        batteryCalls += 1
        keysSeen = keys
        return batteryResult
    }

    mutating func listeningMode(selectors: [UInt32]) -> ListeningModeSample {
        modeCalls += 1
        selectorsSeen = selectors
        return modeResult
    }

    mutating func writeListeningMode(_ mode: ListeningMode, selectors: [UInt32]) -> ListeningModeSample {
        writes += 1
        selectorsSeen = selectors
        guard let writeRaw else { return modeResult }
        var sample = modeResult
        sample.rawMode = writeRaw
        modeResult = sample
        return sample
    }
}
