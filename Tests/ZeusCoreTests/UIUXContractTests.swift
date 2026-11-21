import CoreGraphics
import Foundation
import Testing

/// Linux runs ZeusCore types. Notch presentation, the settings window, hub phases, the decision row,
/// and the dynamic-type ramp are AppKit types. Those cases are marked Mac-only and skipped here.
enum UIUXRuntime {
    static var appKitSurfaces: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}

@Suite("UI UX surface contracts")
struct UIUXContractTests {
    private static let tabs = ["home", "tiling", "agents", "chat", "scribe"]

    /// Mac-only. Hover dwell phases live on AppKit NotchController and were not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func hoverDwellOpensFromIdleAndFromPeek() {
        var desk = ChromeDesk()
        desk.pointerEntered()
        #expect(desk.phase == .hover)
        desk.dwellFinished()
        #expect(desk.phase == .expanded)

        desk = ChromeDesk(phase: .peek)
        desk.pointerEntered()
        #expect(desk.phase == .hover)
        #expect(desk.hoverFrom == .peek)
        desk.pointerExited()
        #expect(desk.phase == .peek)
        desk.pointerEntered()
        desk.dwellFinished()
        #expect(desk.phase == .expanded)
    }

    /// Mac-only. Hover cancel lives on AppKit NotchController and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func leavingBeforeTheDwellCancelsTheHover() {
        var desk = ChromeDesk()
        desk.pointerEntered()
        desk.pointerExited()
        #expect(desk.phase == .idle)
        desk.dwellFinished()
        #expect(desk.phase == .idle)
    }

    @Test func clickTriggerDoesNotOpenOnHover() {
        #expect(NotchOpenRules.opensOnHover(.hover))
        #expect(!NotchOpenRules.opensOnHover(.click))
        let zone = CGRect(x: 0, y: 0, width: 40, height: 14)
        let point = CGPoint(x: 20, y: 14)
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: true, point: point, zone: zone))
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: point, zone: zone))
    }

    @Test func aPressOpensWhenTheTriggerIsClick() {
        let zone = CGRect(x: 10, y: 10, width: 20, height: 14)
        let point = CGPoint(x: 20, y: 24)
        // A closed notch and a peek are both `panelIsOpen: false`. A click promotes a peek.
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: point, zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: true, point: point, zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .hover, panelIsOpen: false, point: point, zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: 20, y: 10), zone: zone))
    }

    /// Mac-only. Drawn-notch calibration lives on AppKit NotchController and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func calibrationDoesNotOpenThePanel() {
        var calibrating = ChromeDesk(trigger: .click, calibrating: true)
        calibrating.press()
        #expect(calibrating.phase == .idle)
    }

    @Test(arguments: [1, 2, 3])
    func repeatedClicksDoNotCloseThePanel(count: Int) {
        let zone = CGRect(x: 0, y: 0, width: 40, height: 14)
        let point = CGPoint(x: 20, y: 14)
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: point, zone: zone))
        for _ in 0..<count {
            #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: true, point: point, zone: zone))
        }
        #expect(!NotchOpenRules.opensOnClick(trigger: .hover, panelIsOpen: false, point: point, zone: zone))
    }

    /// Mac-only. Island hold lives on AppKit NotchController and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func anIslandHoldFollowsTheTrigger() {
        var hover = ChromeDesk()
        hover.pointerEntered()
        hover.holdIsland()
        #expect(hover.phase == .expanded)

        var click = ChromeDesk(trigger: .click)
        click.holdIsland()
        #expect(click.phase == .idle)
    }

    /// Mac-only. Shift peek lives on AppKit NotchController and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func aShiftHoldPeeksAndReleaseReturns() {
        var desk = ChromeDesk()
        desk.shiftHold()
        #expect(desk.phase == .peek)
        #expect(desk.shiftPeek)
        desk.shiftRelease()
        #expect(desk.phase == .idle)
        #expect(!desk.shiftPeek)
    }

    /// Mac-only. Tab-hold lives on AppKit NotchController and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func aTabHoldRevealsTheStripWithoutOpening() {
        var desk = ChromeDesk()
        desk.tabHold()
        #expect(desk.tabStrip)
        #expect(desk.phase == .idle)
        desk.tabRelease()
        #expect(!desk.tabStrip)
    }

    /// Mac-only. File swipe lives on AppKit NotchController and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func aFileSwipeOpensTheShelfAndABareSwipeDoesNot() {
        var desk = ChromeDesk(trigger: .click)
        desk.swipeRight(files: false)
        #expect(desk.phase == .idle)
        #expect(desk.bareSwipes == 1)
        desk.swipeRight(files: true)
        #expect(desk.phase == .expanded)
        #expect(desk.tab == "shelf")
    }

    /// Mac-only. Panel hold-open lives on AppKit NotchController and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func theExpandedPanelStaysForVoiceOverAPinTheMenuThePrompterAndThePicker() {
        for flag in 0..<5 {
            var desk = ChromeDesk(phase: .expanded)
            switch flag {
            case 0: desk.voiceOver = true
            case 1: desk.pinned = true
            case 2: desk.menuOpen = true
            case 3: desk.prompterActive = true
            default: desk.picker = true
            }
            desk.pointerExited()
            #expect(desk.phase == .expanded)
        }
        var plain = ChromeDesk(phase: .expanded)
        plain.pointerExited()
        #expect(plain.phase == .idle)
        plain.phase = .expanded
        plain.approval = ApprovalCard(agent: "Zeus", command: "read", highRisk: false, detailsHidden: false, ownActions: false, offersTrust: false, changePreview: false)
        plain.pointerExited()
        #expect(plain.phase == .peek)
    }

    /// Mac-only. Picker Escape lives on AppKit NotchController and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func escapeClosesOnlyThePicker() {
        var desk = ChromeDesk(phase: .expanded, picker: true, sessionCount: 2)
        desk.approval = ApprovalCard(agent: "Zeus", command: "rm", highRisk: true, detailsHidden: false, ownActions: false, offersTrust: true, changePreview: false)
        desk.escape()
        #expect(!desk.picker)
        #expect(desk.phase == .peek)
        #expect(desk.verdict == nil)
        desk.escape()
        #expect(desk.escapeIgnored == 1)
        #expect(desk.verdict == nil)
        #expect(desk.approval != nil)
    }

    /// Mac-only. Picker Return lives on AppKit NotchController and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func returnOpensThePickedSessionAndDoesNotApprove() {
        var desk = ChromeDesk(picker: true, sessionCount: 2)
        desk.approval = ApprovalCard(agent: "Zeus", command: "send", highRisk: false, detailsHidden: false, ownActions: false, offersTrust: false, changePreview: true)
        #expect(desk.returnKey() == .openedTerminal)
        #expect(desk.verdict == nil)
        #expect(desk.phase == .peek)

        var empty = ChromeDesk(picker: true, sessionCount: 0)
        #expect(empty.returnKey() == .closedPicker)
        var plain = ChromeDesk(phase: .expanded)
        #expect(plain.returnKey() == .ignored)
    }

    /// Mac-only. Approval focus lives on AppKit NotchModel and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func approvalButtonsDecideAndFocusStaysInOrder() {
        var desk = ChromeDesk(phase: .peek)
        desk.approval = ApprovalCard(agent: "Zeus", command: "Send\nnote", highRisk: false, detailsHidden: false, ownActions: false, offersTrust: true, changePreview: true)
        #expect(desk.focusTargets(tabs: Self.tabs) == ["approval.deny", "approval.approve", "approval.trust"])
        desk.focusNext(tabs: Self.tabs)
        desk.focusNext(tabs: Self.tabs)
        desk.focusNext(tabs: Self.tabs)
        #expect(desk.focus == 2)
        desk.decide(.allow)
        #expect(desk.verdict == .allow)
        #expect(desk.phase == .idle)
        desk.decide(.deny)
        #expect(desk.verdict == .allow)

        var hidden = ChromeDesk(phase: .peek)
        hidden.approval = ApprovalCard(agent: "Zeus", command: "plan", highRisk: false, detailsHidden: true, ownActions: true, offersTrust: true, changePreview: false)
        #expect(hidden.focusTargets(tabs: Self.tabs) == ["approval.deny"])
        hidden.decide(.deny)
        #expect(hidden.verdict == .deny)
    }

    /// Mac-only. Panel focus lives on AppKit NotchController and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func panelFocusClampsAtTheEnds() {
        var desk = ChromeDesk(phase: .expanded)
        let targets = desk.focusTargets(tabs: Self.tabs)
        #expect(targets == Self.tabs + ["notch.more"])
        desk.focusPrevious(tabs: Self.tabs)
        #expect(desk.focus == 0)
        for _ in 0..<20 { desk.focusNext(tabs: Self.tabs) }
        #expect(desk.focus == targets.count - 1)
        let again = desk.focusTargets(tabs: Self.tabs)
        #expect(again == targets)
    }

    /// Mac-only. GSSection and GSNavigation are AppKit types and were not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func settingsFocusClampsAcrossTheLiveSidebar() throws {
        let root = try #require(UIUXRepo.root())
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Settings/GlanceSettingsWindow.swift"), encoding: .utf8)
        let sections = UIUXSourceMap.sidebar(in: source)
        #expect(sections.count > UIUXSourceMap.canonicalTwelve.count)
        #expect(!sections.contains { $0.id == "iPhone" })
        let ids = Set(sections.map(\.id))
        for id in UIUXSourceMap.canonicalTwelve {
            #expect(ids.contains(id))
        }
        let groupOrder = ["settings", "tools", "app"]
        let groupIndexes = sections.map { groupOrder.firstIndex(of: $0.group) ?? -1 }
        #expect(groupIndexes.allSatisfy { $0 >= 0 })
        #expect(groupIndexes == groupIndexes.sorted())
        var desk = SettingsDesk(sections: sections)
        desk.step(-4)
        #expect(desk.focused?.id == sections[0].id)
        for _ in 0..<(sections.count + 3) { desk.step(1) }
        #expect(desk.index == sections.count - 1)
        desk.select("murmure")
        #expect(desk.focused?.id == "murmure")
        #expect(desk.returnKeyEffect() == "murmure")
    }

    /// Mac-only. Section content phases are not a ZeusCore type and were not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces), arguments: UIUXSourceMap.canonicalTwelve)
    func everyCanonicalSectionWalksEmptyLoadingErrorAndRecovery(id: String) {
        let sections = UIUXSourceMap.canonicalTwelve.map { SettingsSectionRef(id: $0, title: $0, group: "settings") }
        var desk = SettingsDesk(sections: sections)
        desk.select(id)
        #expect(desk.phase[id] == .empty)
        desk.refreshFocused()
        #expect(desk.phase[id] == .loading)
        desk.failFocused()
        #expect(desk.phase[id] == .error)
        desk.refreshFocused()
        #expect(desk.phase[id] == .error)
        desk.retryFocused()
        #expect(desk.phase[id] == .recovery)
        desk.failFocused()
        #expect(desk.phase[id] == .error)
        desk.retryFocused()
        desk.succeedFocused()
        #expect(desk.phase[id] == .ready)
        desk.clearFocused()
        #expect(desk.phase[id] == .empty)
    }

    /// Mac-only. Hub phases are not a Linux-reachable production type and were not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces), arguments: HubKind.allCases)
    func hubsWalkEmptyLoadingErrorAndRecovery(kind: HubKind) {
        var hub = HubDesk(kind: kind)
        #expect(!hub.commandsEnabled)
        hub.content.refresh()
        #expect(hub.content.phase == .loading)
        hub.play()
        #expect(hub.command == "")
        hub.content.fail()
        #expect(hub.content.phase == .error)
        hub.content.retry()
        hub.content.succeed()
        #expect(hub.commandsEnabled)
        hub.play()
        #expect(hub.command == "play")
        if kind == .agents {
            hub.reply("")
            #expect(hub.content.phase == .error)
            hub.content.phase = .ready
            hub.reply("hello")
            #expect(hub.command == "reply")
        }
    }

    @Test func scribeStartEndKeepAndRecover() {
        let id = ScribeSessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!)
        var machine = ScribeSessionMachine()
        #expect(scribeKind(machine.phase) == "idle")
        #expect(machine.start(id, now: 10).isApplied)
        #expect(scribeKind(machine.phase) == "starting")
        #expect(machine.acknowledgeCapture(id, now: 11).isApplied)
        #expect(scribeKind(machine.phase) == "recording")
        #expect(machine.requestEnd(id, now: 12, grace: 5).isApplied)
        #expect(scribeKind(machine.phase) == "ending")
        #expect(machine.keepRecording(id).isApplied)
        #expect(scribeKind(machine.phase) == "recording")
        #expect(machine.requestEnd(id, now: 20, grace: 2).isApplied)
        #expect(!machine.isCountdownExpired(now: 21))
        #expect(machine.isCountdownExpired(now: 22))
        #expect(machine.tick(now: 23).isApplied)
        #expect(scribeKind(machine.phase) == "ending")
        #expect(machine.captureEnded(id).isApplied)
        #expect(scribeKind(machine.phase) == "processing")
        #expect(machine.transcriptFinalized(id).isApplied)
        #expect(machine.notesReady(id).isApplied)
        #expect(scribeKind(machine.phase) == "complete")

        let denied = ScribeSessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!)
        var failed = ScribeSessionMachine()
        #expect(failed.start(denied, now: 1).isApplied)
        #expect(failed.fail(denied, reason: "permission").isApplied)
        #expect(scribeKind(failed.phase) == "failed")
        #expect(!failed.phase.isActive)
    }

    @Test func murmurHoldAndToggleMatchTheBehaviorContract() {
        let hold = DictationBehavior.holdToSpeak
        #expect(hold.finishesOnRelease)
        #expect(hold.actionOnPress(isDictating: false) == .begin)
        var holding = false
        for _ in 0..<3 {
            let action = hold.actionOnPress(isDictating: holding)
            #expect(action == .begin)
            if action == .begin { holding = true }
        }
        #expect(holding)
        #expect(hold.finishesOnRelease)

        let toggle = DictationBehavior.pressToToggle
        #expect(!toggle.finishesOnRelease)
        #expect(toggle.actionOnPress(isDictating: false) == .begin)
        #expect(toggle.actionOnPress(isDictating: true) == .finish)
        #expect(toggle.actionOnPress(isDictating: true) == .finish)
    }

    /// Mac-only. The decision row phase machine is not DecisionError and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces), arguments: DecisionFault.allCases)
    func decisionRowsRetryExceptWhenAPersonMustAct(fault: DecisionFault) {
        var row = DecisionRow()
        row.submit()
        #expect(row.phase == .loading)
        row.submit()
        #expect(row.inFlight)
        row.fail(fault)
        #expect(row.phase == .error)
        #expect(row.confidence == nil)
        let retried = row.retry()
        #expect(retried == !fault.personMustAct)
        if fault.personMustAct {
            #expect(row.phase == .error)
        } else {
            #expect(row.phase == .recovery)
            row.submit()
            row.arrive(confidence: 0.8)
            #expect(row.phase == .ready)
            #expect(row.confidence == 0.8)
        }
    }

    @Test func reduceMotionCollapsesSpringsAndKeepsTheCrossfade() throws {
        #expect(MotionTokens.allSprings.count == 6)
        for token in MotionTokens.allSprings {
            #expect(MotionReduction.spring(token, reduceMotion: true) == nil)
            #expect(MotionReduction.spring(token, reduceMotion: false) == token)
        }
        #expect(MotionReduction.crossfadeDuration(reduceMotion: true) == 0.12)
        #expect(MotionReduction.crossfadeDuration(reduceMotion: false) == MotionTokens.crossfadeDuration)
        #expect(MotionReduction.pressScale(reduceMotion: true) == 1)
        #expect(MotionReduction.pressScale(reduceMotion: false) == MotionTokens.pressScale)
        #expect(MotionTokens.panelClose == SpringToken(response: 0.175, damping: 1))
        #expect(MotionTokens.panelOpen == SpringToken(response: 0.30, damping: 0.87))
        let root = try #require(UIUXRepo.root())
        let source = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/TopBar/MotionTokens.swift"), encoding: .utf8)
        #expect(UIUXSourceMap.matches(#"SpringToken\(response:"#, in: source).count == 6)
    }

    @Test func reduceTransparencySwapsToAnOpaqueFill() {
        let since = 10.0
        let layout = ScribeIncomingWordLayout(text: "hello", alreadyShown: 0, since: since)
        let mid = since + (1.0 / 12.0) + 0.01
        let glass = layout.frame(forWord: 0, shownWords: 1, at: mid, reduceMotion: false, reduceTransparency: false)
        let opaque = layout.frame(forWord: 0, shownWords: 1, at: mid, reduceMotion: false, reduceTransparency: true)
        #expect(glass.blur > 0)
        #expect(opaque.blur == 0)
        let reduced = layout.frame(forWord: 0, shownWords: 1, at: mid, reduceMotion: true, reduceTransparency: false)
        #expect(reduced.opacity == 1)
        #expect(reduced.blur == 0)
    }

    /// Mac-only. Dynamic Type ramps live on AppKit surfaces. ZeusCore has no shared ramp, and one was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func dynamicTypeStepsAreStrictlyIncreasing() {
        let scales = TypeStep.allCases.map(\.scale)
        #expect(scales.count == 12)
        for pair in zip(scales, scales.dropFirst()) {
            #expect(pair.1 > pair.0)
        }
        #expect(TypeStep.medium.scale == 1)
    }

    @Test func theOpenDwellMatchesTheSettingsLabels() throws {
        #expect(NotchOpenDelay.milliseconds(label: "Fast") == 100)
        #expect(NotchOpenDelay.milliseconds(label: "Standard") == 250)
        #expect(NotchOpenDelay.milliseconds(label: "") == 250)
        #expect(NotchOpenDelay.milliseconds(label: "Relaxed") == 600)
        let root = try #require(UIUXRepo.root())
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Notch/NotchController.swift"), encoding: .utf8)
        #expect(source.contains("NotchOpenDelay.milliseconds(label:"))
    }

    @Test func theDefaultTabRowPutsMurmureAndScribeInThePanel() {
        let tabs = TopBarLayout.defaultRow
        #expect(tabs.first == .home)
        #expect(tabs.contains(.dictation))
        #expect(TopBarTab.dictation.title == "Murmure")
        #expect(tabs.contains(.scribe))
        #expect(tabs.map(\.title).count == Set(tabs.map(\.id)).count)
    }

    @Test func contractControlsCarryLabelTraitAndIdentifier() throws {
        let root = try #require(UIUXRepo.root())
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Settings/GlanceSettingsWindow.swift"), encoding: .utf8)
        let sections = UIUXSourceMap.sidebar(in: settings)
        let tabs = TopBarLayout.defaultRow.map { (id: $0.rawValue, title: $0.title) }
        let controls = ContractControls.all(sections: sections, tabs: tabs)
        #expect(controls.count == Set(controls.map(\.id)).count)
        for control in controls {
            #expect(!control.id.isEmpty)
            #expect(!control.label.isEmpty)
            #expect(control.trait == "button")
        }
        let order = controls.map(\.id)
        let production = [
            "island", "notch.more", "approval.deny", "approval.approve", "approval.trust",
            "scribe.start", "scribe.endNow", "scribe.keep", "scribe.memory.open",
            "hub.nowPlaying.play", "hub.agents.reply", "hub.murmur.press",
        ] + sections.map { "settings.sidebar.\($0.id)" } + tabs.map { "notch.tab.\($0.id)" }
        #expect(order == production)
        #expect(order.filter { $0.hasPrefix("notch.tab.") } == TopBarLayout.defaultRow.map { "notch.tab.\($0.rawValue)" })
    }

    /// Mac-only. Panel focus order lives on AppKit NotchController and was not extracted.
    @Test(.enabled(if: UIUXRuntime.appKitSurfaces))
    func focusOrderIsDeterministic() {
        var desk = ChromeDesk(phase: .expanded)
        let first = desk.focusTargets(tabs: Self.tabs)
        desk.focusNext(tabs: Self.tabs)
        let second = desk.focusTargets(tabs: Self.tabs)
        #expect(first == second)
        #expect(first.first == "home")
        #expect(first.last == "notch.more")
    }

    @Test func fixtureButtonMissingAnIdentifierIsReported() {
        let source = """
        Button("Save") { save() }
            .accessibilityLabel("Save")
        Button { Image(systemName: "ellipsis") }
        NotchButton(title: "Approve", tint: tint, filled: true) { allow() }
            .accessibilityIdentifier("approval.approve")
        """
        let sites = UIUXAudit.fixtureControls(source)
        #expect(sites.count == 3)
        #expect(sites[0].complete == false)
        #expect(sites[0].detail.contains("identifier"))
        #expect(sites[1].complete == false)
        #expect(sites[1].detail.contains("label"))
        #expect(sites[2].complete)
    }

    @Test func fixtureLiteralDurationIsReported() {
        let literal = """
        view.animation(.easeOut(duration: 0.2).delay(0.12), value: flag)
        """
        let sites = UIUXAudit.fixtureMotion(literal)
        #expect(sites.contains { $0.literal && $0.detail.contains("0.2") })
        #expect(sites.contains { $0.missingReduce })

        let token = """
        view.animation(Motion.live(MotionTokens.panelOpen), value: flag)
        """
        #expect(UIUXAudit.fixtureMotion(token).isEmpty)

        let reduced = """
        view.animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: flag)
        """
        let covered = UIUXAudit.fixtureMotion(reduced)
        #expect(covered.allSatisfy { !$0.missingReduce && $0.literal })
    }

    @Test func motionTokenTableIsTheOnlySpringDefinition() throws {
        let root = try #require(UIUXRepo.root())
        let sources = root.appendingPathComponent("Sources")
        var hits: [String] = []
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift", let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if text.contains("SpringToken(response:") {
                hits.append(url.path.replacingOccurrences(of: root.path + "/", with: ""))
            }
        }
        #expect(hits == ["Sources/ZeusCore/TopBar/MotionTokens.swift"])
    }

    @Test func findingExpectationsCoverTheCatalog() throws {
        let catalog = try #require(UIUXFindingExpectations.catalog)
        #expect(catalog.schema == 1)
        #expect(catalog.findings.count == 395)
        #expect(UIUXFindingExpectations.closedIDs.count == 361)
        #expect(UIUXFindingExpectations.openIDs.count == 34)
        let ids = catalog.findings.map(\.id)
        #expect(ids.count == Set(ids).count)
        #expect(ids.allSatisfy { $0.hasPrefix("ZB-UIUX-") })
    }

    /// One case per finding that #257, #258, #259, #260, #262, and #263 close.
    /// The case fails while the scan still reports that file, line, kind, and detail.
    /// #257: A11Y-009 through A11Y-028, MOTION-001, REDUCE-001.
    /// #258: A11Y-001 through A11Y-008, TYPE-001, GLASS-001.
    /// #259: A11Y-037 through A11Y-093, TYPE-003, MOTION-004 through MOTION-010, GLASS-002.
    /// #260: A11Y-100 through A11Y-202, A11Y-213 through A11Y-288, TYPE-004, MOTION-011 through MOTION-013, REDUCE-003.
    /// #262: A11Y-294 through A11Y-357, TYPE-005, MOTION-014 through MOTION-025, REDUCE-004.
    /// #263: TYPE-002.
    @Test(arguments: UIUXFindingExpectations.closedIDs)
    func repositoryFindingsMatchTheCatalog(id: String) throws {
        let root = try #require(UIUXRepo.root())
        let finding = try #require(UIUXFindingExpectations.catalog?.findings.first { $0.id == id })
        #expect(finding.expect == "closed")
        let stillOpen = UIUXScanCache.shared.findings(root: root).contains { UIUXAudit.sameSite($0, finding) }
        #expect(!stillOpen)
    }

    /// Sites those fix PRs leave open: NotchView, speaker editors, speaker recognition, chat, and the decision row.
    /// The case fails if the scan drops the site before its expectation flips to closed.
    @Test(arguments: UIUXFindingExpectations.openIDs)
    func deferredFindingStaysOpenUntilItsOwnFix(id: String) throws {
        let root = try #require(UIUXRepo.root())
        let finding = try #require(UIUXFindingExpectations.catalog?.findings.first { $0.id == id })
        #expect(finding.expect == "open")
        let stillOpen = UIUXScanCache.shared.findings(root: root).contains { UIUXAudit.sameSite($0, finding) }
        #expect(stillOpen)
    }
}

private extension SettingsDesk {
    func returnKeyEffect() -> String { focused?.id ?? "" }
}

private func scribeKind(_ phase: ScribePhase) -> String {
    switch phase {
    case .idle: "idle"
    case .starting: "starting"
    case .recording: "recording"
    case .ending: "ending"
    case .processing: "processing"
    case .complete: "complete"
    case .failed: "failed"
    }
}

enum UIUXFindingExpectations {
    static let catalog: UIUXFindingCatalog? = {
        guard let root = UIUXRepo.root() else { return nil }
        guard let data = try? Data(contentsOf: root.appendingPathComponent("qa/uiux/findings.json")) else { return nil }
        return try? JSONDecoder().decode(UIUXFindingCatalog.self, from: data)
    }()

    static let closedIDs = catalog?.findings.filter { $0.expect == "closed" }.map(\.id) ?? []
    static let openIDs = catalog?.findings.filter { $0.expect == "open" }.map(\.id) ?? []
}

final class UIUXScanCache: @unchecked Sendable {
    static let shared = UIUXScanCache()
    private let lock = NSLock()
    private var stored: [UIUXFinding]?

    func findings(root: URL) -> [UIUXFinding] {
        lock.lock()
        defer { lock.unlock() }
        if let stored { return stored }
        let scanned = UIUXAudit.scan(root: root)
        stored = scanned
        return scanned
    }
}

private extension SettingsDesk {
    func returnKeyEffect() -> String { focused?.id ?? "" }
}
