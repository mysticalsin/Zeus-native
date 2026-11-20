import Testing
@testable import ZeusCore

@Suite struct FocusSectionSessionTests {
    @Test func overlayWhenAFocusTurnsOnOrOffIsOffAndFailsClosed() {
        var session = FocusSectionSession()
        #expect(session.handle(.publicSample(isFocused: true, attachedName: "Deep Work")).isEmpty)
        #expect(session.transition.state == .off)

        let enabled = session.handle(.setTransition(true))
        #expect(enabled.contains(.request(.focusStatus)))
        #expect(!enabled.contains(.readStore))
        #expect(!enabled.contains(.browseLocalNetwork))
        #expect(session.content().status == .loading)
        #expect(session.content().preview.line == "Checking")

        let denied = session.handle(.permission(.focusStatus, .denied))
        #expect(session.transition.state == .unavailable)
        #expect(session.content().status == .unavailable("Unavailable"))
        #expect(session.home().occupancy == .ready)
        #expect(session.home().subtitle == "Ready")
        #expect(!denied.contains { if case .showOverlay = $0 { return true } else { return false } })

        _ = session.handle(.setTransition(false))
        _ = session.handle(.permission(.focusStatus, .allowed))
        let again = session.handle(.setTransition(true))
        #expect(again.contains(.readPublic))
        let baseline = session.handle(.publicSample(isFocused: true, attachedName: "Deep Work"))
        #expect(!showsOverlay(baseline))
        #expect(session.transition.state == .idle)
        #expect(session.name.displayName == nil)
        let turnedOff = session.handle(.publicSample(isFocused: false, attachedName: "Deep Work"))
        #expect(turnedOff.contains(.showOverlay(label: "Focus off", animation: MotionTokens.crossfadeDuration)))
        let back = session.handle(.publicSample(isFocused: true, attachedName: "Deep Work"))
        #expect(back.contains(.showOverlay(label: "Focus on", animation: MotionTokens.crossfadeDuration)))

        _ = session.handle(.setReadName(true))
        let named = session.handle(.publicSample(isFocused: true, attachedName: "Reading"))
        #expect(named.contains(.showOverlay(label: "Reading", animation: MotionTokens.crossfadeDuration)))
        let cleared = session.handle(.publicSample(isFocused: false, attachedName: "Reading"))
        #expect(cleared.contains(.showOverlay(label: "Focus off", animation: MotionTokens.crossfadeDuration)))

        _ = session.handle(.reduceMotion(true))
        let reduced = session.handle(.publicSample(isFocused: true, attachedName: "Reading"))
        #expect(reduced.contains(.showOverlay(label: "Reading", animation: 0)))
        #expect(session.content().preview.animationDuration == 0)
        #expect(session.content().preview.animates == false)
    }

    @Test func theFirstReadingIsABaselineAndADeniedRecoveryDoesNotCue() {
        var session = FocusSectionSession()
        _ = session.handle(.setTransition(true))
        _ = session.handle(.permission(.focusStatus, .allowed))
        #expect(!showsOverlay(session.handle(.publicSample(isFocused: false, attachedName: nil))))
        #expect(showsOverlay(session.handle(.publicSample(isFocused: true, attachedName: nil))))
        _ = session.handle(.permission(.focusStatus, .denied))
        #expect(session.transition.state == .unavailable)
        _ = session.handle(.permission(.focusStatus, .allowed))
        #expect(!showsOverlay(session.handle(.publicSample(isFocused: true, attachedName: nil))))
        let started = session.now
        _ = session.handle(.tick(started + 2.49))
        #expect(session.transition.state == .idle)
        let hiding = session.handle(.tick(started + FocusTransitionMachine.dwell))
        #expect(hiding.isEmpty || !showsOverlay(hiding))
    }

    @Test func aShowingOverlayHidesAtTheDwellAndOnDismiss() {
        var session = FocusSectionSession()
        _ = session.handle(.setTransition(true))
        _ = session.handle(.permission(.focusStatus, .allowed))
        _ = session.handle(.publicSample(isFocused: false, attachedName: nil))
        _ = session.handle(.tick(10))
        _ = session.handle(.publicSample(isFocused: true, attachedName: nil))
        if case .showing(_, _, let since) = session.transition.state {
            #expect(session.handle(.tick(since + 2.49)).isEmpty)
            #expect(session.transition.state != .idle)
            let hidden = session.handle(.tick(since + 2.5))
            #expect(hidden.contains(.hideOverlay))
            #expect(session.transition.state == .idle)
        } else {
            Issue.record("overlay did not show")
        }

        _ = session.handle(.publicSample(isFocused: false, attachedName: nil))
        let dismissed = session.handle(.dismissOverlay)
        #expect(dismissed.contains(.hideOverlay))
        #expect(session.transition.state == .idle)
        _ = session.handle(.setTransition(false))
        #expect(session.handle(.publicSample(isFocused: true, attachedName: nil)).isEmpty)
        #expect(session.transition.state == .off)
    }

    @Test func focusWidgetOnTheHomeViewUsesTheExistingSlot() {
        #expect(HomeSlots([nil, nil, nil, nil])[2] == .focus)
        #expect(FocusSettingKey.homeWidget == "home.widget.2")
        let session = FocusSectionSession()
        #expect(session.home().occupancy == .ready)
        #expect(session.home().title == "Focus")
        #expect(session.home().subtitle == "Ready")
        #expect(session.home().nameStatus == "Hidden")
        #expect(session.home().accessibilityLabel == "Focus, Ready")

        var music = session
        _ = music.handle(.setHomeWidget("Music"))
        #expect(music.home().occupancy == .empty)
        #expect(music.home().subtitle == "Home slot 2 is showing another widget.")
        #expect(music.content().status == .empty)
        #expect(music.content().preview.line == "Nothing is on")

        for stored in ["Focus", "focus", "", "FOCUS", nil] {
            var restored = music
            _ = restored.handle(.setHomeWidget(stored))
            #expect(restored.home().occupancy == .ready)
        }

        var running = session
        _ = running.handle(.timer(FocusTimerSnapshot(phase: .focus, remainingSeconds: 24 * 60)))
        #expect(running.home().occupancy == .running)
        #expect(running.home().subtitle == "Focusing")
        #expect(running.home().accessibilityLabel.contains("Focusing"))
        #expect(FocusHomeWidgetPolicy.animates(reduceMotion: false, running: true))
        #expect(!FocusHomeWidgetPolicy.animates(reduceMotion: true, running: true))
        _ = running.handle(.reduceMotion(true))
        #expect(running.home().animates == false)

        _ = running.handle(.setReadName(true))
        _ = running.handle(.permission(.focusStatus, .denied))
        #expect(running.home().occupancy == .running)
        #expect(running.home().nameStatus == "Unavailable")
        #expect(running.home().subtitle == "Focusing")
    }

    @Test func overlaysAllowedDuringAFocusFollowTheRuleTableAndStartOff() {
        var session = FocusSectionSession()
        #expect(session.settings.overlaysAllowed == false)
        for kind in FocusOverlayKind.allCases {
            #expect(session.overlayDecision(kind) == .unavailable)
        }
        _ = session.handle(.setOverlaysAllowed(true))
        #expect(session.content().status == .loading)
        _ = session.handle(.permission(.focusStatus, .allowed))
        _ = session.handle(.publicSample(isFocused: true, attachedName: nil))
        for rule in FocusOverlayFilter.table {
            let decision = session.overlayDecision(rule.kind)
            #expect(decision == (rule.allowed ? FocusOverlayDecision.allowed : .blocked))
        }
        _ = session.handle(.setOverlaysAllowed(false))
        #expect(session.overlayDecision(.notification) == .blocked)
        #expect(session.overlayDecision(.transition) == .blocked)
        _ = session.handle(.setTransition(true))
        #expect(session.overlayDecision(.transition) == .allowed)
        #expect(session.overlayDecision(.notification) == .blocked)
        _ = session.handle(.publicSample(isFocused: false, attachedName: nil))
        #expect(session.overlayDecision(.notification) == .unfiltered)
        _ = session.handle(.permission(.focusStatus, .denied))
        #expect(session.overlayDecision(.notification) == .unavailable)
        #expect(session.home().occupancy == .ready)
    }

    @Test func lockScreenFocusIsOffAndNeverShowsTheName() {
        var session = FocusSectionSession()
        #expect(session.lockScreen() == .hidden)
        #expect(session.settings.lockScreen == false)
        _ = session.handle(.setLockScreen(true))
        _ = session.handle(.permission(.focusStatus, .denied))
        #expect(session.lockScreen() == .unavailable("Unavailable"))
        #expect(session.home().occupancy == .ready)
        #expect(session.content().status == .unavailable("Unavailable"))

        _ = session.handle(.setLockScreen(false))
        _ = session.handle(.permission(.focusStatus, .allowed))
        _ = session.handle(.setLockScreen(true))
        _ = session.handle(.setReadName(true))
        _ = session.handle(.publicSample(isFocused: false, attachedName: nil))
        #expect(session.lockScreen() == .empty)
        let names = ["Deep Work", "Secret", String(repeating: "名", count: 64), "Focus on", "A\u{0001}B"]
        for name in names {
            _ = session.handle(.publicSample(isFocused: true, attachedName: name))
            #expect(session.lockScreen() == .showing(FocusLockScreenPolicy.label))
            if let showing = lockLabel(session.lockScreen()) {
                #expect(showing == "Focus on")
                #expect(!showing.contains("Secret"))
                #expect(!showing.contains("Deep"))
            }
        }
        #expect(session.name.displayName == "AB")
        _ = session.handle(.setLockScreen(false))
        #expect(session.lockScreen() == .hidden)
        #expect(session.name.displayName == "AB")
    }

    @Test func everyControlHasAHelperAVoiceOverLabelAndTheGlassMetrics() {
        let content = FocusSectionSession().content()
        #expect(content.title == "Focus")
        #expect(content.placement == "topbarTab")
        #expect(content.placementOrder == 4)
        #expect(content.rowHeight == 52)
        #expect(content.panelPadding == 32)
        #expect(content.cardGap == 28)
        #expect(content.controls.map(\.id) == [
            FocusSettingKey.transitionOverlay,
            FocusSettingKey.overlaysAllowed,
            FocusSettingKey.lockScreen,
            FocusSettingKey.readName,
            FocusSettingKey.storeFile,
            FocusSettingKey.localNetwork,
            FocusSettingKey.sharedLink,
            FocusSettingKey.homeWidget,
        ])
        let helpers = [
            "Shows a short overlay when a Focus turns on or off. Off until you turn it on.",
            "While a Focus is on, only the overlays in the filter may appear. Off blocks every overlay.",
            "Shows that a Focus is on at the lock screen. The name stays hidden. Off until you turn it on.",
            "Uses the public filter. Off reads nothing.",
            "A second path, only if you turn it on. It needs Full Disk Access. Off reads nothing.",
            "Off does not browse.",
            "A plain link on shared Wi-Fi is refused. Off until you turn it on.",
            "Home slot 2. Today it shows the Focus timer. A name appears only when reading is allowed.",
        ]
        #expect(content.controls.map(\.helper) == helpers)
        for control in content.controls {
            #expect(!control.helper.isEmpty)
            #expect(control.accessibilityLabel.contains(control.title))
            #expect(control.keyboardReachable)
            #expect(control.accessibilityValue == "Off" || control.id == FocusSettingKey.homeWidget)
        }
        #expect(content.controls.last?.accessibilityValue == "Focus")
        #expect(content.preview.accessibilityLabel.contains(content.preview.line))
        #expect(FocusTransitionMachine.animationDuration(reduceMotion: true) == 0)
        #expect(FocusTransitionMachine.animationDuration(reduceMotion: false) == MotionTokens.crossfadeDuration)
    }

    @Test func anImportTurnsEveryFocusFeatureOffAndHidesTheOverlay() {
        var session = FocusSectionSession()
        _ = session.handle(.setTransition(true))
        _ = session.handle(.setOverlaysAllowed(true))
        _ = session.handle(.setLockScreen(true))
        _ = session.handle(.setReadName(true))
        _ = session.handle(.setStoreFile(true))
        _ = session.handle(.setLocalNetwork(true))
        _ = session.handle(.setSharedLink(true))
        _ = session.handle(.permission(.focusStatus, .allowed))
        _ = session.handle(.publicSample(isFocused: false, attachedName: nil))
        _ = session.handle(.publicSample(isFocused: true, attachedName: "Deep Work"))
        #expect(session.transition.state != .off)
        var imported: [String: Bool] = [:]
        for key in FocusSettingKey.optIn { imported[key] = true }
        let effects = session.handle(.imported(imported, homeWidget: "Weather"))
        #expect(effects.contains(.hideOverlay))
        #expect(effects.contains(.cancelReads))
        #expect(session.settings == FocusSectionSettings.imported(bools: imported, homeWidget: "Weather"))
        #expect(session.settings.readName == false)
        #expect(session.transition.state == .off)
        #expect(session.name.phase == .off)
        #expect(session.name.displayName == nil)
        #expect(session.lockScreen() == .hidden)
        #expect(session.home().occupancy == .empty)
    }

    @Test func permissionAnswersDoNotStartAReadUntilAFeatureIsOn() {
        let answers: [FocusPermissionAnswer] = [.notDetermined, .allowed, .denied]
        let switches = 0..<16
        for mask in switches {
            for status in answers {
                for disk in answers {
                    for network in answers {
                        var session = FocusSectionSession()
                        _ = session.handle(.permission(.focusStatus, status))
                        _ = session.handle(.permission(.fullDisk, disk))
                        _ = session.handle(.permission(.localNetwork, network))
                        let before = session.handle(.publicSample(isFocused: true, attachedName: "Deep Work"))
                        #expect(before.isEmpty)
                        #expect(session.name.displayName == nil)
                        if mask & 1 != 0 { _ = session.handle(.setTransition(true)) }
                        if mask & 2 != 0 { _ = session.handle(.setOverlaysAllowed(true)) }
                        if mask & 4 != 0 { _ = session.handle(.setLockScreen(true)) }
                        if mask & 8 != 0 { _ = session.handle(.setReadName(true)) }
                        let needs = mask != 0
                        if !needs {
                            #expect(session.handle(.storeSample(.on(name: "Deep Work", symbol: "moon.fill"))).isEmpty)
                            #expect(session.name.displayName == nil)
                            #expect(session.lockScreen() == .hidden)
                            #expect(session.transition.state == .off)
                        } else if status == .denied && mask & 8 == 0 {
                            #expect(session.content().status == .unavailable("Unavailable"))
                            #expect(session.home().occupancy == .ready || session.home().occupancy == .empty)
                        }
                    }
                }
            }
        }
    }

    private func showsOverlay(_ effects: [FocusSectionSession.Effect]) -> Bool {
        effects.contains { if case .showOverlay = $0 { return true } else { return false } }
    }

    private func lockLabel(_ state: FocusLockScreenState) -> String? {
        if case .showing(let label) = state { return label }
        return nil
    }
}
