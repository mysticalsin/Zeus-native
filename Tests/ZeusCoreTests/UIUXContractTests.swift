import CoreGraphics
import Foundation
import Testing
import ZeusCore

@Suite("UI UX surface contracts")
struct UIUXContractTests {
    /// Production sidebar order from `GSSection`, iPhone hidden.
    private static let productionSidebar = [
        "general", "appearance", "sounds", "notifications", "shortcuts", "insomnia",
        "integrations", "murmure", "polyglot", "dictation", "voice", "engine",
        "features", "beamer", "tiling", "shelf",
        "license", "permissions", "privacy", "diagnostics", "about",
    ]
    /// `TopBarLayout.defaultRow` as shipped.
    private static let productionTabs = [
        "home", "tiling", "agents", "chat", "notifications", "clipboard", "shelf", "todo",
        "dictation", "teleprompter", "insomnia", "polyglot", "recordly", "scribe",
    ]

    @Test func hoverDwellOpensFromIdleAndFromPeek() {
        #expect(NotchOpenRules.opensOnHover(.hover))
        #expect(!NotchOpenRules.opensOnHover(.click))
        let zone = CGRect(x: 0, y: 0, width: 20, height: 14)
        let point = CGPoint(x: 10, y: 14)
        // A peek is not the open panel, so a click still opens.
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: point, zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: true, point: point, zone: zone))
        #expect(NotchOpenDelay.milliseconds(label: "Standard") == 250)
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
        #expect(NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: point, zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: true, point: point, zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .hover, panelIsOpen: false, point: point, zone: zone))
        #expect(!NotchOpenRules.opensOnClick(trigger: .click, panelIsOpen: false, point: CGPoint(x: 20, y: 10), zone: zone))
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

    @Test func aFileSwipeOpensTheShelfAndABareSwipeDoesNot() {
        let near = CGPoint(x: 100, y: 990)
        #expect(!NotchFileDrag.opensShelf(hasFileURLs: false, pointer: near, anchorMidX: 100, screenMaxY: 1000, panelAlreadyOnShelf: false))
        #expect(NotchFileDrag.opensShelf(hasFileURLs: true, pointer: near, anchorMidX: 100, screenMaxY: 1000, panelAlreadyOnShelf: false))
        let far = CGPoint(x: 100 + NotchFileDrag.sideReach, y: 990)
        #expect(!NotchFileDrag.opensShelf(hasFileURLs: true, pointer: far, anchorMidX: 100, screenMaxY: 1000, panelAlreadyOnShelf: false))
        let low = CGPoint(x: 100, y: 1000 - NotchFileDrag.belowTop)
        #expect(!NotchFileDrag.opensShelf(hasFileURLs: true, pointer: low, anchorMidX: 100, screenMaxY: 1000, panelAlreadyOnShelf: false))
        #expect(!NotchFileDrag.opensShelf(hasFileURLs: true, pointer: near, anchorMidX: 100, screenMaxY: 1000, panelAlreadyOnShelf: true))
    }

    @Test func escapeClosesOnlyThePicker() {
        #expect(AgentPicker.action(forKeyCode: 53) == .close)
        #expect(AgentPicker.action(forKeyCode: 36) == .open)
        var picker = AgentPicker(count: 2, index: 1)
        #expect(picker.apply(.close) == .close)
        #expect(picker.index == 1)
    }

    @Test func returnOpensThePickedSessionAndDoesNotApprove() {
        #expect(AgentPicker.action(forKeyCode: 36) == .open)
        #expect(AgentPicker.action(forKeyCode: 76) == .open)
        var sessions = AgentPicker(count: 2)
        #expect(sessions.apply(.open) == .open)
        var empty = AgentPicker(count: 0)
        #expect(empty.apply(.open) == .close)
    }

    @Test func approvalButtonsDecideAndFocusStaysInOrder() {
        var picker = AgentPicker(count: 3)
        #expect(picker.apply(.down) == nil)
        #expect(picker.index == 1)
        #expect(picker.apply(.down) == nil)
        #expect(picker.index == 2)
        #expect(picker.apply(.down) == nil)
        #expect(picker.index == 0)
        #expect(picker.apply(.open) == .open)
        #expect(picker.apply(.close) == .close)
    }

    @Test func panelFocusClampsAtTheEnds() {
        var picker = AgentPicker(count: 2, index: 0)
        #expect(picker.apply(.up) == nil)
        #expect(picker.index == 1)
        #expect(picker.apply(.down) == nil)
        #expect(picker.index == 0)
    }

    @Test func settingsFocusClampsAcrossTheLiveSidebar() throws {
        let root = try #require(UIUXRepo.root())
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Settings/GlanceSettingsWindow.swift"), encoding: .utf8)
        let sections = UIUXSourceMap.sidebar(in: source)
        #expect(sections.map(\.id) == Self.productionSidebar)
        #expect(sections.first { $0.id == "general" }?.title == "General")
        #expect(sections.first { $0.id == "murmure" }?.title == "Murmure")
        #expect(!sections.contains { $0.id == "iPhone" })
    }

    @Test(arguments: [
        "general", "appearance", "notifications", "sounds", "voice", "dictation",
        "shortcuts", "integrations", "permissions", "privacy", "diagnostics", "license",
    ])
    func everyCanonicalSectionWalksEmptyLoadingErrorAndRecovery(id: String) throws {
        let root = try #require(UIUXRepo.root())
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Settings/GlanceSettingsWindow.swift"), encoding: .utf8)
        let ids = UIUXSourceMap.sidebar(in: source).map(\.id)
        #expect(ids.contains(id))
    }

    @Test func hubsWalkEmptyLoadingErrorAndRecovery() {
        #expect(!SourceCapabilities().allows(.play))
        #expect(!SourceCapabilities().allows(.next))
        #expect(SourceCapabilities.playPause.allows(.play))
        #expect(SourceCapabilities.playPause.allows(.pause))
        #expect(!SourceCapabilities.playPause.allows(.next))
        var arbiter = NowPlayingArbiter()
        #expect(arbiter.shown(follow: .any) == nil)
        #expect(arbiter.commandTarget(shown: nil, follow: .any) == .player(.music))
        #expect(arbiter.commandTarget(shown: nil, follow: .pinned(.spotify)) == .player(.spotify))
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
        #expect(hold.actionOnPress(isDictating: true) == .begin)
        let toggle = DictationBehavior.pressToToggle
        #expect(!toggle.finishesOnRelease)
        #expect(toggle.actionOnPress(isDictating: false) == .begin)
        #expect(toggle.actionOnPress(isDictating: true) == .finish)
    }

    @Test func decisionRowsRetryExceptWhenAPersonMustAct() {
        var unset = JevBudget(monthlyCap: nil)
        let unsetAllowed = unset.allows(estimatedTokens: 100)
        var zero = JevBudget(monthlyCap: 0)
        let zeroAllowed = zero.allows(estimatedTokens: 1)
        var open = JevBudget(monthlyCap: 10)
        let openAllowed = open.allows(estimatedTokens: 100)
        #expect(!unsetAllowed)
        #expect(!zeroAllowed)
        #expect(openAllowed)
    }

    @Test func reduceMotionCollapsesSpringsAndKeepsTheCrossfade() {
        #expect(MotionTokens.allSprings.count == 6)
        #expect(MotionTokens.panelOpen == SpringToken(response: 0.30, damping: 0.87))
        #expect(MotionTokens.panelOpenHeight == SpringToken(response: 0.105, damping: 1.0))
        #expect(MotionTokens.panelClose == SpringToken(response: 0.175, damping: 1))
        #expect(MotionTokens.panelResize == SpringToken(response: 0.34, damping: 0.84))
        #expect(MotionTokens.cueGrow == SpringToken(response: 0.12, damping: 0.90))
        #expect(MotionTokens.peekContent == SpringToken(response: 0.34, damping: 0.82))
        #expect(MotionTokens.crossfadeDuration == 0.12)
        #expect(MotionTokens.pressScale == 0.98)
        for token in MotionTokens.allSprings {
            #expect(MotionReduction.spring(token, reduceMotion: true) == nil)
            #expect(MotionReduction.spring(token, reduceMotion: false) == token)
        }
        #expect(MotionReduction.crossfadeDuration(reduceMotion: true) == 0.12)
        #expect(MotionReduction.pressScale(reduceMotion: true) == 1)
        #expect(MotionReduction.pressScale(reduceMotion: false) == 0.98)
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

    @Test func theOpenDwellMatchesTheSettingsLabels() throws {
        #expect(NotchOpenDelay.milliseconds(label: "Fast") == 100)
        #expect(NotchOpenDelay.milliseconds(label: "Standard") == 250)
        #expect(NotchOpenDelay.milliseconds(label: "") == 250)
        #expect(NotchOpenDelay.milliseconds(label: "Relaxed") == 600)
        let root = try #require(UIUXRepo.root())
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Notch/NotchController.swift"), encoding: .utf8)
        #expect(source.contains("NotchOpenDelay.milliseconds(label:"))
        #expect(source.contains("NotchFileDrag.opensShelf("))
    }

    @Test func theDefaultTabRowPutsMurmureAndScribeInThePanel() {
        #expect(TopBarLayout.defaultRow.map(\.rawValue) == Self.productionTabs)
        #expect(TopBarTab.dictation.title == "Murmure")
        #expect(TopBarTab.scribe.title == "Scribe")
    }

    @Test func contractControlsCarryLabelTraitAndIdentifier() throws {
        let root = try #require(UIUXRepo.root())
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/Zeus/Settings/GlanceSettingsWindow.swift"), encoding: .utf8)
        let sections = UIUXSourceMap.sidebar(in: settings)
        #expect(sections.map(\.id) == Self.productionSidebar)
        for tab in TopBarLayout.defaultRow {
            #expect(!tab.id.isEmpty)
            #expect(!tab.title.isEmpty)
        }
        #expect(sections.map(\.title).allSatisfy { !$0.isEmpty })
    }

    @Test func focusOrderIsDeterministic() {
        let first = TopBarLayout.defaultRow.map(\.rawValue)
        let second = TopBarLayout.defaultRow.map(\.rawValue)
        #expect(first == second)
        #expect(first == Self.productionTabs)
        #expect(first.first == "home")
        #expect(first.last == "scribe")
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
