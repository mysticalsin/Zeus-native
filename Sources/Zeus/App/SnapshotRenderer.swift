import AppKit
import CryptoKit
import SwiftUI
import ZeusCore

/// Snapshot mode only: Glance Settings page headings report which pane they drew, so the harness can
/// check that a capture really shows the pane it is named after (see `SnapshotRenderer.save(pane:)`).
@MainActor
enum SnapshotPaneProbe {
    private(set) static var seen: Set<String> = []
    static func reset() { seen = [] }
    static func note(_ pane: String) {
        guard TopBarStyle.isSnapshot else { return }
        seen.insert(pane)
    }
}

/// A Glance Settings page's panel background and content, alone, with no `ScrollView` -- see the
/// long comment where this is used in `SnapshotRenderer.runIfRequested()` for why: `ImageRenderer`
/// renders a `ScrollView`'s content as blank on its one-shot headless pass, so this exists purely
/// so the snapshot harness has a reliable (if chrome-less) way to see each page's real content.
private struct GSPageSnapshot: View {
    let section: GSSection
    let context: GSContext
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: GS.panelRadius, style: .continuous).fill(GS.panel)
            GSPageView(section: section, navigation: GSNavigation(), context: context)
                .padding(.leading, GS.pagePadding)
                .padding(.trailing, 28)
                .padding(.top, 25)
                .padding(.bottom, 32)
        }
        .background(GS.window)
    }
}

/// `Zeus --snapshots <dir>` renders every notch and spark state to PNG and quits.
/// Used to review the look without Screen Recording permission or a live demo.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshots"), flag + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var scales: [CGFloat] = [1, 2]
        if let scaleFlag = arguments.firstIndex(of: "--snapshot-scales"), scaleFlag + 1 < arguments.count {
            let parsed = arguments[scaleFlag + 1].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { CGFloat($0) }
            if !parsed.isEmpty { scales = parsed }
        }
        // The ~150 `save(...)` calls below (everything that isn't `saveSurface`) read these two
        // so every one of them also lands in `<dir>/<n>x/<name>.png`, not just a flat 2x copy.
        activeScales = scales
        snapshotsDirectory = directory
        snapshotMatch = nil
        if let matchFlag = arguments.firstIndex(of: "--snapshot-match"), matchFlag + 1 < arguments.count {
            snapshotMatch = arguments[matchFlag + 1]
        }

        // `save(...)` (scale: nil, below) now does exactly this fan-out itself, so every named
        // surface call below is the same thing with a bare name instead of a full URL.
        func saveSurface<V: View>(_ view: V, size: CGSize, name: String) {
            save(view, size: size, to: directory.appendingPathComponent("\(name).png"))
        }

        let notch = CGSize(width: 185, height: 32)
        TopBarStyle.isSnapshot = true
        for (name, model) in notchStates() {
            save(NotchStage(model: model, notch: notch), size: CGSize(width: 960, height: 400 + (model.approval?.extraHeight ?? 0)),
                 to: directory.appendingPathComponent("notch-\(name).png"))
        }
        // The top bar: closed wings and cues, then every page opened.
        TopBarStyle.isSnapshot = true
        GlassFonts.register()
        for (name, model, topBar) in topBarStates() {
            let tall = model.approval != nil && model.presentation == .panel
            let wide = name.hasPrefix("4") || name.hasPrefix("5")
            if name.contains("waves") { // the Waves tab in each of its three styles
                SettingsStore.shared.set(AudioSpectrumService.styleKey, name.hasSuffix("-wave") ? "Wave" : name.hasSuffix("-mirror") ? "Mirror" : "Bars")
            }
            save(NotchStage(model: model, topBar: topBar, notch: notch),
                 size: wide ? CGSize(width: 1000, height: 120) : CGSize(width: 960, height: tall ? 520 : 400),
                 to: directory.appendingPathComponent("topbar-\(name).png"))
        }
        // Home customisation: widgets, variants and backdrops (settings are global, so each state sets them as it renders).
        renderHomeStates(into: directory, notch: notch)
        renderParityStates(into: directory, notch: notch)
        // The agent hub: sessions with a reply field, then the New chat form.
        let hub = AgentHub.shared
        let hubStarted = Date().addingTimeInterval(-300)
        hub.sessionsOverride = [
            NotchModel.Session(id: "cc", agent: "Claude Code", project: "zeus", task: "npm run build", status: .working, startedAt: hubStarted),
            NotchModel.Session(id: "cx", agent: "Codex", project: "website", task: "Rate limit reached", status: .failed, startedAt: hubStarted, reason: "Rate limit reached"),
            NotchModel.Session(id: "cu", agent: "Cursor Agent", project: "api", task: "refactor auth", status: .stalled, startedAt: hubStarted, reason: "No activity for 5 min"),
        ]
        AgentTerminals.shared.remember(TerminalInfo(bundleID: "com.apple.Terminal", program: "Apple_Terminal", sessionID: nil, tty: "/dev/ttys004"), for: "cc")
        hub.selectedSession = "cc"
        hub.replyDraft = "also update the changelog"
        for (name, creating) in [("chat-hub", false), ("chat-newchat", true)] {
            let model = NotchModel(), topBar = TopBarModel()
            topBar.selectedTab = .chat
            model.presentation = .panel
            hub.creating = creating
            if creating {
                hub.newTool = .codex
                hub.newDirectory = "/Users/fixture/Projects/Zeus"
                hub.newInstruction = "fix the failing tests"
            }
            save(NotchStage(model: model, topBar: topBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent("agents-\(name).png"))
        }
        hub.creating = false
        hub.sessionsOverride = nil
        // The avatar: every state in the closed notch, in the open header, and as the cursor buddy.
        AvatarStatus.shared.alwaysInNotch = true
        for (index, state) in AvatarState.allCases.enumerated() {
            AvatarStatus.shared.pinned = state
            let tag = String(format: "%02d-%@", index + 1, state.rawValue)
            save(NotchStage(model: NotchModel(), topBar: TopBarModel(), notch: notch), size: CGSize(width: 640, height: 120),
                 to: directory.appendingPathComponent("avatar-notch-\(tag).png"))
            let buddy = BuddyModel()
            buddy.hasAppeared = true
            buddy.position = CGPoint(x: 60, y: 60)
            save(BuddyStage(model: buddy, frame: CGRect(x: 0, y: 0, width: 120, height: 120)), size: CGSize(width: 120, height: 120),
                 to: directory.appendingPathComponent("avatar-buddy-\(tag).png"))
        }
        // Mini ZEUS: four moments of every state's motion side by side, 22 pt as in the notch.
        for (index, state) in AvatarState.allCases.enumerated() {
            let strip = HStack(spacing: 18) {
                ForEach([0.0, 0.9, 2.3, 3.6], id: \.self) { t in MiniMascotView(state: state, size: 22, frameTime: t) }
            }
            .frame(width: 200, height: 44).background(Color.black)
            save(strip, size: CGSize(width: 200, height: 44),
                 to: directory.appendingPathComponent(String(format: "mini-frames-%02d-%@.png", index + 1, state.rawValue)))
        }
        let sleeping = HStack(spacing: 18) {
            ForEach([0.0, 0.8, 1.6, 2.4], id: \.self) { t in LivingAvatar(state: .idle, size: 22, asleep: true, frameTime: t) }
        }
        .frame(width: 200, height: 44).background(Color.black)
        save(sleeping, size: CGSize(width: 200, height: 44), to: directory.appendingPathComponent("mini-frames-14-sleeping.png"))
        AvatarStatus.shared.pinned = .thinking
        let open = NotchModel()
        open.presentation = .panel
        save(NotchStage(model: open, topBar: TopBarModel(), notch: notch), size: CGSize(width: 960, height: 400),
             to: directory.appendingPathComponent("avatar-open-thinking.png"))
        AvatarStatus.shared.pinned = nil
        AvatarStatus.shared.alwaysInNotch = true // the shipped default

        for (name, model) in buddyStates() {
            let frame = CGRect(x: 0, y: 0, width: 420, height: 220)
            save(BuddyStage(model: model, frame: frame), size: frame.size,
                 to: directory.appendingPathComponent("spark-\(name).png"))
        }
        // The floating teleprompter, mid-read.
        let prompter = PrompterWindowModel(topBar: TopBarModel())
        prompter.viewHeight = 262
        prompter.notice = "Follow my words"
        save(PrompterWindowView(model: prompter, actions: .preview).background(Color(hex: 0x1B2030)), size: CGSize(width: 640, height: 300),
             to: directory.appendingPathComponent("prompter-window.png"))
        // Sticky notes: preview, editing on the right edge, and the save-to-brain sheet.
        let stickyActions = StickyActions(changed: {}, toggleEdge: {}, delete: {}, new: {}, saveToBrain: {})
        let stickyText = "# Launch checklist\n- [x] Notch cards\n- [ ] Stickies **today**\n\nAsk Devon about `routines`."
        save(StickyView(state: StickyState(note: StickyNote(text: stickyText, tint: .bolt), editing: false), actions: stickyActions)
                .padding(16).background(Color(hex: 0x1B2030)), size: CGSize(width: 300, height: 260),
             to: directory.appendingPathComponent("sticky-preview.png"))
        save(StickyView(state: StickyState(note: StickyNote(text: stickyText, tint: .sky, placement: .edge(.right, top: 40)), editing: false), actions: stickyActions)
                .padding(16).background(Color(hex: 0x1B2030)), size: CGSize(width: 320, height: 260),
             to: directory.appendingPathComponent("sticky-edge.png"))
        // The correctable dictation preview.
        let preview = DictationPreviewCard.State()
        preview.text = "Hey Devon, the notch build is ready for you to try. Let me know what feels off."
        preview.modeName = "Message"
        save(DictationPreviewView(state: preview, insert: {}, cancel: {}).padding(16).background(Color(hex: 0x1B2030)),
             size: CGSize(width: 472, height: 200), to: directory.appendingPathComponent("dictation-preview.png"))
        // A routine's quiet result card.
        let run = RoutineRun(routineID: UUID(), routineName: "Weekday repo summary", date: Date(), engine: "codex",
                             output: "**3 repos changed** since yesterday:\n- zeus: stickies and routines landed\n- site: copy fixes\n- soul: no changes",
                             failed: false)
        save(RoutineCardView(run: run, dismiss: {}).padding(16).background(Color(hex: 0x1B2030)), size: CGSize(width: 440, height: 240),
             to: directory.appendingPathComponent("routine-card.png"))
        // The morning brief card.
        let morning = Date()
        let brief = MorningBrief.build(
            now: Calendar.current.date(bySettingHour: 8, minute: 5, second: 0, of: morning) ?? morning,
            events: [BriefEvent(title: "Standup", start: Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: morning) ?? morning,
                                end: Calendar.current.date(bySettingHour: 9, minute: 45, second: 0, of: morning) ?? morning, hasCall: true),
                     BriefEvent(title: "Lunch with Devon", start: Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: morning) ?? morning,
                                end: Calendar.current.date(bySettingHour: 13, minute: 30, second: 0, of: morning) ?? morning)],
            todos: [BriefTodo(id: "1", title: "Send the ZEUS build to testers", due: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: morning))],
            name: "Tony")
        save(BriefCardView(brief: brief, dismiss: {}).padding(20).background(Color(hex: 0x1B2030)), size: CGSize(width: 460, height: 260),
             to: directory.appendingPathComponent("brief-card.png"))
        // "Teach ZEUS about you", each slide.
        for step in AboutYouModel.Step.allCases {
            let about = AboutYouModel()
            about.vault = URL(fileURLWithPath: NSHomeDirectory() + "/Documents/brain")
            about.summary = .init(notes: 1284, folders: ["10_Projects", "20_Areas", "30_Resources"], hasInbox: true, truncated: false)
            about.scanning = false
            about.profile = AboutYouProfile(name: "Tony", work: "Building ZEUS", helpWith: "Mornings and agents")
            about.step = step
            save(AboutYouView(model: about, close: {}), size: CGSize(width: 560, height: 470),
                 to: directory.appendingPathComponent("about-you-\(step.rawValue).png"))
        }

        // Panel, setup and settings, as they look with nothing granted yet.
        let permissions = PermissionsModel()
        let connections = ConnectionsModel()
        let panel = PanelView(connections: connections, permissions: permissions, preferences: .shared,
                              playDemo: {}, openSetup: {}, openSettings: {}, quit: {})
        save(panel.fixedSize().frame(minHeight: 0, maxHeight: .infinity, alignment: .top), size: CGSize(width: Theme.panelWidth, height: 900),
             to: directory.appendingPathComponent("panel.png"))
        for step in OnboardingModel.Step.allCases {
            let model = OnboardingModel()
            model.step = step
            if step == .welcome { model.waved = true }
            if step == .theme { model.themePreviewed = true }
            if step == .learn { model.nameDraft = "Tony"; model.celebrated = true }
            let view = OnboardingView(model: model, permissions: permissions, preferences: .shared, watchDemo: {}, finish: {})
            save(view, size: CGSize(width: 960, height: 760),
                 to: directory.appendingPathComponent("setup-\(step.rawValue).png"))
        }
        // Settings, every section, in its window frame.
        seedFlightRecorder()
        // The live (Glance-style) Settings pages this round changed.
        do {
            let context = GSContext(services: OnboardingServices(permissions: PermissionsModel()))
            let nav = GSNavigation()
            for section in [GSSection.appearance, .diagnostics, .privacy, .sounds, .general, .about] {
                nav.section = section
                save(GlanceSettingsRoot(navigation: nav, context: context), size: GS.size, scale: 1, pane: section,
                     to: directory.appendingPathComponent("gs-\(section.rawValue).png"))
            }
        }
        let navigation = SettingsNavigation()
        let obServices = OnboardingServices(permissions: permissions)
        let gsNav = GSNavigation()
        let gsContext = GSContext(services: obServices)
        // Numbered `settings-NN-*` PNGs (QA visual table) for legacy sections that have a live Glance page of
        // the same name. A legacy section that only *aliases* to another page (topBar, todo, memory,
        // teleprompter, agents, stickies, routines, keepAwake, assistant, intelligence, interview, about)
        // used to be saved as that other page under its own name, which is how `settings-08..18` ended up
        // showing Features, Integrations or Appearance. Those are skipped now (and listed on stdout);
        // `settings-legacy-*` still covers the old views. Every pane capture asserts the pane it shows.
        for (index, section) in SettingsNavigation.Section.allCases.enumerated() {
            let fileName = String(format: "settings-%02d-%@", index + 1, section.rawValue)
            guard let glanceSection = GSSection.allCases.first(where: { $0.rawValue.lowercased() == section.rawValue.lowercased() }) else {
                print("snapshot: skipped \(fileName): legacy section '\(section.rawValue)' has no live pane of its own")
                continue
            }
            gsNav.section = glanceSection
            save(GlanceSettingsRoot(navigation: gsNav, context: gsContext), size: GS.size, pane: glanceSection,
                 to: directory.appendingPathComponent("\(fileName).png"))
            save(GSPageSnapshot(section: glanceSection, context: gsContext),
                 size: CGSize(width: GS.panelFrame.width, height: GlanceSettingsSnapshotHeight.height(for: glanceSection.rawValue)),
                 scale: 1, pane: glanceSection,
                 to: directory.appendingPathComponent(String(format: "settings-full-%02d-%@.png", index + 1, section.rawValue)))
        }
        // The legacy sidebar search (legacy view, not a Glance pane). The legacy reset confirmation is an
        // alert, which an offscreen render cannot draw, so it is no longer captured: the old
        // `settings-17-reset-confirm.png` was just the Appearance page with no dialog.
        navigation.section = .sounds
        navigation.query = "sound"
        save(WindowStage(content: SettingsView(connections: connections, preferences: .shared, permissions: permissions, topBar: TopBarModel(),
                                               navigation: navigation, openSetup: {})),
             size: SettingsView.size, to: directory.appendingPathComponent("settings-legacy-search.png"))
        navigation.query = ""

        // Canonical named surfaces for QA parity checks
        for step in OnboardingStep.allCases {
            let flow = OnboardingFlow()
            flow.step = step
            // QA7 round 11 (report-11.md): V3-ORDER.md names these surfaces exactly
            // `onboarding-welcome`/`-murmure`/`-agents`/`-day`/`-halo`/`-sounds`; the step's *case
            // name* (`welcome`, `murmure`, ...), not its Int `rawValue` (`0`, `1`, ...) used before.
            // QA looked for `onboarding-welcome.png` and only found `onboarding-0.png`, scored a
            // "no 1x render" FAIL on every onboarding surface even though the content itself (once
            // found under the old numeric name) was reviewed and partly passed.
            saveSurface(OnboardingRoot(flow: flow, services: obServices, finish: {}), size: CGSize(width: 960, height: 760), name: "onboarding-\(step)")
        }

        let permConfigs: [(String, String, String)] = [
            ("perm-accessibility", "Accessibility", "hand.raised.fill"),
            ("perm-microphone", "Microphone", "mic.fill"),
            ("perm-speech", "Speech Recognition", "waveform"),
            ("perm-screen-recording", "Screen Recording", "display"),
            ("perm-input-monitoring", "Input Monitoring", "keyboard.fill"),
            ("perm-automation", "Automation", "applescript.fill")
        ]
        for (permName, title, sym) in permConfigs {
            saveSurface(PermissionSnapshotView(name: title, symbol: sym), size: CGSize(width: 420, height: 160), name: permName)
        }
        saveSurface(DragHelperView(), size: CGSize(width: 260, height: 160), name: "drag-helper")

        for section in GSSection.allCases where section.isShown {
            gsNav.section = section
            save(GlanceSettingsRoot(navigation: gsNav, context: gsContext), size: GS.size, pane: section,
                 to: directory.appendingPathComponent("settings-\(section.rawValue).png"))
            // QA round 10 (report-10.md VISUAL section, "blank content pane"): `ImageRenderer`
            // never lays out `GSPanelHost`'s `ScrollView` on its one-shot headless render, so the
            // `settings-\(section.rawValue)` capture just above is blank for *every* GSSection,
            // not only the 6 (murmure, polyglot, engine, features, beamer, insomnia) report-10
            // happened to catch -- the other 19 were masked by the exact filename collision fixed
            // just below (QA was unknowingly grading the deprecated `SettingsView`'s screenshot,
            // which has no `ScrollView`-in-`ImageRenderer` problem, instead of noticing this one
            // was empty). Proven empirically: `zeus --settings-only --settings-section murmure`
            // (a real, live, on-screen window, no `ImageRenderer` involved) shows this exact page
            // fully populated. Confirmed by generating `--snapshots` fresh locally and reading
            // `gs-general.png`/`gs-appearance.png` (names this file already wrote uniquely, never
            // touched by the collision) -- both blank too, for the plainest sections there are.
            // Mirrors this file's own existing `settings-full-NN-*` workaround for the identical
            // `ScrollView` limitation on the deprecated view ("whole page, unclipped, so every
            // option shows (live has a scroll view)", above): capture the page's content alone,
            // at a generous fixed height, with no `ScrollView` for `ImageRenderer` to misjudge.
            save(GSPageSnapshot(section: section, context: gsContext),
                 size: CGSize(width: GS.panelFrame.width, height: GlanceSettingsSnapshotHeight.height(for: section.rawValue)), pane: section,
                 to: directory.appendingPathComponent("settings-full-\(section.rawValue).png"))
        }
        // QA round 10 (report-10.md VISUAL section): this loop and the `GSSection.allCases` loop
        // just above it both used the bare name `"settings-\(section.rawValue)"`. `SettingsView`
        // (this one, the deprecated pre-Glance sidebar window) and `GlanceSettingsRoot` (the live
        // one) share several section names (voice, dictation, integrations, permissions, privacy,
        // iPhone, diagnostics, license, general, appearance, notifications, sounds, shortcuts) --
        // for every one of those, this loop silently overwrote the live Glance page's screenshot
        // with the deprecated view's, so QA was unknowingly reviewing the wrong UI for most of the
        // Settings window. (The handful of sections unique to `GSSection` -- murmure, polyglot,
        // engine, features, beamer, insomnia -- were never overwritten, which is exactly why those
        // specific pages' *own*, unclobbered, blank-content-pane bug was visible in isolation.)
        // Keep both: this deprecated view still backs the live `Cmd+,` window pending its full
        // Glance migration, so its real screenshots stay useful, just under a name that can never
        // collide with the current one QA should actually be grading.
        for section in SettingsNavigation.Section.allCases {
            let sNav = SettingsNavigation()
            sNav.section = section
            let sView = SettingsView(connections: connections, preferences: .shared, permissions: permissions, topBar: TopBarModel(), navigation: sNav, openSetup: {})
            saveSurface(WindowStage(content: sView), size: SettingsView.size, name: "settings-legacy-\(section.rawValue)")
        }

        let notchClosed = NotchModel()
        notchClosed.presentation = .closed
        saveSurface(NotchStage(model: notchClosed, topBar: TopBarModel(), notch: notch), size: CGSize(width: 960, height: 120), name: "notch-closed")

        let notchPeek = NotchModel()
        notchPeek.presentation = .peek
        saveSurface(NotchStage(model: notchPeek, topBar: TopBarModel(), notch: notch), size: CGSize(width: 960, height: 120), name: "notch-peek")

        let notchPanel = NotchModel()
        let panelTop = TopBarModel()
        notchPanel.presentation = .panel
        saveSurface(NotchStage(model: notchPanel, topBar: panelTop, notch: notch), size: CGSize(width: 960, height: 400), name: "notch-panel")

        let volNotch = NotchModel()
        let volTop = TopBarModel()
        volTop.show(.volume(0.75, muted: false))
        saveSurface(NotchStage(model: volNotch, topBar: volTop, notch: notch), size: CGSize(width: 960, height: 120), name: "hud-volume")

        let brightNotch = NotchModel()
        let brightTop = TopBarModel()
        brightTop.show(.brightness(0.75))
        saveSurface(NotchStage(model: brightNotch, topBar: brightTop, notch: notch), size: CGSize(width: 960, height: 120), name: "hud-brightness")

        // Item 8's own row ("orb: the real voice orb or recorder pill view, not a MascotTile") and
        // P0 item F.3 (QA7): the real `RecorderPillView`, with its real `ThinkingOrbView`, in every
        // state Tony asked to see -- never the `ObsidianOrbSnapshotView` placeholder this used to be.
        func pill(_ name: String, _ configure: (TopBarModel) -> Void) {
            let top = TopBarModel()
            configure(top)
            saveSurface(RecorderPillView(topBar: top).padding(20).background(Color(hex: 0x1B2030)), size: CGSize(width: 332, height: 88), name: name)
        }
        pill("orb") { $0.dictationPhase = .listening; $0.dictationLevel = 0.7 } // the default/hero shot
        pill("murmur-orb-idle") { $0.dictationPhase = .listening; $0.dictationLevel = 0 }
        pill("murmur-orb-listening-loud") { $0.dictationPhase = .listening; $0.dictationLevel = 0.9 }
        pill("murmur-orb-listening-quiet") { $0.dictationPhase = .listening; $0.dictationLevel = 0.08 }
        pill("murmur-orb-transcribing") { $0.dictationPhase = .transcribing }
        pill("murmur-orb-no-speech") { $0.dictationPhase = .failed("No speech was heard.") }

        let murmurNav = GSNavigation()
        murmurNav.section = .murmure
        save(GlanceSettingsRoot(navigation: murmurNav, context: gsContext), size: GS.size, pane: .murmure,
             to: directory.appendingPathComponent("murmur-settings.png"))

        let murmurCardState = DictationPreviewCard.State()
        murmurCardState.text = "Send the draft by Friday."
        murmurCardState.modeName = "Murmure"
        saveSurface(DictationPreviewView(state: murmurCardState, insert: {}, cancel: {}).padding(20).background(Color(hex: 0x1B2030)), size: CGSize(width: 520, height: 180), name: "murmur-overlay")

        // QA tooling gate: a capture that shows the wrong pane, or two panes with identical bytes, fails the run.
        if !harnessFailures.isEmpty {
            fputs("snapshot harness FAILED (\(harnessFailures.count) problem(s)):\n", stderr)
            for failure in harnessFailures { fputs("  - \(failure)\n", stderr) }
            exit(1)
        }
        return true
    }

    /// `Zeus --engine-logos <dir>` writes N7 proof PNGs (light/dark at 2x and 4x) and quits.
    static func runEngineLogosIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--engine-logos"), flag + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        do {
            let paths = try EngineBrandSnapshotExport.writeRows(to: directory, scales: [2, 4])
            print(paths.joined(separator: "\n"))
        } catch {
            fputs("engine-logos export failed: \(error)\n", stderr)
            exit(1)
        }
        return true
    }

    /// Shared with `runIfRequested`: every plain `save(...)` call below fans out across these
    /// scales (into `<dir>/<n>x/<name>.png`) unless it passes an explicit `scale:`.
    private static var activeScales: [CGFloat] = [1, 2]
    private static var snapshotsDirectory: URL!
    /// Every pane-identity or duplicate-bytes problem found this run; a non-empty list fails the run.
    private static var harnessFailures: [String] = []
    /// SHA-256 of each pane capture's bytes (per size and scale) to the pane that produced it: two
    /// different panes with the same bytes mean one capture is showing the wrong page.
    private static var paneByDigest: [String: String] = [:]
    /// When set (`--snapshot-match voice`), only file names containing this text are written.
    private static var snapshotMatch: String?

    /// `scale: nil` (the default) renders at every `activeScales` entry into its own `<n>x`
    /// subfolder, plus one flat legacy copy at the highest scale, exactly like `saveSurface`.
    /// Passing an explicit `scale:` renders once, at that scale, to `url` only (used by the
    /// handful of callers that need one specific pixel ratio, e.g. a 1x-only full-page render).
    private static func save<V: View>(_ view: V, size: CGSize, scale: CGFloat? = nil, pane: GSSection? = nil, to url: URL) {
        if let snapshotMatch, !url.lastPathComponent.localizedCaseInsensitiveContains(snapshotMatch) { return }
        if let scale {
            writeOne(view, size: size, scale: scale, pane: pane, to: url)
            return
        }
        let name = url.lastPathComponent
        for s in activeScales {
            let scaleDir = snapshotsDirectory.appendingPathComponent("\(Int(s))x", isDirectory: true)
            try? FileManager.default.createDirectory(at: scaleDir, withIntermediateDirectories: true)
            writeOne(view, size: size, scale: s, pane: pane, to: scaleDir.appendingPathComponent(name))
        }
        writeOne(view, size: size, scale: activeScales.last ?? 2, pane: pane, to: url)
    }

    /// Renders one PNG. With `pane` set (Settings captures) the render must show exactly that pane, and
    /// no other pane may have produced the same bytes; otherwise the run records a failure and exits 1.
    private static func writeOne<V: View>(_ view: V, size: CGSize, scale: CGFloat, pane: GSSection? = nil, to url: URL) {
        let content = view.environment(\.mascotRasterScale, scale).frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        // Let pending main-queue work from navigating to the pane land before rendering.
        if pane != nil { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
        SnapshotPaneProbe.reset()
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            if pane != nil { harnessFailures.append("\(url.lastPathComponent): render produced no image") }
            return
        }
        if let pane {
            let shown = SnapshotPaneProbe.seen
            guard shown == [pane.rawValue] else {
                let found = shown.isEmpty ? "no pane heading" : shown.sorted().map { "'\($0)'" }.joined(separator: ", ")
                harnessFailures.append("\(url.lastPathComponent): expected pane '\(pane.rawValue)' but the render shows \(found)")
                return
            }
            let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
            let key = "\(Int(size.width))x\(Int(size.height))@\(scale):\(digest)"
            if let other = paneByDigest[key], other != pane.rawValue {
                harnessFailures.append("\(url.lastPathComponent): identical bytes to the '\(other)' pane capture")
            }
            paneByDigest[key] = pane.rawValue
        }
        try? png.write(to: url)
    }

    private static func notchStates() -> [(String, NotchModel)] {
        func make(_ configure: (NotchModel) -> Void) -> NotchModel {
            let model = NotchModel()
            configure(model)
            return model
        }
        let started = Date().addingTimeInterval(-74)
        let claude = NotchModel.Session(id: "cc", agent: "Claude Code", project: "zeus", task: "npm run build", status: .working, startedAt: started)
        let approval = NotchModel.Approval(id: "a", agent: "Claude Code", project: "zeus", tool: "Bash",
                                           command: "rm -rf dist && npm run build", risk: .high,
                                           deadline: Date().addingTimeInterval(87), timeoutNote: "then your terminal asks", resolve: { _ in })
        return [
            ("1-closed-working", make { $0.sessions = [claude]; $0.presentation = .closed }),
            ("2-peek-running", make { $0.sessions = [claude]; $0.peekSessionID = "cc"; $0.presentation = .peek }),
            ("3-peek-approval", make { $0.sessions = [claude]; $0.approval = approval; $0.presentation = .peek }),
            ("4-peek-done", make {
                var done = claude; done.status = .done
                $0.sessions = [done]; $0.peekSessionID = "cc"; $0.presentation = .peek
            }),
            ("8-peek-recap", make {
                var done = claude; done.status = .done
                $0.sessions = [done]; $0.presentation = .peek
                let now = Date()
                $0.recap = WelcomeRecap(awaySeconds: 23 * 60,
                    finished: [RecapEvent(kind: .finished, id: "cc", agent: "Claude Code", project: "zeus", date: now),
                               RecapEvent(kind: .finished, id: "cu", agent: "Cursor Agent", project: "api", date: now)],
                    failed: [RecapEvent(kind: .failed, id: "cx", agent: "Codex", project: "website", detail: "Rate limit reached", date: now)],
                    waiting: [RecapEvent(kind: .waiting, id: "cw", agent: "Claude Code", project: "docs", detail: "Bash", date: now)])
            }),
            ("6-peek-plan", make {
                $0.sessions = [claude]; $0.presentation = .peek
                let plan = "## Plan\n1. Add `ApprovalDetail` for plans\n2. Render Markdown blocks\n   - lists and code\n3. Run `scripts/test.sh`"
                $0.approval = NotchModel.Approval(id: "p", agent: "Claude Code", project: "zeus", tool: "Plan", command: "Plan ready", risk: .low,
                                                  detail: ApprovalDetail(kind: .plan(plan), input: nil, session: "cc"), resolve: { _ in })
            }),
            ("7-peek-question", make {
                $0.sessions = [claude]; $0.presentation = .peek
                let question = AgentQuestion(question: "Which database should the sync use?", header: "DB",
                                             options: [.init(label: "SQLite", detail: "Local file, zero setup"), .init(label: "Postgres", detail: "Shared server")],
                                             multiSelect: false)
                $0.approval = NotchModel.Approval(id: "q", agent: "Claude Code", project: "zeus", tool: "Question", command: "Question", risk: .low,
                                                  detail: ApprovalDetail(kind: .questions([question]), input: nil, session: "cc"), resolve: { _ in })
            }),
            ("8-peek-diff", make {
                $0.sessions = [claude]; $0.presentation = .peek
                let input = try? JSONDecoder().decode(JSONValue.self, from: Data(#"{"file_path":"/zeus/Sources/App.swift","old_string":"let a = 1\nlet b = 2\nprint(a)","new_string":"let a = 1\nlet b = 3\nprint(a + b)"}"#.utf8))
                $0.approval = NotchModel.Approval(id: "d", agent: "Claude Code", project: "zeus", tool: "Edit", command: "Edit App.swift", risk: .low,
                                                  detail: ApprovalDetail.make(tool: "Edit", input: input, session: "cc"), resolve: { _ in })
            }),
            ("9-peek-completion", make {
                var done = claude; done.status = .done
                $0.sessions = [done]; $0.peekSessionID = "cc"; $0.presentation = .peek
                $0.completion = AgentCompletion(sessionID: "cc", agent: "Claude Code", project: "zeus",
                                                summary: "All 104 tests pass and the work is committed on devon/claude.", startedAt: started)
            }),
            ("10-peek-failed", make {
                var failed = claude; failed.status = .failed; failed.reason = "Rate limit reached: 429 Too Many Requests"
                $0.sessions = [failed]; $0.peekSessionID = "cc"; $0.presentation = .peek
                $0.failure = .init(sessionID: "cc", agent: "Claude Code", project: "zeus", reason: "Rate limit reached: 429 Too Many Requests")
            }),
            ("11-peek-stalled", make {
                var stalled = claude; stalled.status = .stalled; stalled.reason = "No activity for 5 min"
                $0.sessions = [stalled]; $0.peekSessionID = "cc"; $0.presentation = .peek
            }),
            ("12-panel-picker", make {
                let stalled = NotchModel.Session(id: "cu", agent: "Cursor Agent", project: "api", task: "refactor auth", status: .stalled,
                                                 startedAt: started, reason: "No activity for 5 min")
                let failed = NotchModel.Session(id: "cx", agent: "Codex", project: "website", task: "Rate limit reached", status: .failed,
                                                startedAt: started, reason: "Rate limit reached")
                $0.sessions = [claude, stalled, failed]
                $0.picker = AgentPicker(count: 3, index: 1)
                $0.presentation = .panel
            }),
            ("5-panel", make {
                var done = claude; done.status = .done; done.task = "build finished in 41 s"
                $0.sessions = [
                    done,
                    .init(id: "cx", agent: "Codex", project: "website", task: "write tests for checkout", status: .working, startedAt: started),
                    .init(id: "cu", agent: "Cursor", project: "api", task: "refactor auth middleware", status: .done, startedAt: started),
                ]
                $0.approval = NotchModel.Approval(id: "b", agent: "Codex", project: "website", tool: "Bash",
                                                  command: "git push --force origin main", risk: .high, resolve: { _ in })
                $0.presentation = .panel
            }),
        ]
    }

    // MARK: Home customisation, tab editor and calendar snapshots

    private static func sampleModel(_ configure: (TopBarModel) -> Void = { _ in }) -> (NotchModel, TopBarModel) {
        let now = Date()
        let model = NotchModel()
        let topBar = TopBarModel()
        topBar.nowPlaying = NowPlaying(player: .music, title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
                                       isPlaying: true, duration: 243, position: 96, positionAt: now)
        if let playing = topBar.nowPlaying { ArtworkStore.shared.seed(Self.sampleCover(), for: playing) }
        topBar.weatherPlace = "São Paulo"
        let day: (Int) -> Date = { now.addingTimeInterval(Double($0) * 86_400) }
        topBar.weather = WeatherSnapshot(temperature: 24, apparent: 26, high: 27, low: 18, sky: .partlyCloudy, isDay: true, humidity: 62, wind: 17,
                                         hours: (1...8).map { WeatherSnapshot.Hour(time: now.addingTimeInterval(Double($0) * 3600),
                                                                                   temperature: 24 + 3 * sin(Double($0) * 0.6),
                                                                                   sky: $0 > 5 ? .rain : .partlyCloudy, rainChance: $0 > 5 ? 70 : 10) },
                                         days: [.init(date: day(0), high: 27, low: 18, sky: .partlyCloudy), .init(date: day(1), high: 25, low: 17, sky: .rain),
                                                .init(date: day(2), high: 22, low: 15, sky: .cloudy), .init(date: day(3), high: 28, low: 19, sky: .clear)])
        topBar.calendarAccess = .granted
        topBar.events = [
            .init(id: "e1", title: "Design review", start: now.addingTimeInterval(1500), end: now.addingTimeInterval(4500), isAllDay: false,
                  colorHex: 0x4DA3FF, location: "Meet", meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"), calendarName: "Work"),
            .init(id: "e2", title: "Ship ZEUS top bar", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(9000), isAllDay: false,
                  colorHex: 0xFFC83D, location: nil, meetingURL: nil, calendarName: "Work"),
        ]
        topBar.battery = .init(level: 82, charging: false, pluggedIn: false)
        topBar.note = "Ask Ana about the launch deck. Buy coffee beans."
        topBar.selectedTab = .home
        model.presentation = .panel
        configure(topBar)
        return (model, topBar)
    }

    /// Some made-up app events for the Diagnostics log.
    private static func seedFlightRecorder() {
        let recorder = FlightRecorder.shared
        recorder.clear()
        let base = Date().addingTimeInterval(-120)
        let rows: [(String, String, String)] = [
            ("voice", "key", "talk shortcut pressed (access granted)"), ("voice", "listen", "started (recogniser en-US)"),
            ("sound", "listenStart", ""), ("voice", "transcript", "open the build log"), ("voice", "route", "fast via Rules: open app"),
            ("cue", "decided", ""), ("agent", "UserPromptSubmit", "Claude Code zeus session 7f3a91c2"),
            ("agent", "PreToolUse", "Claude Code zeus session 7f3a91c2 tool Bash"), ("sound", "request", "Classic"),
            ("cue", "copied", ""), ("agent", "Stop", "Claude Code zeus session 7f3a91c2"), ("sound", "done", "Success"),
            ("error", "error", "can't reach api.example.com token=[redacted]"), ("cue", "shortcut", ""),
        ]
        for (index, row) in rows.enumerated() { recorder.record(row.0, row.1, row.2, at: base.addingTimeInterval(Double(index) * 7)) }
    }

    /// Parity round: card styles, lyrics, the clipboard with pictures, reminders filters, the focus dial, the quit peek.
    private static func renderParityStates(into directory: URL, notch: CGSize) {
        let store = SettingsStore.shared
        let savedStyle = store.string("appearance.cardStyle"), savedLyrics = store.string("privacy.lyrics"), savedMusic = store.string("home.variant.music")
        let savedSlots = (1...4).map { store.string(HomeSlots.settingID(slot: $0)) }
        defer {
            store.set("appearance.cardStyle", savedStyle); store.set("privacy.lyrics", savedLyrics); store.set("home.variant.music", savedMusic)
            for (index, value) in savedSlots.enumerated() { store.set(HomeSlots.settingID(slot: index + 1), value) }
            LyricsToggle.snapshotShow = false
        }
        // Every card style on Home.
        for (index, finish) in CardFinish.allCases.enumerated() {
            store.set("appearance.cardStyle", finish.rawValue)
            let (model, topBar) = sampleModel()
            save(NotchStage(model: model, topBar: topBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent(String(format: "parity-card-%d-%@.png", index + 1, finish.rawValue.replacingOccurrences(of: " ", with: "-"))))
        }
        for (index, style) in ["Borderless", "Borderless colour"].enumerated() {
            store.set("appearance.homeStyle", style)
            let (model, topBar) = sampleModel()
            save(NotchStage(model: model, topBar: topBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent("parity-home-\(index + 1)-\(style.replacingOccurrences(of: " ", with: "-")).png"))
        }
        store.set("appearance.homeStyle", "Device")
        store.set("appearance.cardStyle", "Liquid Glass")

        // Lyrics: the Music page and the Home music variant.
        store.set("privacy.lyrics", "true")
        let lines = ["Waiting in a car", "Waiting for a ride in the dark", "The night city grows", "Look at the horizon and the stars", "Waiting in a car",
                     "Waiting for a ride in the dark", "Drinking in the lights", "Following the neon signs", "Waiting for a roar", "Looking at the mountains"]
            .enumerated().map { LyricLine(time: 80 + Double($0.offset) * 8, text: $0.element) }
        do {
            let (model, topBar) = sampleModel { $0.selectedTab = .music }
            if let playing = topBar.nowPlaying { LyricsStore.shared.seed(.synced(lines), for: playing) }
            LyricsToggle.snapshotShow = true
            save(NotchStage(model: model, topBar: topBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent("parity-lyrics-music.png"))
            LyricsToggle.snapshotShow = false
            store.set("home.variant.music", "Lyrics")
            for (slot, name) in ["Music", "Focus", "Weather", "Calendar"].enumerated() { store.set(HomeSlots.settingID(slot: slot + 1), name) }
            let (homeModel, homeBar) = sampleModel()
            if let playing = homeBar.nowPlaying { LyricsStore.shared.seed(.synced(lines), for: playing) }
            save(NotchStage(model: homeModel, topBar: homeBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent("parity-lyrics-home.png"))
            store.set("home.variant.music", "Art")
        }

        // Clipboard with pictures and files.
        ClipboardMedia.directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-snap-clip", isDirectory: true)
        let now = Date()
        do {
            let (model, topBar) = sampleModel { t in
                t.selectedTab = .clipboard
                var history = ClipboardHistory()
                history.add("npm run build", sourceApp: "Terminal", at: now.addingTimeInterval(-30))
                for seed in 0..<2 {
                    if let saved = ClipboardMedia.save(ClipboardMedia.sampleImage(seed: seed)) {
                        history.addImage(file: saved.file, width: saved.width, height: saved.height, sourceApp: "Preview", at: now.addingTimeInterval(Double(-10 - seed * 20)))
                    }
                }
                history.addFiles(["/System/Library/Sounds/Glass.aiff"], sourceApp: "Finder", at: now.addingTimeInterval(-5))
                history.add("https://zeus.dev/docs", sourceApp: "Safari", at: now.addingTimeInterval(-90))
                t.clipboard = history
            }
            save(NotchStage(model: model, topBar: topBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent("parity-clipboard.png"))
        }

        // Reminders: Flagged filter with a due time chip selected.
        RemindersController.shared.seedForSnapshot([
            .init(id: "r1", title: "Pay the electricity bill", list: "Home", due: now.addingTimeInterval(-86_400), colorHex: 0xFF9F0A, flagged: true),
            .init(id: "r2", title: "Call the bank", list: "Errands", due: now.addingTimeInterval(3 * 3600), colorHex: 0x4DA3FF, flagged: true, hasTime: true),
            .init(id: "r3", title: "Pick up the dry cleaning", list: "Errands", due: nil, colorHex: 0x4DA3FF),
            .init(id: "r4", title: "Send the invoice", list: "Work", due: now.addingTimeInterval(86_400 * 2), colorHex: 0x3CCB7F),
        ])
        for (name, filter) in [("today", ReminderFilter.today), ("flagged", .flagged)] {
            RemindersController.shared.filter = filter
            RemindersController.shared.pendingDue = filter == .today ? .tomorrowMorning : nil
            let (model, topBar) = sampleModel { $0.selectedTab = .reminders }
            save(NotchStage(model: model, topBar: topBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent("parity-reminders-\(name).png"))
        }
        RemindersController.shared.filter = .all
        RemindersController.shared.pendingDue = nil

        // Focus dial.
        do {
            let (model, topBar) = sampleModel { t in t.selectedTab = .focus; t.focus.setTime(minutes: 35); t.focus.start(at: now.addingTimeInterval(-300)); t.focus.extend(by: 300, at: now) }
            save(NotchStage(model: model, topBar: topBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent("parity-focus.png"))
        }
        // The Quit peek on the closed notch.
        do {
            let (model, topBar) = sampleModel { t in
                t.nowPlaying = nil
                t.setCueForSnapshot(.shortcut(ShortcutPeek.lookup("q", shift: false)!))
                t.setLightsForSnapshot([(.shortcut(.quit), 0.3)])
            }
            model.presentation = .closed
            save(NotchStage(model: model, topBar: topBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent("parity-quit-peek.png"))
        }
    }

    private static func renderHomeStates(into directory: URL, notch: CGSize) {
        let store = SettingsStore.shared
        let ids = (1...4).map { HomeSlots.settingID(slot: $0) } + ["home.variant.clock", "home.variant.music", "home.variant.weather", "home.variant.calendar", HomeBackdrop.settingID]
        let saved = ids.map { ($0, store.string($0)) }
        defer { for (id, value) in saved { store.set(id, value) } }
        func apply(_ widgets: [String], _ variants: [String: String] = [:], backdrop: String = "None") {
            for (index, name) in widgets.enumerated() { store.set(HomeSlots.settingID(slot: index + 1), name) }
            for (id, value) in variants { store.set(id, value) }
            store.set(HomeBackdrop.settingID, backdrop)
        }
        func render(_ name: String, _ configure: (TopBarModel) -> Void = { _ in }) {
            let (model, topBar) = sampleModel(configure)
            save(NotchStage(model: model, topBar: topBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent("home-\(name).png"))
        }
        let defaults = ["Music", "Focus", "Weather", "Calendar"]
        let plain = ["home.variant.clock": "Analog", "home.variant.music": "Art", "home.variant.weather": "Summary", "home.variant.calendar": "Next event"]
        apply(defaults, plain)
        render("01-default")
        apply(["Clock", "Music", "Weather", "Month"], ["home.variant.clock": "Analog", "home.variant.music": "Disc", "home.variant.weather": "Hourly curve"], backdrop: "Aurora")
        render("02-analog-disc-hourly-aurora")
        apply(["Music", "Clock", "Weather", "Agenda"], ["home.variant.music": "Cassette", "home.variant.clock": "Blue halo", "home.variant.weather": "Days"], backdrop: "Sunset")
        render("03-cassette-halo-days-sunset")
        store.set("home.countdown.title", "Launch day")
        store.set("home.countdown.date", TodoQuickAdd.dayString(Date().addingTimeInterval(23 * 86_400)))
        apply(["Clock", "World clock", "Weather", "Countdown"], ["home.variant.clock": "Elastic", "home.variant.weather": "Wind"], backdrop: "Halftone")
        render("04-elastic-world-wind-countdown-halftone")
        apply(["Calendar", "Note", "Weather", "Battery"], ["home.variant.calendar": "Week", "home.variant.weather": "Feels like"], backdrop: "Watercolor")
        render("05-week-note-feels-battery-watercolor")
        apply(["Music", "Agents", "Weather", "Calendar"], ["home.variant.music": "Wave", "home.variant.calendar": "Agenda", "home.variant.weather": "Summary"], backdrop: "Cosmos")
        render("06-wave-agents-cosmos")
        apply(defaults, plain, backdrop: "Marble")
        render("07-customize") { $0.homeCustomizing = true; $0.homePickerSlot = 3 }
        apply(["Clock", "Focus", "Weather", "Calendar"], ["home.variant.clock": "Elastic", "home.variant.calendar": "Month"], backdrop: "Matcha")
        render("08-customize-clock") { $0.homeCustomizing = true; $0.homePickerSlot = 1 }
        // Every backdrop, one frame each, big enough to judge.
        let sheet = LazyVGrid(columns: Array(repeating: GridItem(.fixed(300), spacing: 12), count: 4), spacing: 12) {
            ForEach(HomeBackdrop.allCases.filter { $0 != .off }) { backdrop in
                ZStack(alignment: .bottomLeading) {
                    HomeBackdropView(backdrop: backdrop, visible: false, reduceMotion: true).frame(width: 300, height: 114)
                    Text(backdrop.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).padding(6)
                        .background(Capsule().fill(Color.black.opacity(0.55))).padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .padding(16).background(Color(hex: 0x10131A))
        save(sheet, size: CGSize(width: 1272, height: 420), to: directory.appendingPathComponent("home-09-backdrops.png"))
        apply(defaults, plain)

        // The tab editor and the Calendar page.
        do {
            let (model, topBar) = sampleModel { $0.tabEditing = true; $0.tabEditorNote = nil }
            topBar.layout = TopBarLayout.standard.trimmedToRow()
            save(NotchStage(model: model, topBar: topBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent("tabs-editor.png"))
        }
        do {
            let now = Date()
            let (model, topBar) = sampleModel { t in
                t.selectedTab = .calendar
                let calendar = ZeusDates.calendar()
                let start = calendar.startOfDay(for: now)
                func at(_ offset: Int, _ hour: Int, _ minutes: Int = 60) -> (Date, Date) {
                    let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                    let begin = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
                    return (begin, begin.addingTimeInterval(Double(minutes) * 60))
                }
                let specs: [(Int, Int, String, UInt32)] = [(0, 10, "Design review", 0x4DA3FF), (0, 15, "Ship ZEUS top bar", 0xFFC83D), (1, 13, "Lunch with Ana", 0x3CCB7F),
                                                           (3, 9, "Dentist", 0xFF5A5F), (5, 18, "Dinner", 0xA78BFA), (9, 11, "Planning", 0x4DA3FF), (12, 14, "Offsite", 0xFFC83D),
                                                           (-4, 16, "1:1 with Sam", 0x3CCB7F)]
                t.calendarEvents = specs.enumerated().map { index, spec in
                    let (a, b) = at(spec.0, spec.1)
                    return .init(id: "m\(index)", title: spec.2, start: a, end: b, isAllDay: false, colorHex: spec.3,
                                 location: index == 0 ? "Meet" : nil, meetingURL: index == 0 ? URL(string: "https://meet.google.com/abc-defg-hij") : nil,
                                 calendarName: "Work", notes: index == 0 ? "Walk through the Home customise mode." : nil)
                }
                t.calendarDay = now
                t.calendarDetailID = "m0"
                t.quickAddNote = "Added Lunch with Ana, tomorrow 1:00 PM."
            }
            save(NotchStage(model: model, topBar: topBar, notch: notch), size: CGSize(width: 960, height: 400),
                 to: directory.appendingPathComponent("calendar-month.png"))
        }
    }

    private static func topBarStates() -> [(String, NotchModel, TopBarModel)] {
        let now = Date()
        func make(_ tab: TopBarTab?, _ configure: (NotchModel, TopBarModel) -> Void = { _, _ in }) -> (NotchModel, TopBarModel) {
            let model = NotchModel()
            let topBar = TopBarModel()
            topBar.nowPlaying = NowPlaying(player: .music, title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
                                           isPlaying: true, duration: 243, position: 96, positionAt: now)
            if let playing = topBar.nowPlaying { ArtworkStore.shared.seed(Self.sampleCover(), for: playing) }
            topBar.weatherPlace = "São Paulo"
            topBar.weather = WeatherSnapshot(temperature: 24, apparent: 25, high: 27, low: 18, sky: .partlyCloudy, isDay: true,
                                             humidity: 62, wind: 11,
                                             hours: (1...8).map { WeatherSnapshot.Hour(time: now.addingTimeInterval(Double($0) * 3600),
                                                                                       temperature: 24 - Double($0) * 0.6,
                                                                                       sky: $0 > 4 ? .rain : .partlyCloudy, rainChance: $0 > 4 ? 70 : 10) })
            topBar.calendarAccess = .granted
            topBar.events = [
                .init(id: "e1", title: "Design review", start: now.addingTimeInterval(1500), end: now.addingTimeInterval(4500), isAllDay: false,
                      colorHex: 0x4DA3FF, location: "Meet", meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")),
                .init(id: "e2", title: "Ship ZEUS top bar", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(9000), isAllDay: false,
                      colorHex: 0xFFC83D, location: nil, meetingURL: nil),
            ]
            topBar.reminders = [.init(id: "r1", title: "Send invoice", due: now.addingTimeInterval(3600), done: false)]
            topBar.battery = .init(level: 82, charging: false, pluggedIn: false)
            for text in ["https://zeus.dev/docs", "npm run build", "Meeting notes: ship Friday"] { _ = topBar.clipboard.add(text, at: now) }
            topBar.dictationHistory = [
                DictationRecord(datetime: now.addingTimeInterval(-300), duration: 6200, processingTime: 310, modeKey: "voice", modeName: "Voice",
                                rawResult: "lets ship the top bar today", result: "Let's ship the top bar today.", appName: "Slack", inserted: true),
                DictationRecord(datetime: now.addingTimeInterval(-1800), duration: 9100, processingTime: 2400, modeKey: "email", modeName: "Email",
                                rawResult: "tell anna the build is green", result: "Hi Anna, the build is green. Best, Tony", appName: "Mail", inserted: true),
            ]
            if let tab { topBar.selectedTab = tab; model.presentation = .panel }
            configure(model, topBar)
            return (model, topBar)
        }
        let day = { (offset: Int) in TodoQuickAdd.dayString(now.addingTimeInterval(Double(offset) * 86_400)) }
        BrainTodayModel.shared.seedForSnapshot([
            BrainTask(title: "Call Anna about the RFP", project: "Clients", dueToday: true, highPriority: false, file: "a.md"),
            BrainTask(title: "Live model path end to end", project: "Soul", dueToday: false, highPriority: true, file: "b.md"),
            BrainTask(title: "Ten dev RFPs scored", project: "Soul", dueToday: false, highPriority: true, file: "b.md"),
        ])
        TodoController.shared.seedForSnapshot([
            TodoItem(title: "Send Anna the deck", due: day(-1)),
            TodoItem(title: "Review the top bar PR", due: day(0)),
            TodoItem(title: "Book the dentist", due: day(1)),
            TodoItem(title: "Plan the iPhone pairing", due: day(9)),
            TodoItem(title: "Buy coffee beans", done: true),
        ], connection: BrainConnection(source: BrainSource(kind: .obsidian, name: "Vault", path: "/tmp/zeus-snapshot-vault"),
                                       access: .readWrite, todo: .note(BrainConnection.defaultTodoNote)))
        let started = now.addingTimeInterval(-74)
        let claude = NotchModel.Session(id: "cc", agent: "Claude Code", project: "zeus", task: "npm run build", status: .working, startedAt: started)
        var states: [(String, (NotchModel, TopBarModel))] = [
            ("01-closed-music", make(nil)),
            ("02-closed-copied", make(nil) { _, t in t.setCueForSnapshot(.copied("npm run build")) }),
            ("03-closed-volume", make(nil) { _, t in t.setCueForSnapshot(.volume(0.6, muted: false)) }),
            ("04-closed-capslock", make(nil) { _, t in t.setCueForSnapshot(.capsLock(true)) }),
            ("05-closed-focus", make(nil) { _, t in t.focus.start(at: now.addingTimeInterval(-300)) }),
            ("06-closed-dictating", make(nil) { _, t in t.dictationPhase = .listening; t.dictationLevel = 0.7 }),
        ]
        // The closed notch's light language, frozen mid-effect.
        func lit(_ kind: NotchLightKind, _ p: Double) -> (NotchModel, TopBarModel) {
            make(nil) { _, t in t.nowPlaying = nil; t.setLightsForSnapshot([(kind, p)]) }
        }
        states += [
            ("40-light-copy", lit(.copySweep, 0.3)),
            ("41-light-capslock", lit(.capsLock(true), 0.25)),
            ("42-light-shift", lit(.shiftCrest, 0.55)),
            ("43-light-battery", lit(.battery(level: 0.62, charging: true), 0.5)),
            ("44-light-airdrop", lit(.landed(airDrop: true), 0.25)),
            ("45-light-reminder", lit(.reminderPinned, 0.7)),
            ("46-light-event", lit(.eventRibbon, 0.3)),
            ("47-light-cut", make(nil) { _, t in t.nowPlaying = nil; t.setCueForSnapshot(.shortcut(ShortcutPeek.lookup("x", shift: false)!)); t.setLightsForSnapshot([(.shortcut(.breach), 0.4)]) }),
            ("48-light-timer", make(nil) { _, t in t.nowPlaying = nil; t.focus.start(at: now.addingTimeInterval(-600)) }),
            ("49-halo-classic", make(nil) { m, t in t.nowPlaying = nil; m.sessions = [claude]; t.haloStyle = .classic }),
            ("50-halo-pixelated", make(nil) { m, t in t.nowPlaying = nil; m.sessions = [claude]; t.haloStyle = .pixelated }),
            ("51-halo-volumetric", make(nil) { m, t in t.nowPlaying = nil; m.sessions = [claude]; t.haloStyle = .volumetric }),
            ("60-halo-rayons", make(nil) { m, t in t.nowPlaying = nil; m.sessions = [claude]; t.haloStyle = .rayons }),
            ("61-halo-prisme", make(nil) { m, t in t.nowPlaying = nil; m.sessions = [claude]; t.haloStyle = .prisme }),
            ("62-halo-nimbus", make(nil) { m, t in t.nowPlaying = nil; m.sessions = [claude]; t.haloStyle = .nimbus }),
            ("63-halo-lumiere", make(nil) { m, t in t.nowPlaying = nil; m.sessions = [claude]; t.haloStyle = .lumiere }),
            ("64-halo-bio", make(nil) { m, t in t.nowPlaying = nil; m.sessions = [claude]; t.haloStyle = .bioluminescent }),
            ("65-entrance-bigbang", lit(.entrance(.bigBang, .sky), 0.3)),
            ("66-entrance-hue", lit(.entrance(.hueSlide, .sky), 0.7)),
            ("52-halo-entrance", lit(.entrance(.sweep, .sky), 0.45)),
            ("53-light-drag", make(nil) { _, t in t.nowPlaying = nil; t.isDraggingFiles = true }),
            ("54-light-mic", make(nil) { _, t in t.nowPlaying = nil; t.micListening = true; t.micLevel = 0.5 }),
            ("55-cue-brightness", make(nil) { _, t in t.nowPlaying = nil; t.setCueForSnapshot(.brightness(0.7)) }),
            ("56-cue-rain", make(nil) { _, t in t.nowPlaying = nil; t.setCueForSnapshot(.rain(minutes: 25)) }),
            ("57-light-music", make(nil) { _, _ in }),
            ("58-dictation-wave", make(nil) { _, t in
                t.nowPlaying = nil; t.dictationPhase = .listening
                for i in 0..<28 { t.pushDictationLevel(0.15 + 0.35 * abs(sin(Double(i) * 0.7))) }
            }),
        ]
        TodayController.shared.seedForSnapshot(TodaySummary(
            day: day(0), dailyNote: "02_Areas/Daily/\(day(0)).md",
            tasks: [TodayTask(title: "Send Q4 numbers to Marta", due: day(-1), overdue: true, file: "01_Projects/Finance.md", line: 12),
                    TodayTask(title: "Prep ZEUS demo script", due: day(0), overdue: false, file: "01_Projects/ZEUS.md", line: 4)],
            meetings: [TodayNote(title: "\(day(0)) Design review", file: "Meetings/prep/\(day(0)) Design review.md")]), vault: "brain")
        RemindersController.shared.seedForSnapshot([
            .init(id: "r1", title: "Pay the electricity bill", list: "Home", due: now.addingTimeInterval(-86_400), colorHex: 0xFF9F0A),
            .init(id: "r2", title: "Call the bank", list: "Errands", due: now, colorHex: 0x4DA3FF),
            .init(id: "r3", title: "Pick up the dry cleaning", list: "Errands", due: nil, colorHex: 0x4DA3FF),
        ])
        NotificationsController.shared.seedForSnapshot([
            MirroredNotification(id: 1, app: "com.apple.MobileSMS", title: "Anna", subtitle: nil, body: "Deck looks great, ship it", date: now.addingTimeInterval(-120)),
            MirroredNotification(id: 2, app: "com.apple.mail", title: "GitHub", subtitle: "zeus", body: "CI passed on devon/zeus-next", date: now.addingTimeInterval(-900)),
            MirroredNotification(id: 3, app: "com.apple.iCal", title: "Design review", subtitle: nil, body: "In 25 minutes", date: now.addingTimeInterval(-1800)),
        ])
        // A made-up spectrum (a bass-heavy tilt with a couple of peaks) so the Waves tab has bars to draw.
        AudioSpectrumService.shared.seedForSnapshot((0..<SpectrumMath.bandCount).map { i in
            let x = Float(i) / Float(SpectrumMath.bandCount - 1)
            return min(1, max(0.06, 0.78 - 0.5 * x + 0.16 * sin(Float(i) * 0.9) + 0.12 * sin(Float(i) * 2.3 + 1)))
        })
        for (index, tab) in TopBarTab.allCases.enumerated() {
            states.append((String(format: "%02d-page-%@", 10 + index, tab.rawValue), make(tab) { m, t in
                if tab == .agents { m.sessions = [claude] }
                if tab == .focus { t.focus.start(at: now.addingTimeInterval(-420)) }
                if tab == .usage { UsageModel.shared.loadNow() }
                if tab == .polyglot { PolyglotController.shared.seedForSnapshot() }
                if tab == .shelf { t.shelf = [.init(url: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"))] }
            }))
        }
        // The Record page in the states a person meets: one or two displays, permission missing, countdown, recording, saved.
        for (name, displays, granted, state) in RecordlySnapshotFixtures.pageStates {
            states.append(("27-page-recordly-\(name)", make(.recordly) { _, t in
                t.recordlyForSnapshot = RecordlySnapshotFixtures.controller(displays: displays, granted: granted, state: state)
            }))
        }
        states.append(("22-page-waves-wave", make(.waves)))
        states.append(("23-page-waves-mirror", make(.waves)))
        states.append(("20-page-teleprompter-rolling", make(.teleprompter) { _, t in
            t.roll.start(at: now, countdown: false)
            t.roll.hear(level: 0.6, at: now)
            t.roll.jump(to: 58)
            t.prompterLevel = 0.55
        }))
        states.append(("21-page-teleprompter-countdown", make(.teleprompter) { _, t in
            t.roll.start(at: now.addingTimeInterval(-1.2))
        }))
        states.append(("30-panel-approval", make(.home) { m, _ in
            m.sessions = [claude]
            m.approval = NotchModel.Approval(id: "a", agent: "Claude Code", project: "zeus", tool: "Bash", command: "git push --force origin main",
                                             risk: .high, deadline: now.addingTimeInterval(87), timeoutNote: "then your terminal asks", resolve: { _ in })
        }))
        return states.map { ($0.0, $0.1.0, $0.1.1) }
    }

    /// A made-up cover for the snapshots (no network): a teal to magenta sky with a low sun.
    private static func sampleCover() -> NSImage {
        NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.05, green: 0.12, blue: 0.30, alpha: 1), NSColor(red: 0.85, green: 0.22, blue: 0.55, alpha: 1),
                                NSColor(red: 1.0, green: 0.62, blue: 0.30, alpha: 1)])?.draw(in: rect, angle: 90)
            NSColor(red: 1.0, green: 0.86, blue: 0.55, alpha: 0.95).setFill()
            NSBezierPath(ovalIn: NSRect(x: 190, y: 170, width: 220, height: 220)).fill()
            NSColor(red: 0.04, green: 0.05, blue: 0.14, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 600, height: 190)).fill()
            return true
        }
    }

    private static func buddyStates() -> [(String, BuddyModel)] {
        func make(_ configure: (BuddyModel) -> Void) -> BuddyModel {
            let model = BuddyModel()
            model.hasAppeared = true
            model.position = CGPoint(x: 120, y: 130)
            configure(model)
            return model
        }
        return [
            ("1-following", make { _ in }),
            ("2-listening", make { $0.mode = .listening; $0.audioLevel = 0.7 }),
            ("3-thinking", make { $0.mode = .thinking }),
            ("4-flying", make { $0.mode = .flying; $0.rotation = 62; $0.scale = 1.28 }),
            ("6-caption", make {
                $0.caption = "That's the Apple menu, top left. Click it for About This Mac and System Settings."
                $0.captionVisible = true
            }),
            ("5-strike", make {
                $0.mode = .pointing; $0.rotation = 120
                $0.strikeCenter = $0.position; $0.strikeProgress = 0.45
                $0.bubbleVisible = true; $0.bubbleText = "that's me up here, click the bolt"
            }),
        ]
    }
}

/// A notch on a slice of dark menu bar and desktop.
private struct NotchStage: View {
    let model: NotchModel
    var topBar: TopBarModel? = nil
    let notch: CGSize

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x2B3446), Color(hex: 0x141922)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.black.opacity(0.35)).frame(height: notch.height)
            NotchView(model: model, topBar: topBar, notch: notch)
        }
    }
}

private struct BuddyStage: View {
    let model: BuddyModel
    let frame: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0x2B3446), Color(hex: 0x141922)], startPoint: .topLeading, endPoint: .bottomTrailing)
            BuddyOverlayView(model: model, screenFrame: frame)
        }
    }
}

/// A window frame for snapshots: rounded corners and traffic lights over the content.
private struct WindowStage<Content: View>: View {
    let content: Content
    var body: some View {
        content
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { hex in
                        Circle().fill(Color(hex: UInt32(hex))).frame(width: 12, height: 12)
                    }
                }
                .padding(.leading, 18).padding(.top, 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DragHelperView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: Brand.logo)
                .resizable()
                .frame(width: 48, height: 48)
                .shadow(radius: 4)
            Text("Drag Zeus into System Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(20)
        .frame(width: 260, height: 160)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: 0x1B2030))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct PermissionSnapshotView: View {
    let name: String
    let symbol: String
    private let iconColumn: CGFloat = 32
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.sky)
                    .frame(width: iconColumn, height: 24, alignment: .center)
                Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle().fill(.white.opacity(0.35)).frame(width: 8, height: 8)
                    Text("Not allowed").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Not allowed")
            }
            HStack {
                Spacer()
                Button("Open System Settings") {}
                    .buttonStyle(GSButtonStyle(prominent: true))
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: 0x181D28))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        )
    }
}

