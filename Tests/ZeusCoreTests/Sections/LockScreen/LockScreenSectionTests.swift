import Foundation
import Testing
@testable import ZeusCore

/// Lock Screen settings. Every control is off until the owner turns it on, and a failure hides the card.
@Suite struct LockScreenSectionTests {
    private static let allowedLogs: Set<String> = [
        "lock-screen hidden setting-off",
        "lock-screen hidden not-locked",
        "lock-screen hidden symbol-missing",
        "lock-screen hidden call-failed",
        "lock-screen hidden no-playback",
    ]

    // MARK: Observation

    @Test func observationStartsUnknown() {
        let machine = LockObservationMachine()
        #expect(machine.state == .unknown)
        #expect(LockObservation.allCases == [.unknown, .unlocked, .locking, .locked, .unlocking])
    }

    @Test func everyObservationEventHasOneGuardedNextState() {
        let expected: [LockObservation: [LockObservationEvent: LockObservation]] = [
            .unknown: [
                .sawUnknown: .unknown, .sawUnlocked: .unlocked, .sawLocked: .locked,
                .beganLocking: .locking, .beganUnlocking: .unlocking, .cancelled: .unknown,
            ],
            .unlocked: [
                .sawUnknown: .unknown, .sawUnlocked: .unlocked, .sawLocked: .locked,
                .beganLocking: .locking, .beganUnlocking: .unlocked, .cancelled: .unlocked,
            ],
            .locking: [
                .sawUnknown: .unknown, .sawUnlocked: .unlocked, .sawLocked: .locked,
                .beganLocking: .locking, .beganUnlocking: .unlocking, .cancelled: .unlocked,
            ],
            .locked: [
                .sawUnknown: .unknown, .sawUnlocked: .unlocked, .sawLocked: .locked,
                .beganLocking: .locked, .beganUnlocking: .unlocking, .cancelled: .locked,
            ],
            .unlocking: [
                .sawUnknown: .unknown, .sawUnlocked: .unlocked, .sawLocked: .locked,
                .beganLocking: .locking, .beganUnlocking: .unlocking, .cancelled: .locked,
            ],
        ]
        #expect(expected.count == LockObservation.allCases.count)
        for state in LockObservation.allCases {
            for event in LockObservationEvent.allCases {
                let next = LockObservationMachine.step(state, event)
                #expect(next == expected[state]?[event], "\(state) +\(event) -> \(next)")
                var machine = LockObservationMachine(state: state)
                machine.handle(event)
                #expect(machine.state == next)
            }
        }
    }

    @Test func aLostReadingReturnsToUnknownFromEveryState() {
        for state in LockObservation.allCases {
            #expect(LockObservationMachine.step(state, .sawUnknown) == .unknown)
        }
    }

    @Test func cancellingALockReturnsUnlockedAndCancellingAnUnlockStaysLocked() {
        #expect(LockObservationMachine.step(.locking, .cancelled) == .unlocked)
        #expect(LockObservationMachine.step(.unlocking, .cancelled) == .locked)
        #expect(LockObservationMachine.step(.locked, .cancelled) == .locked)
        #expect(LockObservationMachine.step(.unlocked, .cancelled) == .unlocked)
    }

    @Test func walksOfThreeEventsStayInsideTheFiveStates() {
        let events = LockObservationEvent.allCases
        for start in LockObservation.allCases {
            for first in events {
                for second in events {
                    for third in events {
                        var state = start
                        for event in [first, second, third] {
                            state = LockObservationMachine.step(state, event)
                            #expect(LockObservation.allCases.contains(state))
                        }
                    }
                }
            }
        }
    }

    // MARK: Settings

    @Test func everyLockScreenSettingIsOffByDefault() {
        let settings = LockScreenSettings.off
        #expect(settings.playerCard == false)
        #expect(settings.lockSound == .off)
        #expect(settings.unlockSound == .off)
        #expect(settings.soundLevel == .off)
        #expect(settings.soundLevel.gain == 0)
        #expect(LockScreenSettingKey.all == [
            "lockScreen.playerCard", "lockScreen.lockSound", "lockScreen.unlockSound", "lockScreen.soundLevel",
        ])
        #expect(Set(LockScreenSettingKey.all).count == LockScreenSettingKey.all.count)
    }

    @Test func anImportOrAMissingStoreCannotTurnAnythingOn() {
        for origin in [LockScreenOrigin.imported, .absent] {
            let settings = LockScreenSettings.resolve(
                playerCard: true, lockSound: "Gentle", unlockSound: "Listening", soundLevel: "Loud", origin: origin
            )
            #expect(settings == .off)
        }
        let missing = LockScreenSettings.resolve(
            playerCard: nil, lockSound: nil, unlockSound: nil, soundLevel: nil, origin: .owner
        )
        #expect(missing == .off)
    }

    @Test func theOwnerCanTurnOnOnlyKnownValues() {
        let settings = LockScreenSettings.resolve(
            playerCard: true, lockSound: "Gentle", unlockSound: "To-do", soundLevel: "Quiet", origin: .owner
        )
        #expect(settings.playerCard)
        #expect(settings.lockSound.fileName == "success_gentle.m4a")
        #expect(settings.unlockSound.fileName == "todo_check.m4a")
        #expect(settings.soundLevel == .quiet)
        #expect(settings.soundLevel.gain == 0.35)
    }

    @Test(arguments: ["", " ", "off", "OFF", "Gentle ", "gentle", "Listening\n", "success_gentle.m4a", "Glass"])
    func anUnknownSoundOrLevelFailsClosed(_ stored: String) {
        let settings = LockScreenSettings.resolve(
            playerCard: true, lockSound: stored, unlockSound: stored, soundLevel: stored, origin: .owner
        )
        #expect(settings.playerCard)
        #expect(settings.lockSound == .off)
        #expect(settings.unlockSound == .off)
        #expect(settings.soundLevel == .off)
    }

    @Test func loudIsALevelAndNotASoundName() {
        let settings = LockScreenSettings.resolve(
            playerCard: false, lockSound: "Loud", unlockSound: "Quiet", soundLevel: "Loud", origin: .owner
        )
        #expect(settings.lockSound == .off)
        #expect(settings.unlockSound == .off)
        #expect(settings.soundLevel == .loud)
        #expect(settings.playerCard == false)
    }

    @Test func quietIsSofterThanLoudAndOffIsSilent() {
        #expect(LockScreenSoundLevel.off.gain == 0)
        #expect(LockScreenSoundLevel.quiet.gain > 0)
        #expect(LockScreenSoundLevel.quiet.gain < LockScreenSoundLevel.loud.gain)
        #expect(LockScreenSoundLevel.loud.gain == 1)
        #expect(LockScreenSoundLevel.resolve("Quiet") == .quiet)
        #expect(LockScreenSoundLevel.resolve("Loud") == .loud)
        #expect(LockScreenSoundLevel.resolve("quiet") == .off)
        #expect(LockScreenSoundLevel.resolve(nil) == .off)
    }

    @Test func soundChoicesAreOriginalFilesAlreadyInTheCatalog() throws {
        let root = try repositoryRoot()
        let catalog = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/Sound/SoundCatalog.swift"), encoding: .utf8)
        let titles = LockScreenSoundOption.all.map(\.title)
        #expect(titles == ["Off", "Gentle", "Listening", "Stopped listening", "To-do"])
        for option in LockScreenSoundOption.all {
            guard let file = option.fileName else {
                #expect(option == .off)
                continue
            }
            #expect(!file.contains("/"))
            #expect(!file.contains("\\"))
            #expect(file.unicodeScalars.allSatisfy { $0 != "\0" })
            let stem = String(file.split(separator: ".").first ?? "")
            #expect(catalog.contains("file: \"\(stem)\""))
            let url = root.appendingPathComponent("Sources/Zeus/Sounds").appendingPathComponent(file)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func lockScreenKeysStayOutOfTheExistingKeyList() throws {
        let shell = try String(contentsOf: repositoryRoot().appendingPathComponent("Sources/ZeusCore/Settings/GlassSettingsShell.swift"), encoding: .utf8)
        for key in LockScreenSettingKey.all {
            #expect(!shell.contains("\"\(key)\""))
        }
    }

    // MARK: Card

    @Test func missingLockScreenSymbolStaysHidden() {
        var session = LockScreenSession(settings: cardOn())
        var calls = 0
        session.handle(.sawUnlocked, playback: .playing, space: { _ in
            calls += 1
            return .shown
        }, soundFileExists: { _ in true })
        session.handle(.beganLocking, playback: .playing, space: { _ in .shown }, soundFileExists: { _ in true })
        let effects = session.handle(.sawLocked, playback: .playing, space: { _ in
            calls += 1
            return .symbolMissing
        }, soundFileExists: { _ in true })
        #expect(calls == 1)
        #expect(session.spaceAttempts == 1)
        #expect(session.surface.visible == false)
        #expect(session.surface.windowID == nil)
        #expect(session.surface.word == nil)
        #expect(session.surface.log == "lock-screen hidden symbol-missing")
        #expect(session.surface.controlCount == 0)
        #expect(session.surface.acceptsCommands == false)
        #expect(effects.contains(where: { if case .open = $0 { return true }; return false }) == false)
        #expect(session.press("play") == false)
        #expect(session.commands.isEmpty)
    }

    @Test func aFailedPrivateCallShowsNothingAndLogsOnlyTheReason() {
        let session = locked(space: { _ in .callFailed })
        #expect(session.surface.visible == false)
        #expect(session.surface.log == "lock-screen hidden call-failed")
        #expect(Self.allowedLogs.contains(session.surface.log ?? ""))
        #expect(session.ledger.openID == nil)
        #expect(session.ledger.retired.count == 1)
    }

    @Test func theCardStaysHiddenWhenTheSettingIsOffOrTheSessionIsNotLocked() {
        var off = LockScreenSession()
        var calls = 0
        off.handle(.sawLocked, playback: .playing, space: { _ in
            calls += 1
            return .shown
        }, soundFileExists: { _ in true })
        #expect(calls == 0)
        #expect(off.surface.log == "lock-screen hidden setting-off")
        #expect(off.surface.visible == false)

        for event in [LockObservationEvent.sawUnknown, .sawUnlocked, .beganLocking, .beganUnlocking] {
            var session = LockScreenSession(settings: cardOn())
            session.handle(.sawUnlocked, playback: .playing, space: { _ in .shown }, soundFileExists: { _ in true })
            if event != .sawUnlocked {
                session.handle(event, playback: .playing, space: { _ in .shown }, soundFileExists: { _ in true })
            }
            #expect(session.observation != .locked)
            #expect(session.surface.visible == false)
            #expect(session.spaceAttempts == 0)
        }
    }

    @Test func nothingPlayingDoesNotOpenAPrivateSpace() {
        var session = LockScreenSession(settings: cardOn())
        session.handle(.sawLocked, playback: .none, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(session.spaceAttempts == 0)
        #expect(session.surface.visible == false)
        #expect(session.surface.log == "lock-screen hidden no-playback")
    }

    @Test func aShownCardIsReadOnlyPlayingOrPausedAndOpensANewWindowEachLock() {
        var session = LockScreenSession(settings: cardOn())
        session.handle(.sawUnlocked, playback: .playing, space: { _ in .shown }, soundFileExists: { _ in true })
        session.handle(.beganLocking, playback: .playing, space: { _ in .shown }, soundFileExists: { _ in true })
        session.handle(.sawLocked, playback: .playing, space: { _ in .shown }, soundFileExists: { _ in true })
        let first = session.surface.windowID
        #expect(session.surface.visible)
        #expect(session.surface.word == "Playing")
        #expect(session.surface.controlCount == 0)
        #expect(session.surface.acceptsCommands == false)
        #expect(session.surface.log == nil)
        let inside = LockScreenPointer(x: 10, y: 10)
        #expect(session.hit(inside) == .inertCard)
        #expect(session.press("next") == false)
        #expect(session.press("pause") == false)
        #expect(session.press("unlock") == false)
        #expect(session.commands.isEmpty)

        session.handle(.sawLocked, playback: .paused, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(session.surface.windowID == first)
        #expect(session.surface.word == "Paused")
        #expect(session.spaceAttempts == 1)

        session.handle(.beganUnlocking, playback: .paused, space: { _ in .shown }, soundFileExists: { _ in true })
        session.handle(.sawUnlocked, playback: .paused, space: { _ in .shown }, soundFileExists: { _ in true })
        session.handle(.sawLocked, playback: .playing, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(session.surface.windowID != first)
        #expect(session.ledger.retired == [first!])
        #expect(session.spaceAttempts == 2)
    }

    @Test func unlockDoesNotSwallowTheNextClick() {
        var session = locked(space: { _ in .shown }, playback: .playing)
        let covered = LockScreenPointer(x: LockScreenCardBox.standard.x + 1, y: LockScreenCardBox.standard.y + 1)
        #expect(session.hit(covered) == .inertCard)
        let closed = session.handle(.beganUnlocking, playback: .playing, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(session.observation == .unlocking)
        #expect(session.surface.visible == false)
        #expect(session.surface.windowID == nil)
        #expect(closed.contains(.close(id: 1)))
        #expect(session.hit(covered) == .session)
        #expect(session.hit(LockScreenPointer(x: -10, y: -10)) == .session)
        session.handle(.sawUnlocked, playback: .playing, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(session.observation == .unlocked)
        #expect(session.hit(covered) == .session)
        #expect(session.press("play") == false)
        #expect(session.commands.isEmpty)
        #expect(session.surface.controlCount == 0)
    }

    @Test func pointsOutsideTheCardAndBrokenPointsReachTheSession() {
        let session = locked(space: { _ in .shown }, playback: .paused)
        let box = LockScreenCardBox.standard
        #expect(session.hit(LockScreenPointer(x: box.x, y: box.y)) == .inertCard)
        #expect(session.hit(LockScreenPointer(x: box.x + box.width - 0.1, y: box.y + box.height - 0.1)) == .inertCard)
        #expect(session.hit(LockScreenPointer(x: box.x + box.width, y: box.y)) == .session)
        #expect(session.hit(LockScreenPointer(x: box.x, y: box.y + box.height)) == .session)
        for point in [
            LockScreenPointer(x: -1, y: 0),
            LockScreenPointer(x: .nan, y: 0),
            LockScreenPointer(x: 0, y: .infinity),
            LockScreenPointer(x: -.infinity, y: .nan),
        ] {
            #expect(session.hit(point) == .session)
        }
    }

    @Test func turningTheCardOffWhileLockedClosesTheWindow() {
        var session = locked(space: { _ in .shown }, playback: .playing)
        let id = session.surface.windowID
        let effects = session.replaceSettings(.off, playback: .playing, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(id == 1)
        #expect(effects.contains(.close(id: 1)))
        #expect(session.surface.visible == false)
        #expect(session.surface.log == "lock-screen hidden setting-off")
        #expect(session.hit(LockScreenPointer(x: 10, y: 10)) == .session)
    }

    @Test func soundsPlayOnlyOnAFinishedLockOrUnlockAndFailClosed() {
        var session = LockScreenSession(settings: LockScreenSettings.resolve(
            playerCard: false, lockSound: "Gentle", unlockSound: "Listening", soundLevel: "Loud", origin: .owner
        ))
        session.handle(.sawUnlocked, playback: .none, space: { _ in .shown }, soundFileExists: { _ in true })
        let locking = session.handle(.beganLocking, playback: .none, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(locking.contains(where: { if case .play = $0 { return true }; return false }) == false)
        let locked = session.handle(.sawLocked, playback: .none, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(locked.contains(.play(LockScreenCue(fileName: "success_gentle.m4a", gain: 1, moment: .lock))))
        let unlocking = session.handle(.beganUnlocking, playback: .none, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(unlocking.contains(where: { if case .play = $0 { return true }; return false }) == false)
        let unlocked = session.handle(.sawUnlocked, playback: .none, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(unlocked.contains(.play(LockScreenCue(fileName: "listen_start.m4a", gain: 1, moment: .unlock))))

        var quiet = LockScreenSession(settings: LockScreenSettings.resolve(
            playerCard: false, lockSound: "To-do", unlockSound: "Stopped listening", soundLevel: "Quiet", origin: .owner
        ))
        quiet.handle(.sawUnlocked, playback: .none, space: { _ in .shown }, soundFileExists: { _ in true })
        let cue = quiet.handle(.sawLocked, playback: .none, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(cue.contains(.play(LockScreenCue(fileName: "todo_check.m4a", gain: 0.35, moment: .lock))))

        var missing = LockScreenSession(settings: LockScreenSettings.resolve(
            playerCard: false, lockSound: "Gentle", unlockSound: "Off", soundLevel: "Loud", origin: .owner
        ))
        missing.handle(.sawUnlocked, playback: .none, space: { _ in .shown }, soundFileExists: { _ in false })
        let silent = missing.handle(.sawLocked, playback: .none, space: { _ in .shown }, soundFileExists: { _ in false })
        #expect(silent.contains(where: { if case .play = $0 { return true }; return false }) == false)

        var discovered = LockScreenSession(settings: LockScreenSettings.resolve(
            playerCard: false, lockSound: "Gentle", unlockSound: "Listening", soundLevel: "Loud", origin: .owner
        ))
        let foundLocked = discovered.handle(.sawLocked, playback: .none, space: { _ in .shown }, soundFileExists: { _ in true })
        #expect(foundLocked.contains(where: { if case .play = $0 { return true }; return false }) == false)
    }

    @Test func anOffSoundOrAnOffLevelPlaysNothing() {
        for settings in [
            LockScreenSettings.resolve(playerCard: false, lockSound: "Off", unlockSound: "Gentle", soundLevel: "Loud", origin: .owner),
            LockScreenSettings.resolve(playerCard: false, lockSound: "Gentle", unlockSound: "Off", soundLevel: "Off", origin: .owner),
        ] {
            var session = LockScreenSession(settings: settings)
            session.handle(.sawUnlocked, playback: .none, space: { _ in .shown }, soundFileExists: { _ in true })
            let locked = session.handle(.sawLocked, playback: .none, space: { _ in .shown }, soundFileExists: { _ in true })
            let playedLock = locked.contains { if case .play(let cue) = $0 { return cue.moment == .lock }; return false }
            #expect(playedLock == false)
        }
    }

    @Test func shownCardsAndLogsStayInsideTheClosedSet() {
        let sounds = ["Off", "Gentle"]
        let levels = ["Off", "Quiet", "Loud"]
        let playbacks = [LockScreenPlayback.none, .playing, .paused]
        let answers = [LockScreenSpaceAnswer.shown, .symbolMissing, .callFailed]
        let words: Set<String?> = [nil, "Playing", "Paused"]
        for player in [false, true] {
            for lockSound in sounds {
                for unlockSound in sounds {
                    for level in levels {
                        let settings = LockScreenSettings.resolve(
                            playerCard: player, lockSound: lockSound, unlockSound: unlockSound, soundLevel: level, origin: .owner
                        )
                        for playback in playbacks {
                            for answer in answers {
                                for exists in [false, true] {
                                    var session = LockScreenSession(settings: settings)
                                    session.handle(.sawUnlocked, playback: playback, space: { _ in answer }, soundFileExists: { _ in exists })
                                    let effects = session.handle(.sawLocked, playback: playback, space: { _ in answer }, soundFileExists: { _ in exists })
                                    assertClosed(session, effects: effects, playback: playback, answer: answer)
                                    let left = session.handle(.sawUnlocked, playback: playback, space: { _ in answer }, soundFileExists: { _ in exists })
                                    assertClosed(session, effects: left, playback: playback, answer: answer)
                                    #expect(words.contains(session.surface.word))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Page

    @Test func thePageShowsLoadingEmptyAndErrorWithoutAControlThatBypassesTheLock() {
        let loading = page(loaded: false)
        #expect(loading.phase == .loading)
        #expect(loading.preview.body == .loading)
        #expect(loading.preview.accessibilityLabel == LockScreenCopy.loading)
        #expect(loading.controls.isEmpty)

        let empty = page(settings: .off)
        #expect(empty.phase == .empty)
        #expect(empty.preview.controlCount == 0)
        if case .empty(let text) = empty.preview.body {
            #expect(text == LockScreenCopy.empty)
        } else {
            Issue.record("expected an empty preview")
        }

        var on = cardOn()
        on.lockSound = LockScreenSoundOption.resolve("Gentle")
        let failed = page(settings: on, space: .symbolMissing)
        #expect(failed.phase == .unavailable(LockScreenCopy.unavailable))
        #expect(failed.controls.count == 4)
        #expect(failed.controls.filter { $0.keyboardReachable && !$0.label.isEmpty && !$0.helper.isEmpty }.count == failed.controls.count)
        #expect(failed.preview.controlCount == 0)

        let sample = page(settings: cardOn(), space: nil, playback: .playing)
        #expect(sample.phase == .ready)
        #expect(sample.preview.body == .card(word: "Playing"))
        #expect(sample.preview.accessibilityLabel == LockScreenCopy.previewPlaying)
        #expect(sample.preview.controlCount == 0)
    }

    @Test func layoutTokensAndReduceMotion() {
        #expect(GlassSettingsMetrics.controlRow == 52)
        #expect(GlassSettingsMetrics.helperLine == 16)
        #expect(GlassSettingsMetrics.panelPadding == 32)
        #expect(GlassSettingsMetrics.cardSpacing == 28)
        let moving = page(reduceMotion: false)
        let still = page(reduceMotion: true)
        #expect(moving.animationDuration == LockScreenPageModel.motionDuration)
        #expect(moving.animationDuration > 0)
        #expect(still.animationDuration == 0)
        #expect(moving.rowHeight == GlassSettingsMetrics.controlRow)
        #expect(moving.panelPadding == GlassSettingsMetrics.panelPadding)
        #expect(moving.cardGap == GlassSettingsMetrics.cardSpacing)
        #expect(still.controls.allSatisfy { $0.keyboardReachable })
    }

    @Test func aMissingSoundFileIsExplainedAndNotPlayed() {
        var settings = LockScreenSettings.off
        settings.lockSound = .resolve("Gentle")
        settings.soundLevel = .loud
        let model = page(settings: settings, soundFileExists: { _ in false })
        #expect(model.soundNote == LockScreenCopy.soundMissing)
        #expect(LockScreenSounds.cue(settings: settings, from: .locking, to: .locked, fileExists: { _ in false }) == nil)
    }

    @Test func helpersSitUnderEveryControl() {
        let model = page(settings: cardOn())
        #expect(model.controls.map(\.id) == ["playerCard", "lockSound", "unlockSound", "soundLevel"])
        for control in model.controls {
            #expect(control.helper.isEmpty == false)
            #expect(control.label == control.title)
            #expect(control.keyboardReachable)
        }
    }

    @Test func theSymbolGateKeepsNoPartialTable() {
        #expect(LockScreenSymbolGate.table(names: ["one", "two"], lookup: { $0 == "one" ? 3 : nil }) == nil)
        #expect(LockScreenSymbolGate.table(names: ["one"], lookup: { _ in 0 }) == nil)
        #expect(LockScreenSymbolGate.table(names: [], lookup: { _ in 8 }) == nil)
        #expect(LockScreenSymbolGate.table(names: ["one", "one"], lookup: { _ in 8 }) == nil)
        #expect(LockScreenSymbolGate.table(names: ["one", "two"], lookup: { $0 == "one" ? 2 : 9 }) == ["one": 2, "two": 9])
    }

    @Test func aResolvedProbeShowsThePlayerCard() {
        let table = LockScreenSymbolGate.table(names: ["SLSMainConnectionID"], lookup: { _ in 4 })
        #expect(table != nil)
        #expect(LockScreenSpaceProbe.answer(resolved: table != nil, invokesUnverifiedSymbols: false) == .shown)
        #expect(LockScreenSpaceProbe.answer(resolved: false, invokesUnverifiedSymbols: false) == .symbolMissing)
        #expect(LockScreenSpaceProbe.answer(resolved: true, invokesUnverifiedSymbols: true) == .callFailed)
    }

    @Test func spaceSymbolNamesLiveInTheLoaderOnly() throws {
        let root = try repositoryRoot().appendingPathComponent("Sources")
        var hits: [String] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            Issue.record("sources could not be listed")
            return
        }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("SLSMainConnectionID") { hits.append(url.lastPathComponent) }
        }
        #expect(hits == ["LockScreenSpaceLoader.swift"])
        let loader = try String(contentsOf: repositoryRoot().appendingPathComponent("Sources/Zeus/Settings/GlassShell/Sections/LockScreen/LockScreenSpaceLoader.swift"), encoding: .utf8)
        #expect(loader.contains("invokesUnverifiedSymbols = false"))
        #expect(!loader.contains("unsafeBitCast"))
        #expect(!loader.contains("dlsym(") || loader.contains("lookup"))
    }

    // MARK: Persistence

    @Test func eachSettingSurvivesASecondStoreOnTheSameValues() {
        var first = LockScreenSettingsStore()
        #expect(first.settings == .off)
        let chosen = LockScreenSettings.resolve(
            playerCard: true, lockSound: "Gentle", unlockSound: "To-do", soundLevel: "Quiet", origin: .owner
        )
        first.save(chosen)
        let second = LockScreenSettingsStore(values: first.values)
        #expect(second.settings == chosen)
        #expect(second.values[LockScreenSettingKey.playerCard] == "true")
        #expect(second.values[LockScreenSettingKey.lockSound] == "Gentle")
        #expect(second.values[LockScreenSettingKey.unlockSound] == "To-do")
        #expect(second.values[LockScreenSettingKey.soundLevel] == "Quiet")
    }

    @Test func aFreshStoreIsOffAndAnImportCannotTurnTheCardOrTheSoundsOn() {
        let fresh = LockScreenSettingsStore()
        #expect(fresh.settings == .off)
        let incoming = [
            LockScreenSettingKey.playerCard: "true",
            LockScreenSettingKey.lockSound: "Gentle",
            LockScreenSettingKey.unlockSound: "Listening",
            LockScreenSettingKey.soundLevel: "Loud",
        ]
        let imported = LockScreenSettingsStore(values: LockScreenSettingsStore.importing(incoming))
        #expect(imported.settings == .off)
        let kept = LockScreenSettingsStore.importing(incoming, into: ["lockScreen.playerCard": "false"])
        #expect(LockScreenSettingsStore(values: kept).settings.playerCard == false)
    }

    @Test func theCatalogRegistersTheKeysForExportImportSearchAndReset() {
        let items = LockScreenSectionSlot.keyContributions
        #expect(items.map(\.id) == LockScreenSettingKey.all)
        #expect(items.allSatisfy { $0.policy == .importCannotEnable })
        #expect(items.allSatisfy { $0.defaultValue == "false" || $0.defaultValue == "Off" })
        #expect(GlassSectionManifest.keyContributions.map(\.id).contains(LockScreenSettingKey.playerCard))
        let problems = SettingsKeyLedger.problems(catalogIDs: ["general.language"], contributions: GlassSectionManifest.keyContributions)
        #expect(problems.isEmpty)
        let card = items[0]
        var stored: [String: String] = [:]
        #expect(SettingsKeyLedger.save(&stored, card, "true"))
        #expect(SettingsKeyLedger.exportMap(stored: stored, contributions: items)[card.id] == "true")
        #expect(SettingsKeyLedger.imported(card, current: "false", incoming: "true") == nil)
        #expect(SettingsKeyLedger.resetValue(card) == "false")
        #expect(SettingsKeyLedger.search("player", in: items).map(\.id) == [LockScreenSettingKey.playerCard])
    }

    // MARK: Helpers

    private func cardOn() -> LockScreenSettings {
        var settings = LockScreenSettings.off
        settings.playerCard = true
        return settings
    }

    private func locked(
        space: @escaping @Sendable (Int) -> LockScreenSpaceAnswer,
        playback: LockScreenPlayback = .playing
    ) -> LockScreenSession {
        var session = LockScreenSession(settings: cardOn())
        session.handle(.sawUnlocked, playback: playback, space: { _ in .shown }, soundFileExists: { _ in true })
        session.handle(.sawLocked, playback: playback, space: space, soundFileExists: { _ in true })
        return session
    }

    private func page(
        settings: LockScreenSettings = LockScreenSettings.resolve(
            playerCard: false, lockSound: "Gentle", unlockSound: "Off", soundLevel: "Quiet", origin: .owner
        ),
        space: LockScreenSpaceAnswer? = nil,
        playback: LockScreenPlayback = .none,
        reduceMotion: Bool = false,
        soundFileExists: @escaping @Sendable (String) -> Bool = { _ in true },
        loaded: Bool = true
    ) -> LockScreenPageModel {
        LockScreenPageModel.make(
            settings: settings,
            playback: playback,
            space: space,
            reduceMotion: reduceMotion,
            soundFileExists: soundFileExists,
            loaded: loaded
        )
    }

    private func assertClosed(
        _ session: LockScreenSession,
        effects: [LockScreenEffect],
        playback: LockScreenPlayback,
        answer: LockScreenSpaceAnswer
    ) {
        #expect(session.surface.controlCount == 0)
        #expect(session.surface.acceptsCommands == false)
        #expect(session.commands.isEmpty)
        #expect(session.press("seek") == false)
        if let log = session.surface.log {
            #expect(Self.allowedLogs.contains(log))
        }
        if session.surface.visible {
            #expect(session.observation == .locked)
            #expect(session.settings.playerCard)
            #expect(playback != .none)
            #expect(answer == .shown)
            #expect(session.surface.log == nil)
            #expect(session.surface.word == (playback == .playing ? "Playing" : "Paused"))
            #expect(session.surface.windowID != nil)
        } else {
            #expect(session.surface.word == nil)
            #expect(session.surface.windowID == nil)
            #expect(session.hit(LockScreenPointer(x: 4, y: 4)) == .session)
        }
        for effect in effects {
            if case .play(let cue) = effect {
                #expect(cue.gain == 0.35 || cue.gain == 1)
                #expect(LockScreenSoundOption.all.contains { $0.fileName == cue.fileName })
            }
            if case .open = effect {
                #expect(session.surface.visible)
            }
        }
    }

    private func repositoryRoot() throws -> URL {
        if let env = ProcessInfo.processInfo.environment["ZEUS_REPO_ROOT"] {
            let url = URL(fileURLWithPath: env)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
        }
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            let manifest = url.appendingPathComponent("Package.swift")
            if let text = try? String(contentsOf: manifest, encoding: .utf8), text.contains("name: \"Zeus\"") {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw LockScreenTestError.repositoryNotFound
    }
}

private enum LockScreenTestError: Error { case repositoryNotFound }
