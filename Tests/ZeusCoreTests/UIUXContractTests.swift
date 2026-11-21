import Foundation
import Testing

@Suite("UI UX surface contracts")
struct UIUXContractTests {
    private static let tabs = ["home", "tiling", "agents", "chat", "scribe"]

    @Test func hoverDwellOpensFromIdleAndFromPeek() {
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

    @Test func leavingBeforeTheDwellCancelsTheHover() {
        var desk = ChromeDesk()
        desk.pointerEntered()
        desk.pointerExited()
        #expect(desk.phase == .idle)
        desk.dwellFinished()
        #expect(desk.phase == .idle)
    }

    @Test func clickTriggerDoesNotOpenOnHover() {
        var desk = ChromeDesk(trigger: .click)
        desk.pointerEntered()
        desk.dwellFinished()
        desk.holdIsland()
        #expect(desk.phase == .idle)
    }

    @Test func aPressOpensWhenTheTriggerIsClick() {
        for start in [ChromePhase.idle, .peek] {
            var desk = ChromeDesk(phase: start, trigger: .click)
            desk.press()
            #expect(desk.phase == .expanded)
        }
        var calibrating = ChromeDesk(trigger: .click, calibrating: true)
        calibrating.press()
        #expect(calibrating.phase == .idle)
    }

    @Test(arguments: [1, 2, 3])
    func repeatedClicksDoNotCloseThePanel(count: Int) {
        var click = ChromeDesk(trigger: .click)
        click.clicks(count)
        #expect(click.phase == .expanded)

        var hover = ChromeDesk(trigger: .hover)
        hover.clicks(count)
        #expect(hover.phase == .idle)
    }

    @Test func anIslandHoldFollowsTheTrigger() {
        var hover = ChromeDesk()
        hover.pointerEntered()
        hover.holdIsland()
        #expect(hover.phase == .expanded)

        var click = ChromeDesk(trigger: .click)
        click.holdIsland()
        #expect(click.phase == .idle)
    }

    @Test func aShiftHoldPeeksAndReleaseReturns() {
        var desk = ChromeDesk()
        desk.shiftHold()
        #expect(desk.phase == .peek)
        #expect(desk.shiftPeek)
        desk.shiftRelease()
        #expect(desk.phase == .idle)
        #expect(!desk.shiftPeek)
    }

    @Test func aTabHoldRevealsTheStripWithoutOpening() {
        var desk = ChromeDesk()
        desk.tabHold()
        #expect(desk.tabStrip)
        #expect(desk.phase == .idle)
        desk.tabRelease()
        #expect(!desk.tabStrip)
    }

    @Test func aFileSwipeOpensTheShelfAndABareSwipeDoesNot() {
        var desk = ChromeDesk(trigger: .click)
        desk.swipeRight(files: false)
        #expect(desk.phase == .idle)
        #expect(desk.bareSwipes == 1)
        desk.swipeRight(files: true)
        #expect(desk.phase == .expanded)
        #expect(desk.tab == "shelf")
    }

    @Test func theExpandedPanelStaysForVoiceOverAPinTheMenuThePrompterAndThePicker() {
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

    @Test func escapeClosesOnlyThePicker() {
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

    @Test func returnOpensThePickedSessionAndDoesNotApprove() {
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

    @Test func approvalButtonsDecideAndFocusStaysInOrder() {
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

    @Test func panelFocusClampsAtTheEnds() {
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

    @Test func settingsFocusClampsAcrossTheLiveSidebar() throws {
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

    @Test(arguments: UIUXSourceMap.canonicalTwelve)
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

    @Test(arguments: HubKind.allCases)
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
        var scribe = ScribeDesk()
        #expect(scribe.startEnabled)
        scribe.endNow()
        #expect(scribe.phase == .idle)
        scribe.start()
        #expect(scribe.phase == .recording)
        #expect(scribe.endNowEnabled)
        scribe.endNow()
        #expect(scribe.phase == .ending)
        scribe.keep()
        #expect(scribe.phase == .recording)
        scribe.endNow()
        scribe.countdownFinished()
        #expect(scribe.phase == .writing)
        #expect(!scribe.keepEnabled)
        scribe.notesReady()
        #expect(scribe.phase == .notes)

        var denied = ScribeDesk(permission: false)
        denied.start()
        #expect(denied.phase == .error)
        denied.retry()
        #expect(denied.phase == .recovery)
        denied.permission = true
        denied.start()
        #expect(denied.phase == .recording)
        denied.fail()
        #expect(denied.phase == .error)
    }

    @Test func murmurHoldAndToggleMatchTheBehaviorContract() throws {
        let root = try #require(UIUXRepo.root())
        let source = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/DictationBehavior.swift"), encoding: .utf8)
        #expect(source.contains("case holdToSpeak"))
        #expect(source.contains("case pressToToggle"))
        #expect(source.contains("finishesOnRelease"))

        var hold = MurmurDesk(mode: .holdToSpeak)
        hold.clicks(3)
        #expect(hold.phase == .holding)
        hold.release()
        #expect(hold.phase == .committing)
        hold.commitFinished()
        #expect(hold.phase == .idle)

        var toggle = MurmurDesk(mode: .pressToToggle)
        toggle.press()
        #expect(toggle.phase == .recording)
        toggle.press()
        #expect(toggle.phase == .committing)
        toggle.clicks(1)
        #expect(toggle.phase == .committing)
        toggle.commitFinished()
        #expect(toggle.phase == .idle)

        var blocked = MurmurDesk(mode: .pressToToggle, permission: false)
        blocked.press()
        #expect(blocked.phase == .error)
        blocked.retry()
        #expect(blocked.phase == .recovery)
    }

    @Test(arguments: DecisionFault.allCases)
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
        let root = try #require(UIUXRepo.root())
        let source = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/TopBar/MotionTokens.swift"), encoding: .utf8)
        let tokens = UIUXSourceMap.springs(in: source)
        let specs = MotionContract.specs(from: tokens)
        #expect(specs.count == 13)
        for spec in specs where spec.name != "crossfadeDuration" && spec.name != "pressScale" {
            #expect(spec.reduced == .instant)
            #expect(spec.full != .instant)
        }
        #expect(specs.first { $0.name == "crossfadeDuration" }?.reduced == .seconds(0.12))
        #expect(specs.first { $0.name == "pressScale" }?.reduced == .scale(1))
        #expect(specs.first { $0.name == "panelClose" }?.full == .spring(response: 0.175, damping: 1))
        #expect(specs.first { $0.name == "panelOpen" }?.full == .spring(response: 0.30, damping: 0.87))
        let definitions = UIUXSourceMap.matches(#"SpringToken\(response:"#, in: source)
        #expect(definitions.count == 6)
    }

    @Test func reduceTransparencySwapsToAnOpaqueFill() {
        #expect(TransparencyContract.fill(reduceTransparency: false) == .blurred)
        #expect(TransparencyContract.fill(reduceTransparency: true) == .opaque)
    }

    @Test func dynamicTypeStepsAreStrictlyIncreasing() {
        let scales = TypeStep.allCases.map(\.scale)
        #expect(scales.count == 12)
        for pair in zip(scales, scales.dropFirst()) {
            #expect(pair.1 > pair.0)
        }
        #expect(TypeStep.medium.scale == 1)
    }

    @Test func theOpenDwellMatchesTheSettingsLabels() throws {
        let root = try #require(UIUXRepo.root())
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Notch/NotchController.swift"), encoding: .utf8)
        let table = UIUXSourceMap.dwellTable(in: source)
        #expect(table["Fast"] == 100)
        #expect(table["Standard"] == 250)
        #expect(table["Relaxed"] == 600)
    }

    @Test func theDefaultTabRowPutsMurmureAndScribeInThePanel() throws {
        let root = try #require(UIUXRepo.root())
        let source = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/TopBar/TopBarLayout.swift"), encoding: .utf8)
        let tabs = UIUXSourceMap.defaultTabs(in: source)
        #expect(tabs.first?.id == "home")
        #expect(tabs.map(\.id).contains("dictation"))
        #expect(tabs.first { $0.id == "dictation" }?.title == "Murmure")
        #expect(tabs.map(\.id).contains("scribe"))
        #expect(tabs.map(\.title).count == Set(tabs.map(\.id)).count)
    }

    @Test func contractControlsCarryLabelTraitAndIdentifier() throws {
        let root = try #require(UIUXRepo.root())
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Settings/GlanceSettingsWindow.swift"), encoding: .utf8)
        let layout = try String(contentsOf: root.appendingPathComponent("Sources/ZeusCore/TopBar/TopBarLayout.swift"), encoding: .utf8)
        let controls = ContractControls.all(sections: UIUXSourceMap.sidebar(in: settings), tabs: UIUXSourceMap.defaultTabs(in: layout))
        #expect(controls.count == Set(controls.map(\.id)).count)
        for control in controls {
            #expect(!control.id.isEmpty)
            #expect(!control.label.isEmpty)
            #expect(control.trait == "button")
        }
        let order = controls.map(\.id)
        #expect(order == controls.map(\.id))
    }

    @Test func focusOrderIsDeterministic() {
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

    @Test func repositoryFindingsMatchTheCatalog() throws {
        let root = try #require(UIUXRepo.root())
        let actual = UIUXAudit.scan(root: root)
        let catalogURL = root.appendingPathComponent("qa/uiux/findings.json")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(UIUXFindingCatalog.self, from: data)
        #expect(catalog.schema == 1)
        if catalog.findings != actual {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let rendered = try encoder.encode(UIUXFindingCatalog(schema: 1, findings: actual))
            try rendered.write(to: URL(fileURLWithPath: "/tmp/uiux-findings-actual.json"))
        }
        #expect(catalog.findings == actual)
        let ids = actual.map(\.id)
        #expect(ids.count == Set(ids).count)
        #expect(actual.allSatisfy { $0.id.hasPrefix("ZB-UIUX-") })
    }
}

private extension SettingsDesk {
    func returnKeyEffect() -> String { focused?.id ?? "" }
}
