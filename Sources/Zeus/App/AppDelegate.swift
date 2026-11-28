import AppKit
import Carbon.HIToolbox
import SwiftUI
import ZeusCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// What this launch may start. `.normal` (the default) allows everything, as before.
    private let policy: StartupPolicy
    private func on(_ service: StartupService) -> Bool { policy.allows(service) }

    init(policy: StartupPolicy = .normal) {
        self.policy = policy
        // Preferences.shared writes the talk key's default when it is missing, so a QA startup (panel denied,
        // the only user) never builds it. Normal mode builds it first, as the property initializer did.
        preferences = policy.allows(.panelUI) ? Preferences.shared : nil
        // ChatWindowController() builds ChatModel.shared, which reads the chat history from disk, so a QA
        // startup (chat window denied) never builds it. Normal mode builds it here, as before.
        chatWindow = policy.allows(.chatWindow) ? ChatWindowController() : nil
        super.init()
    }

    private var statusItem: NSStatusItem!
    private var panel: MenuBarPanel!
    private let preferences: Preferences?
    private let connections = ConnectionsModel()
    private let buddy = BuddyController()
    private let notch = NotchController()
    private let permissions = PermissionsModel()
    private let hotkey = HotkeyMonitor()
    private var talkChordDefaultsObserver: NSObjectProtocol?
    /// The talk chord and the second talk key as the last sync point worked them out. The talk monitor reads them on every key
    /// event and hold tick, so they are stored here and never worked out in the key path (no access check, no Carbon call).
    private var cachedTalkChord: Shortcut?
    private var cachedSecondTalkKey: Shortcut?
    private var cancelTalkChordVoiceOverWatch: (() -> Void)?
    private var demo: DemoDirector!
    private var voice: VoiceTurnController!
    private var agentServer: AgentEventServer!
    private var commands: CommandCenter!
    private let topBar = TopBarModel()
    private let earbudsNotch = EarbudsNotchPresenter()
    private let earbudsWatch = EarbudsOutputWatch()
    private var topBarServices: TopBarServices!
    private var dictation: DictationController!
    private var teleprompter: TeleprompterController!
    private let keepAwake = KeepAwake()
    private let chatWindow: ChatWindowController?
    private var explanation: ExplanationController?
    private var pointing: PointingController?
    private var pointingProviders: PointingProviders?
    private var pointingSettingsObserver: NSObjectProtocol?
    private var tilingSettingsObserver: NSObjectProtocol?
    private var explanationQuitToken: UUID?
    /// The per-app equaliser. Built with its live ports; only the owner's switch starts it, live or as stored at launch.
    private var equaliser: EqualiserController?
    private var explanationDeletionTasks: [UUID: Task<Void, Never>] = [:]
    /// History UUID -> conversation UUID. Retained until exact deletion succeeds.
    private var failedExplanationDeletions: [UUID: UUID] = [:]

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let chat = on(.chatWindow) ? ChatModel.shared : nil
        chat?.retryVisualConversationLinks()
        for (historyID, id) in failedExplanationDeletions where explanationDeletionTasks[historyID] == nil {
            deleteExplanationHistory(id, historyID: historyID)
        }
        explanation?.beginClosing()
        let pending = {
            self.explanation?.hasUnsavedHistory == true || chat?.hasUnsavedVisualLinks == true
                || !self.failedExplanationDeletions.isEmpty || !self.explanationDeletionTasks.isEmpty
        }
        guard pending() else { return .terminateNow }
        guard explanationQuitToken == nil else { return .terminateLater }
        let token = UUID(); explanationQuitToken = token
        Task { @MainActor [weak self] in
            await self?.explanation?.flushPendingSaves()
            guard let self, self.explanationQuitToken == token else { return }
            for deletion in Array(self.explanationDeletionTasks.values) { await deletion.value }
            guard self.explanationQuitToken == token else { return }
            chat?.retryVisualConversationLinks()
            self.explanationQuitToken = nil
            if pending() {
                self.explanation?.resumeAfterCancelledQuit()
                self.topBar.show(.hint("Zeus is waiting for explanation saves or deletions. Resolve the storage error before quitting."))
            }
            sender.reply(toApplicationShouldTerminate: !pending())
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.explanationQuitToken == token else { return }
            self.explanationQuitToken = nil
            self.explanation?.resumeAfterCancelledQuit()
            self.topBar.show(.hint("Saving the explanation is taking longer than expected. Zeus stayed open to preserve it."))
            sender.reply(toApplicationShouldTerminate: false)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting while Zeus listens or speaks must not leave the Mac's output at the lowered volume.
        SystemAudioDucker.end()
        explanation?.stop()
        pointing?.stop()
        // Every shaping tap is destroyed and the claim released, so no app is left muted.
        equaliser?.shutdown()
        if on(.lockChimes) { LockChimeController.shared.stop() }
        // Tiling removes its key tap, observers and overlays. It never moves a window on the way out. The controller
        // is not even made when the service is denied.
        if on(.tiling) { TilingController.shared.stop() }
        // A lid-closed session puts sleep, sound, Low Power and frozen apps back before Zeus goes.
        if on(.insomniaShutdown) { InsomniaController.shared.shutdown() }
        // A Memory edit typed inside its 600 ms pause is written before Zeus goes.
        if on(.panelUI) { WikiController.shared.flushEdit() }
    }

    /// A voice saved outside the app (a script, another ZEUS) is picked up when the app comes forward.
    func applicationDidBecomeActive(_ notification: Notification) {
        Task.detached(priority: .utility) { _ = Keychain.fresh("elevenlabs.voice-id") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load the Keychain cache off the main thread early; every later read is a dictionary lookup.
        Task.detached(priority: .userInitiated) { Keychain.store.load() }
        // The Ultron stock lines come from the bundled dialogue file; a missing file keeps the compiled lines.
        PersonalityAssets.installDialogue()
        // Before anything can touch ScribeController.shared: the automatic start opt-in is decided by its stamp.
        if on(.settingsCatalog) { ScribeAutoStartController.migrateOptInAtLaunch() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Brand.menuBarImage
            button.setAccessibilityLabel("ZEUS")
            button.toolTip = "ZEUS"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // N2: menu bar status item is always visible so Zeus is reachable on displays without a notch.
        statusItem.isVisible = true

        if on(.buddy) {
            buddy.start()
            BuddyPreference.shared.onChange = { [weak self] choice in self?.buddy.showPolicy = choice }
        }
        notch.topBar = topBar
        notch.onPresentationChange = { [weak self] presentation in self?.buddy.setHiddenForPanel(presentation == .panel) }
        if on(.notchUI) { notch.start(); DrawnNotchModel.shared.start() }
        if on(.notchUI) { ScreenCornerOverlay.shared.start() }
        // A permission cue is eligible for a system notification, which reads SettingsStore.shared (migration
        // writes), so a QA startup never wires it.
        if on(.systemNotifications) {
            // Attaches the banner tap handler (no prompt) so "Open" on a banner from before a relaunch still routes.
            SystemNotificationService.installResponseHandler()
            topBar.onSystemNotification = { [weak self] cue in
                guard let self, self.notch.model.presentation == .closed else { return }
                let sharingOrFullscreen = MeetingState.active || FullScreenDetector.frontAppIsFullScreen()
                if sharingOrFullscreen && ExtraPreferences.shared.quietWhileSharing { return }
                Task { await SystemNotificationService.shared.deliver(cue) }
            }
        }

        // Top bar live data (music, clipboard, system cues, weather, calendar on request).
        if on(.topBarServices) {
            topBarServices = TopBarServices(model: topBar)
            topBarServices.notchIsOpen = { [weak self] in self?.notch.model.presentation != .closed }
            topBarServices.start()
        }
        // Continuity: a cue from Zeus when Beamer moves your keyboard to another machine.
        if on(.beamer) {
            BeamerModel.shared.speakPlace = { [weak self] in self?.voice.sayBeamerPlace() }
            BeamerModel.shared.onCrossing = { [weak self] crossed in self?.topBar.flash(.entrance(.sweep, crossed ? .cyan : .mint)) }
            BeamerModel.shared.startBackgroundWatch()
            BeamerModel.shared.startIfWanted()
        }
        // Dictation: hold its key anywhere, speak, release, the words are typed where you are.
        if on(.dictation) {
            let dictationRoot = ZeusPaths.supportDirectory.appendingPathComponent("Dictation", isDirectory: true)
            dictation = DictationController(topBar: topBar, store: DictationStore(root: dictationRoot))
            topBar.toggleDictation = { [weak self] in
                guard let self else { return }
                if self.topBar.dictationPhase == .listening { self.dictation.finish() } else if !self.topBar.isDictating { self.dictation.begin() }
            }
            dictation.rewrite = { prompt in try await ClaudeRewriter.rewrite(prompt) }
            dictation.start()
            // Continue language packs the owner chose earlier. Returns at once; installs run off the main actor.
            LanguagePackController.shared.resumeOnLaunch()
        }
        // Teleprompter under the camera, hidden from screen shares while it runs.
        if on(.teleprompter) {
            teleprompter = TeleprompterController(topBar: topBar)
            teleprompter.setPrivate = { [weak self] hidden in self?.teleprompterPrivate = hidden }
            teleprompter.start()
        }
        if on(.prompterWatcher) {
            PrompterHub.shared.topBar = topBar
            PrompterHub.shared.onHotkeysChange = { [weak self] in self?.registerShortcuts() }
            PrompterHub.shared.updateWatcher()
        }
        topBar.onKeepAwake = { [weak self] on in self?.keepAwake.set(on) }
        // The optional display hold that lasts only while music plays. Separate from the cup and sessions.
        topBar.onMusicPlaying = { playing in MusicAwakeHold.shared.setPlaying(playing) }
        MusicAwakeHold.shared.setEnabled(SettingsStore.shared.bool(MusicAwakeHold.settingID))
        // The hold shares the session's battery floor and heat setting, so a change there re-runs its rule.
        KeepAwakeSession.shared.onRulesChange = { MusicAwakeHold.shared.evaluate() }
        topBar.onOpenTab = { [weak self] tab in guard let self else { return }; self.topBar.selectedTab = tab; self.notch.show(.panel) }
        // A session that ends (time, battery, heat) also lets the Home cup's display hold go.
        KeepAwakeSession.shared.onEnd = { [weak self] in self?.topBar.keepAwake = false }
        KeepAwakeSession.shared.onNotice = { [weak self] text in self?.topBar.show(.keepAwake(text)) }
        KeepAwakeSession.shared.speak = { [weak self] speech in self?.voice.sayKeepAwake(speech) }
        // Insomnia: undo a lid-closed session a crash left behind, and read whether the admin rule is set up.
        if on(.insomniaLaunch), !TopBarStyle.isSnapshot { InsomniaController.shared.launch() }
        topBar.openSettings = { [weak self] in self?.showSettings() }
        topBar.openPermissions = { [weak self] in self?.showPermissions() }
        // Typed chat: one store behind the notch Chat tab and the floating window.
        if on(.chatBrain) {
            ChatModel.shared.brain = ClaudeCLIProvider()
            ChatModel.shared.speakChats = { [weak self] in self?.voice.sayChats() }
        }
        if on(.chatWindow) {
            ChatModel.shared.speakChats = { [weak self] in self?.voice.sayChats() }
            ChatModel.shared.openWindow = { [weak self] in self?.chatWindow?.show() }
            chatWindow?.makeExplanation = { [weak self] in self?.visualExplanation() }
            chatWindow?.stopExplanation = { [weak self] in self?.explanation?.stop() }
            ChatModel.shared.onDeleteConversation = { [weak self] id, historyID in
                self?.deleteExplanationHistory(id, historyID: historyID)
            }
        }
        if on(.chatHotkey) { ChatHotkeyMonitor.shared.start { [weak self] in self?.chatWindow?.toggle() } }
        // Usage and limits from the agents' local logs; a cue when a limit gets close.
        if on(.usage) {
            UsageModel.shared.onAlert = { [weak self] text in self?.topBar.show(.usageAlert(text)) }
            UsageModel.shared.speakToday = { [weak self] in self?.voice.sayUsage() }
            UsageModel.shared.start()
        }
        if on(.proactive) { ProactiveController.shared.start() }
        if on(.stickiesRestore) { StickiesController.shared.restore() }
        if on(.routines) { RoutineRunner.shared.start() }
        demo = DemoDirector(buddy: buddy, notch: notch, statusItemFrame: { [weak self] in
            guard let item = self?.statusItem else { return nil }
            return item.button?.window?.frame
        }, say: { [weak self] text in
            self?.voice?.say(text)
        })

        // Real agent events from Claude Code hooks. The socket starts only after `commandHandler`
        // is wired below so `zeus debug dictate-file` never runs while launch is still wiring handlers.
        if on(.agentServer) {
            // Read this app's own signature now, off the main thread, before the socket opens: once Zeus.app is
            // replaced on disk while this process runs, the running copy can no longer be validated, and every
            // command that needs the peer check would be refused until the next launch.
            Task.detached(priority: .utility) { _ = PeerSigning.captureOwnIdentity() }
            agentServer = AgentEventServer(notch: notch)
        }
        if on(.helperRefresh) {
            if ClaudeHookInstaller.isInstalled() { try? ClaudeHookInstaller.refreshHelper() }
            if ChromeInstaller.isInstalled() {
                try? HelperInstaller.refresh("zeus-bridge")
                try? ChromeInstaller.refreshExtension()
            }
        }

        // Push-to-talk → Claude CLI → spoken, captioned answer + spark.
        if on(.voiceTurn) {
            voice = VoiceTurnController(buddy: buddy, notch: notch, brain: ClaudeCLIProvider())
            commands = CommandCenter(voice: voice)
        }
        // The fast path: instant app, media, volume, to-do, timer, link and lock commands.
        if on(.voiceTurn) { FastActions.shared.topBar = topBar }
        if on(.appIndex) { AppIndex.shared.start() }
        if on(.projectScanner) { ProjectScanner.shared.start() }
        if on(.topBarServices) { topBarServices.onTimerFinished = { [weak self] in self?.voice?.timerFinished() } }
        if on(.macControl) { startMacControl() }
        if on(.avatarFeed) { startAvatarFeed() }
        if on(.shortcuts) { registerShortcuts() }
        if on(.todo) {
            TodoController.shared.start()
            TodoController.shared.onReminderSaved = { [weak self] in self?.topBar.flash(.reminderPinned) }
            TodoController.shared.onCompleted = { AvatarStatus.shared.flash(.done) }
        }
        if on(.sleepWatch) { AvatarStatus.shared.startSleepWatch() }
        if on(.lockChimes) { LockChimeController.shared.start() }
        if on(.intelligence) {
            IntelligenceCenter.shared.onDecided = { [weak self] engine, intent in self?.topBar.show(.decided(engine: engine, summary: intent)) }
        }
        notch.allowKeyboard { [weak self] in
            guard let tab = self?.notch.topBar?.selectedTab else { return false }
            return (tab == .todo || tab == .reminders || tab == .chat) && self?.notch.model.presentation == .panel
        }
        AgentHub.shared.notch = notch
        if on(.notificationPeeker) {
            notificationPeeker.notch = notch
            notificationPeeker.start()
            notch.openNotificationLine = { line in NotificationsController.shared.openApp(line.app) }
        }
        // The notch mic: same dictation as the key, pasted where you were typing.
        if on(.voiceTurn) {
            topBar.speakBrief = { [weak self] text in self?.voice.sayTodayBrief(text) }
            topBar.speakNowPlaying = { [weak self] title, artist, playing in
                self?.voice.sayNowPlaying(title: title, artist: artist, playing: playing)
            }
            topBar.speakNothingPlaying = { [weak self] in self?.voice.sayNothingPlaying() }
            topBar.speakWeather = { [weak self] degrees, phrase, place in
                self?.voice.sayWeather(degrees: degrees, phrase: phrase, place: place)
            }
            topBar.speakWeatherNotReady = { [weak self] in self?.voice.sayWeatherNotReady() }
            topBar.speakBattery = { [weak self] level, charging, pluggedIn in
                self?.voice.sayBattery(level: level, charging: charging, pluggedIn: pluggedIn)
            }
            topBar.speakNoBattery = { [weak self] in self?.voice.sayNoBattery() }
            RemindersController.shared.speakAdded = { [weak self] result in self?.voice.sayReminder(result) }
            topBar.speakMeeting = { [weak self] title, place in self?.voice.sayMeeting(title: title, place: place) }
            topBar.speakNoMeeting = { [weak self] in self?.voice.sayNoMeeting() }
            topBar.speakNextEvent = { [weak self] title, when, allDay in
                self?.voice.sayNextEvent(title: title, when: when, allDay: allDay)
            }
            topBar.speakNoNextEvent = { [weak self] in self?.voice.sayNoNextEvent() }
            topBar.speakClock = { [weak self] time, period in
                self?.voice.sayClock(time: time, period: period)
            }
            topBar.speakWorldClock = { [weak self] readings in
                self?.voice.sayWorldClock(readings)
            }
            topBar.speakCountdown = { [weak self] title, days in
                self?.voice.sayCountdown(title: title, days: days)
            }
            topBar.speakNoCountdown = { [weak self] in self?.voice.sayNoCountdown() }
            topBar.speakDate = { [weak self] weekday, date in
                self?.voice.sayDate(weekday: weekday, date: date)
            }
            topBar.speakNote = { [weak self] text in self?.voice.sayNote(text) }
            topBar.speakNoNote = { [weak self] in self?.voice.sayNoNote() }
            topBar.speakSecretNote = { [weak self] in self?.voice.saySecretNote() }
            topBar.speakAgents = { [weak self] in self?.voice.sayAgents() }
            topBar.speakTimeLeft = { [weak self] in self?.voice.sayTimeLeft() }
            topBar.speakNextReminder = { [weak self] title, when in
                self?.voice.sayNextReminder(title: title, when: when)
            }
            topBar.speakNoNextReminder = { [weak self] in self?.voice.sayNoNextReminder() }
            topBar.speakNextReminderAccess = { [weak self] in self?.voice.sayNextReminderAccess() }
            topBar.speakAlerts = { [weak self] in self?.voice.sayAlerts() }
            topBar.speakTodoCount = { [weak self] in self?.voice.sayTodoCount() }
            topBar.speakAgenda = { [weak self] in self?.voice.sayAgenda() }
            topBar.speakShelf = { [weak self] in self?.voice.sayShelf() }
            topBar.speakRain = { [weak self] in self?.voice.sayRain() }
            topBar.speakWeek = { [weak self] in self?.voice.sayWeek() }
            topBar.speakClipboard = { [weak self] in self?.voice.sayClipboard() }
            topBar.speakRounds = { [weak self] in self?.voice.sayRounds() }
            topBar.speakWords = { [weak self] in self?.voice.sayWords() }
            topBar.speakDictation = { [weak self] in self?.voice.sayDictation() }
            topBar.speakPolyglot = { [weak self] in self?.voice.sayPolyglot() }
            topBar.speakRecording = { [weak self] in self?.voice.sayRecording() }
            topBar.speakDarkMode = { [weak self] in self?.voice.sayDarkMode() }
            topBar.speakTiling = { [weak self] in self?.voice.sayTiling() }
            topBar.speakScreens = { [weak self] in self?.voice.sayScreens() }
            topBar.speakEarbuds = { [weak self] in self?.voice.sayEarbuds() }
            topBar.speakOutput = { [weak self] in self?.voice.sayOutput() }
            topBar.speakScript = { [weak self] in self?.voice.sayScript() }
            InsomniaController.shared.speakLid = { [weak self] in self?.voice.sayLid() }
            InsomniaController.shared.speakHeat = { [weak self] in self?.voice.sayHeat() }
            WakeWordController.shared.speakWake = { [weak self] in self?.voice.sayHeyZeus() }
            VoiceSettings.shared.speakVoice = { [weak self] in self?.voice.sayVoiceChoice() }
            LicenseManager.shared.speakLicense = { [weak self] in self?.voice.sayLicense() }
            PermissionsModel.speakScreen = { [weak self] in self?.voice.sayScreenRecording() }
            DriveController.speakDrive = { [weak self] in self?.voice.sayDriveAutonomy() }
            NotchController.speakNotch = { [weak self] in self?.voice.sayNotchPlace() }
            NotchController.speakOpen = { [weak self] in self?.voice.sayNotchOpen() }
            HaloStyle.speakLight = { [weak self] in self?.voice.sayHaloLight() }
            HomeSlots.speakHome = { [weak self] in self?.voice.sayHomeCards() }
            SystemHUDSettings.speakLights = { [weak self] in self?.voice.sayNotchLights() }
            TopBarLayout.liveTitles = { [weak self] in
                self?.topBar.layout.trimmedToRow().tabs.map(\.title) ?? TopBarLayout.standard.trimmedToRow().tabs.map(\.title)
            }
            TopBarLayout.speakTabs = { [weak self] in self?.voice.sayTopBarTabs() }
            SoundCatalog.speakCues = { [weak self] in self?.voice.sayCueSounds() }
            DictationSettings.speakSetup = { [weak self] in self?.voice.sayDictationSetup() }
            ExtraPreferences.speakVoiceCues = { [weak self] in self?.voice.sayVoiceCues() }
            DayToDayVoice.speakDay = { [weak self] in self?.voice.sayDayToDay() }
            PrompterSetupVoice.speakSetup = { [weak self] in self?.voice.sayPrompterSetup() }
            BrowserAgentVoice.speakAgent = { [weak self] in self?.voice.sayBrowserAgent() }
            PolyglotSettings.speakSetup = { [weak self] in self?.voice.sayPolyglotSetup() }
            KeepAwakeSession.speakSetup = { [weak self] in self?.voice.sayKeepAwakeSetup() }
            FlingVoice.speakFling = { [weak self] in self?.voice.sayFlingSetup() }
            TilingSetupVoice.speakSetup = { [weak self] in self?.voice.sayTilingSetup() }
            CodingSetupVoice.speakSetup = { [weak self] in self?.voice.sayCodingSetup() }
            NotifySetupVoice.speakNotices = { [weak self] in self?.voice.sayNotifySetup() }
            FlingVoice.speakReceive = { [weak self] in self?.voice.sayReceiveSetup() }
            BeamerSetupVoice.speakSetup = { [weak self] in self?.voice.sayBeamerSetup() }
            PolyglotSettings.speakCaptions = { [weak self] in self?.voice.sayCaptionSetup() }
            PolyglotSettings.speakChord = { [weak self] in self?.voice.sayPolyglotChord() }
            AwakeHoldVoice.speakHold = { [weak self] in self?.voice.sayAwakeHold() }
            LiveTouchVoice.speakTouch = { [weak self] in self?.voice.sayLiveTouch() }
            PointerGlideVoice.speakGlide = { [weak self] in self?.voice.sayPointerGlide() }
            RoutineListVoice.speakList = { [weak self] in self?.voice.sayRoutineList() }
            RecordlyCaptureVoice.speakCapture = { [weak self] in self?.voice.sayRecordlyCapture() }
            AnswerPathVoice.speakPath = { [weak self] in self?.voice.sayAnswerPath() }
            AskFinishVoice.speakAsks = { [weak self] in self?.voice.sayAskFinish() }
            ShareSeenVoice.speakSeen = { [weak self] in self?.voice.sayShareSeen() }
            ModelCapVoice.speakCap = { [weak self] in self?.voice.sayModelCap() }
            FocusLengthVoice.speakLength = { [weak self] in self?.voice.sayFocusLength() }
            PlaybackModeVoice.speakModes = { [weak self] in self?.voice.sayPlaybackMode() }
            ReminderListVoice.speakList = { [weak self] in self?.voice.sayReminderList() }
            ExtraPreferences.speakEvents = { [weak self] in self?.voice.saySoundEvents() }
            OtherAppsVoice.speakApps = { [weak self] in self?.voice.sayOtherApps() }
            HomeSlots.speakStyles = { [weak self] in self?.voice.sayHomeStyles() }
            WeatherPlaceVoice.speakPlace = { [weak self] in self?.voice.sayWeatherPlace() }
            InsomniaSetupVoice.speakSetup = { [weak self] in self?.voice.sayInsomniaSetup() }
            DictationModeVoice.speakMode = { [weak self] in self?.voice.sayDictationMode() }
            VoiceGlowSettings.speakGlow = { [weak self] in self?.voice.sayVoiceGlow() }
            DictationRecordVoice.speakRecord = { [weak self] in self?.voice.sayDictationRecord() }
            InsomniaSetupVoice.speakNudge = { [weak self] in self?.voice.sayAgentNudge() }
            HomeFrameVoice.speakFrame = { [weak self] in self?.voice.sayHomeFrame() }
            ScreenCornerVoice.speakCorners = { [weak self] in self?.voice.sayScreenCorners() }
            NotchCloseVoice.speakClose = { [weak self] in self?.voice.sayNotchClose() }
            EverydayLightsVoice.speakLights = { [weak self] in self?.voice.sayEverydayLights() }
            HaloArmVoice.speakArm = { [weak self] in self?.voice.sayHaloArm() }
            MusicLightsVoice.speakLights = { [weak self] in self?.voice.sayMusicLights() }
            RunningCardVoice.speakCard = { [weak self] in self?.voice.sayRunningCard() }
            VoiceStyleVoice.speakStyle = { [weak self] in self?.voice.sayVoiceStyle() }
            LockChimeVoice.speakChimes = { [weak self] in self?.voice.sayLockChimes() }
            FacePresenceSetVoice.speakSet = { [weak self] in self?.voice.sayFacePresenceSet() }
            ResearchSetupVoice.speakSetup = { [weak self] in self?.voice.sayResearchSetup() }
            ScribeSetupVoice.speakSetup = { [weak self] in self?.voice.sayScribeSetup() }
            LanguagePackVoice.speakPacks = { [weak self] in self?.voice.sayLanguagePacks() }
            SpeakerSetupVoice.speakSetup = { [weak self] in self?.voice.saySpeakerSetup() }
            AccessVoice.speakAccess = { [weak self] in self?.voice.sayAccessSet() }
            ExtraSoundVoice.speakExtra = { [weak self] in self?.voice.sayExtraSounds() }
            HudExtraVoice.speakExtras = { [weak self] in self?.voice.sayHudExtras() }
            WavesSetupVoice.speakWaves = { [weak self] in self?.voice.sayWavesSetup() }
            NotchlessVoice.speakShape = { [weak self] in self?.voice.sayNotchless() }
            HomeBackdropVoice.speakBackdrop = { [weak self] in self?.voice.sayHomeBackdrop() }
            DictationSoundVoice.speakSound = { [weak self] in self?.voice.sayDictationSound() }
            DictationKeepVoice.speakKeep = { [weak self] in self?.voice.sayDictationKeep() }
            GrantVoice.speakGrants = { [weak self] in self?.voice.sayGrantSet() }
            JevSetupVoice.speakJev = { [weak self] in self?.voice.sayJevSetup() }
            PickerSetupVoice.speakPicker = { [weak self] in self?.voice.sayPickerSetup() }
            DefaultAgentVoice.speakAgent = { [weak self] in self?.voice.sayDefaultAgent() }
            LocalAccessVoice.speakLocal = { [weak self] in self?.voice.sayLocalAccess() }
            FastPathVoice.speakPath = { [weak self] in self?.voice.sayFastPath() }
            FlickSetupVoice.speakFlick = { [weak self] in self?.voice.sayFlickSetup() }
            HaloEntranceVoice.speakEntrance = { [weak self] in self?.voice.sayHaloEntrance() }
            TalkMicVoice.speakMic = { [weak self] in self?.voice.sayTalkMic() }
            ExplainSetupVoice.speakSetup = { [weak self] in self?.voice.sayExplainSetup() }
            ProactiveSetupVoice.speakSetup = { [weak self] in self?.voice.sayProactiveSetup() }
            ScriptSetupVoice.speakScript = { [weak self] in self?.voice.sayScriptSetup() }
            OfferSetupVoice.speakOffer = { [weak self] in self?.voice.sayOfferSetup() }
            ShareSetupVoice.speakShare = { [weak self] in self?.voice.sayShareSetup() }
            KeywordSetupVoice.speakWords = { [weak self] in self?.voice.sayKeywordSetup() }
            BannerSetupVoice.speakBanners = { [weak self] in self?.voice.sayBannerSetup() }
            FeedbackSetupVoice.speakFeedback = { [weak self] in self?.voice.sayFeedbackSetup() }
            DictateSwitchVoice.speakSwitch = { [weak self] in self?.voice.sayDictateSwitch() }
            ArrivalLightsVoice.speakLights = { [weak self] in self?.voice.sayArrivalLights() }
            HaloWashVoice.speakWash = { [weak self] in self?.voice.sayHaloWash() }
            BandSetupVoice.speakBands = { [weak self] in self?.voice.sayBandSetup() }
            HaloMeasureVoice.speakMeasure = { [weak self] in self?.voice.sayHaloMeasure() }
            TilingGapVoice.speakGaps = { [weak self] in self?.voice.sayTilingGaps() }
            HotspotSetupVoice.speakHotspot = { [weak self] in self?.voice.sayHotspotSetup() }
            HomeLaterVoice.speakLater = { [weak self] in self?.voice.sayHomeLater() }
            VoiceKeyVoice.speakKeys = { [weak self] in self?.voice.sayVoiceKeys() }
            UpdateSetupVoice.speakUpdates = { [weak self] in self?.voice.sayUpdateSetup() }
            VoiceTuneVoice.speakTune = { [weak self] in self?.voice.sayVoiceTune() }
            DictateHearVoice.speakHear = { [weak self] in self?.voice.sayDictateHear() }
            CommandSetupVoice.speakCommand = { [weak self] in self?.voice.sayCommandSetup() }
            NotchFitVoice.speakFit = { [weak self] in self?.voice.sayNotchFit() }
            QuietSetupVoice.speakQuiet = { [weak self] in self?.voice.sayQuietSetup() }
            FreezeSetupVoice.speakFreeze = { [weak self] in self?.voice.sayFreezeSetup() }
            AskWordsVoice.speakAsk = { [weak self] in self?.voice.sayAskWords() }
            LeftOutVoice.speakLeft = { [weak self] in self?.voice.sayLeftOut() }
            SeparateBrowserVoice.speakBrowser = { [weak self] in self?.voice.saySeparateBrowser() }
            VocabSetupVoice.speakVocab = { [weak self] in self?.voice.sayVocabSetup() }
            ExplainHearVoice.speakHear = { [weak self] in self?.voice.sayExplainHear() }
            ExplainHearVoice.captionOn = { [weak self] in self?.explanation?.muted == true }
            ExplainHearVoice.microphoneUID = { [weak self] in self?.explanation?.deviceUID }
            ExplainHearVoice.whisperOn = { [weak self] in self?.explanation?.useInstalledWhisper == true }
            OfferSetupVoice.claudeConnected = { [weak self] in self?.guideServices.isConnected(.claude) ?? false }
            OfferSetupVoice.codexConnected = { [weak self] in self?.guideServices.isConnected(.codex) ?? false }
            MusicLightsVoice.wingsOn = { [weak self] in
                self?.topBar.liveMusicWings ?? (UserDefaults.standard.object(forKey: "topBar.musicWings") as? Bool ?? true)
            }
            BeamerSetupVoice.continuityOn = { [weak self] in self?.topBar.layout.contains(.continuity) ?? false }
            PointingSettings.speakKeys = { [weak self] in self?.voice.sayPointingKeys() }
            PointingSettings.speakTrail = { [weak self] in self?.voice.sayPointTrail() }
            TalkSightVoice.speakSight = { [weak self] in self?.voice.sayTalkSight() }
            DrawnSizeVoice.speakSize = { [weak self] in self?.voice.sayDrawnSize() }
            PointingSettings.speakRoute = { [weak self] in self?.voice.sayPointRoute() }
            CompanionVoice.speakCompanion = { [weak self] in self?.voice.sayCompanion() }
            GatewayVoice.speakGateway = { [weak self] in self?.voice.sayGateway() }
            AssistantSettings.speakModel = { [weak self] in self?.voice.sayChatModel() }
            KokoroSetupVoice.speakKokoro = { [weak self] in self?.voice.sayKokoroSetup() }
            CloudVoiceVoice.speakCloud = { [weak self] in self?.voice.sayCloudVoice() }
            FlingPeerVoice.speakPeers = { [weak self] in self?.voice.sayFlingPeers() }
            VisualReadyVoice.speakReady = { [weak self] in self?.voice.sayVisualReady() }
            ShowMeVoice.speakShow = { [weak self] in self?.voice.sayShowMe() }
            LivesVoice.speakLives = { [weak self] in self?.voice.sayLives() }
            TalkHoldVoice.speakHold = { [weak self] in self?.voice.sayTalkHold() }
            ExtraKeyVoice.speakExtra = { [weak self] in self?.voice.sayExtraKey() }
            TodoSetupVoice.speakTodos = { [weak self] in self?.voice.sayTodoSetup() }
            BrainSetupVoice.speakBrain = { [weak self] in self?.voice.sayBrainSetup() }
            AgentFinishVoice.speakFinish = { [weak self] in self?.voice.sayAgentFinish() }
            ExtraOfferVoice.speakOffers = { [weak self] in self?.voice.sayExtraOffer() }
            HookShowVoice.speakHooks = { [weak self] in self?.voice.sayHookShow() }
            RecordlyExportVoice.speakExport = { [weak self] in self?.voice.sayRecordlyExport() }
            PasteSetupVoice.speakPaste = { [weak self] in self?.voice.sayPasteSetup() }
            ChatHotkeyMonitor.speakChat = { [weak self] in self?.voice.sayChatShortcut() }
            AssistantSettings.speakProvider = { [weak self] in self?.voice.sayProvider() }
            NowPlayingHub.speakSource = { [weak self] in self?.voice.sayMusicSource() }
            CardFinish.speakLook = { [weak self] in self?.voice.sayCardStyle() }
            BuddyPreference.speakShow = { [weak self] in self?.voice.sayPointerBuddy() }
            topBar.speakFocus = { [weak self] speech in self?.voice.sayFocus(speech) }
            topBar.speakQuickAdd = { [weak self] speech in
                switch speech {
                case .added(let event): self?.voice.sayAddedEvent(event)
                case .problem(let line): self?.voice.sayCalendarProblem(line)
                }
            }
            WelcomeBackCoordinator.shared.speak = { [weak self] text in self?.voice.say(text) }
        }
        if on(.shortcuts) {
            ExtraPreferences.shared.onShortcutsChange = { [weak self] in
                // The chord first, so it lets go of Control-Option-Space for a preset that moved onto it; then the shortcuts;
                // then the chord again, in case a preset moved off it and the chord can take it back.
                self?.syncTalkChord()
                self?.registerShortcuts()
                self?.syncTalkChord()
            }
        }
        if on(.settingsCatalog) {
            wireSettingsCatalog()
            // The meeting-start detector starts here, at launch, unless "When a meeting starts" is Off. It reads
            // which app holds the microphone, never audio, and then only waits until a meeting is near.
            ScribeCallWatcher.shared.follow()
        }
        if on(.settingsCatalog) { makeEqualiser() }
        if on(.updates) {
            UpdateCoordinator.shared.onBadgeDidChange = { [weak self] in self?.syncMenuBarUpdateBadge() }
            UpdateCoordinator.shared.startPolling()
            UpdateCoordinator.shared.refreshBadge()
        }
        if on(.windowSharing) { ZeusWindowSharing.refreshFromAppState(teleprompterSessionHidden: false) }
        if on(.updates) { syncMenuBarUpdateBadge() }
        if on(.voiceTurn) { wireDebugCommands() }
        if on(.agentServer) {
            CLIAccess.migrateLegacyDefault()
            agentServer.commandHandler = { [weak self] line, peer in
                guard let self, let commands = self.commands else { return nil }
                return await commands.handle(line, peer: peer)
            }
            agentServer.start()
        }
        if on(.cliInstall) { CLIInstaller.install() }
        if on(.assistantKeyImport) { AssistantKeyImporter.importDefaultIfNeeded() }
        if on(.talkHotkey) {
            // The monitor plays the installed talk cues. This path does not also play listenStart.
            hotkey.onPress = { [weak self] in self?.talkKeyPressed(builtinCue: false) ?? false }
            // Right Option shows the bar at the key-down. The microphone still opens in talkKeyPressed, when the hold
            // has stayed alone through the typing window.
            hotkey.onHoldAppear = { [weak self] in self?.buddy.call() }
            hotkey.onHoldHide = { [weak self] in self?.buddy.releaseUnansweredCall() }
            hotkey.onRelease = { [weak self] in
                WakeWordController.shared.talkKeyHeld = false
                self?.voice?.release(builtinCue: false)
            }
            // Right Command is Murmur, owned by the dictation monitor. This talk monitor must not start a second session.
            hotkey.onListenAccessMissing = { [weak self] in
                if let cue = KeyAccessNotice.cue(granted: false) { self?.topBar.show(.permission(cue.text, pane: cue.pane)) }
            }
            hotkey.onBlocked = { [weak self] message in self?.voice?.keysBlocked(message) }
            // Space may join the bare Control-Option hold (the talk chord); the dictation key never has one. Every event reads
            // the value the sync points stored (start, access granted, a Chat or shortcut change, VoiceOver, any setting), so the
            // key path asks neither the system for access nor Carbon for the hot key again.
            hotkey.chordProvider = { [weak self] in self?.cachedTalkChord?.keyCode }
            // Right Option, the second talk key, is read the same way.
            hotkey.secondKeyProvider = { [weak self] in self?.cachedSecondTalkKey }
            // A turn that stops listening for its own reason (a failed start, the owner ending it) is told to the key
            // machine, so the next press starts a turn instead of being spent on one that is gone.
            voice?.onListeningEnded = { [weak self] in
                WakeWordController.shared.talkKeyHeld = false
                self?.hotkey.turnEnded()
            }
            // A chord or a key that joins the talk keys cancels the hold instead of sending it.
            hotkey.onCancel = { [weak self] in
                WakeWordController.shared.talkKeyHeld = false
                self?.voice?.cancelListening()
            }
            hotkey.start()
            syncTalkChord()
            // The chord only takes Space once the monitors can hear keys; when access comes later, it takes it then.
            KeyListenAccess.whenGranted { [weak self] in self?.syncTalkChord() }
            ChatHotkeyMonitor.shared.onChange = { [weak self] in self?.syncTalkChord() }
            // A recorder in Settings listens for any chord, so the Carbon hot keys let go while it does.
            ShortcutRecorderModel.pauseGlobalHotkeys = { paused in
                ChatHotkeyMonitor.shared.setPaused(paused)
                TalkChordHotkey.shared.setPaused(paused)
            }
            talkChordDefaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                // syncTalkChord returns the chord; Xcode 26.1 cannot infer the closure type from a discarded result.
                MainActor.assumeIsolated { _ = self?.syncTalkChord() }
            }
            cancelTalkChordVoiceOverWatch = TilingKeyClash.watchVoiceOver { [weak self] in self?.syncTalkChord() }
        }
        if on(.pointingHotkey) {
            syncPointing()
            // The setting can change while Zeus runs; the hold monitor starts or stops with it.
            pointingSettingsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncPointing() }
            }
        }
        if on(.tiling) {
            syncTiling()
            // The switch can change while Zeus runs; tiling starts or stops with it.
            tilingSettingsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncTiling() }
            }
        }
        if on(.polyglotHotkey) {
            PolyglotController.shared.onHint = { [weak self] text in self?.topBar.show(.hint(text)) }
            PolyglotController.shared.installHotkey()
        }
        VoicePermissions.showDenied = { [weak self] text, pane in self?.topBar.show(.permission(text, pane: pane)) }
        if on(.permissionStatusRead) { permissions.refresh() }
        if on(.permissionStatusRead), let notice = KeyAccessNotice.cue(granted: KeyListenAccess.granted) {
            VoiceLog.log("keys", "neither Accessibility nor Input Monitoring is on: the talk shortcut can't be seen outside Zeus windows")
            topBar.show(.permission(notice.text, pane: notice.pane))
        }
        // "Hey Zeus": off until the user turns it on (WakeWordController reads `wake.enabled`, default false),
        // on-device wake detection, and launch never prompts for a permission.
        if on(.wakeWord) { WakeWordController.shared.start(voice: voice, topBar: topBar) }
        // Face presence: off until the owner turns it on; with it on, launch reads the vault and opens no camera.
        if on(.facePresence) {
            FacePresenceController.shared.speakFace = { [weak self] in self?.voice.sayFace() }
            FacePresenceController.shared.start(permissions: .live(permissions))
        }

        if on(.panelUI), let preferences {
            panel = MenuBarPanel(
                rootView: PanelView(
                    connections: connections,
                    permissions: permissions,
                    preferences: preferences,
                    playDemo: { [weak self] in self?.playDemo() },
                    openSetup: { [weak self] in self?.showOnboarding() },
                    openSettings: { [weak self] in self?.showSettings() },
                    quit: { NSApp.terminate(nil) }
                )
            )
        }
        if on(.connectionsRefresh) { Task { await connections.refresh() } }

        // First launch: a short setup that asks for each permission with an explanation.
        // The demo never plays by itself; it's in the panel, the menu and the last setup step.
        if on(.autoOnboarding), OnboardingProgress.opensAtLaunch(OnboardingFlow.launchProgress, explicitStepRequested: OnboardingParity.requestedStep != nil) {
            showOnboarding(restart: false)
        }
        if on(.demoArg), CommandLine.arguments.contains("--demo") { demo.play() }
        if on(.motionOpenArg) { motionOpenIfRequested() }
        // An "Allow all" sweep that macOS interrupted (Screen Recording's Quit and Reopen) picks up where it
        // stopped. Only a sweep the person started minutes ago resumes; nothing is asked twice.
        if on(.settingsWindow) { permissionSweep.resumeIfSaved { [weak self] in self?.showPermissions() } }
    }

    private var sensitiveCueTask: Task<Void, Never>?

    /// Keeps the capture cue visible for the whole capture: re-shown until cleared with nil.
    private func setSensitiveCue(_ text: String?) {
        sensitiveCueTask?.cancel()
        sensitiveCueTask = nil
        guard let text else { return }
        topBar.show(.hint(text))
        sensitiveCueTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.topBar.show(.hint(text))
            }
        }
    }

    /// The `zeus debug` handlers behind the command center (not wired in a QA startup).
    private func wireDebugCommands() {
        commands.onDebugOpenSettings = { [weak self] sectionName -> Bool in
            guard let self else { return false }
            self.panel?.close()
            if let sectionName, !sectionName.isEmpty {
                guard let section = GSSection.matching(sectionName) else {
                    return false
                }
                self.glanceSettings.show(section)
            } else {
                self.glanceSettings.show()
            }
            return true
        }
        commands.onSensitiveCue = { [weak self] text in
            self?.setSensitiveCue(text)
        }
        commands.onOfferKeyRemoval = { source in
            AssistantKeyImporter.offerRemoval(of: source)
        }
        commands.onDebugOnboarding = { [weak self] isPreview in
            guard let self else { return }
            self.showOnboarding(restart: !isPreview)
        }
        commands.onDebugScreenshot = { [weak self] base, filter in
            guard let self else { return [] }
            var named: [(name: String, window: NSWindow)] = []
            if let w = self.notch.debugWindow { named.append(("notch", w)) }
            if let w = self.glanceSettings.debugWindow { named.append(("settings", w)) }
            if let w = self.guide.debugWindow { named.append(("onboarding", w)) }
            return DebugScreenshot.capture(windows: named, base: base, filter: filter)
        }
        commands.onDebugTab = { [weak self] tabName in
            guard let self else { return false }
            let lower = tabName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard let tab = TopBarTab.allCases.first(where: { $0.rawValue.lowercased() == lower || $0.title.lowercased() == lower }) else { return false }
            self.topBar.selectedTab = tab
            self.notch.show(.panel)
            return true
        }
        commands.onDebugHUDState = { [weak self] in
            self?.topBar.hudStateJSON() ?? "{}"
        }
        commands.onDebugPermissions = { [weak self] in
            guard let self else { return "ERROR permissions model unavailable" }
            self.permissions.refresh()
            return self.permissions.capturePermissionsReport
        }
        commands.onDebugPresence = { arg in
            switch arg.lowercased() {
            case "on": CursorPresenceController.isEnabled = true
            case "off":
                CursorPresenceController.isEnabled = false
                CursorPresenceController.shared.stop()
            default: break
            }
            let on = CursorPresenceController.isEnabled
            let tracking = CursorPresenceController.shared.isTracking
            // `currentFrame()` is AppKit coordinates (bottom-left origin); `zeus debug` and the
            // E2E harness compare against Quartz-space pointer positions (top-left origin, same
            // as AXSnapshot and screenshots), so flip before reporting -- see `CursorAnchor.
            // flipToQuartz`.
            let mainHeight = NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height ?? 0
            let frame = CursorPresenceController.shared.currentFrame().map { CursorAnchor.flipToQuartz($0, mainScreenHeight: mainHeight) }
            let frameText = frame.map { "{\"x\":\($0.origin.x),\"y\":\($0.origin.y),\"w\":\($0.size.width),\"h\":\($0.size.height)}" } ?? "null"
            return "{\"presence.nearCursor\":\(on),\"tracking\":\(tracking),\"frame\":\(frameText)}"
        }
        commands.onDebugDictateFile = { [weak self] path in
            guard let self else { return "ERROR no app" }
            let resolved = DebugAudioPath.resolve(path)
            let url = URL(fileURLWithPath: resolved)
            guard FileManager.default.fileExists(atPath: url.path) else { return "ERROR file not found: \(resolved)" }
            // E2E dictation clips must run Murmur first. Wake-before-dictation let a false wake
            // or a stale history `ok` pass while TextEdit stayed empty (integrator FIX 02:16).
            let murmur = await self.dictation.injectDictationFile(url)
            if murmur == "ok" { return murmur }
            if let wake = await WakeWordController.shared.injectWakeFile(url) { return wake }
            return murmur
        }
        commands.onDebugWakeFile = { path in
            let resolved = DebugAudioPath.resolve(path)
            let url = URL(fileURLWithPath: resolved)
            guard FileManager.default.fileExists(atPath: url.path) else { return "ERROR file not found: \(resolved)" }
            return await WakeWordController.shared.injectWakeFile(url) ?? "ERROR wake not heard"
        }
        commands.onDebugHandsLive = { [weak self] in
            guard let self else { return "FAIL no app" }
            return HandsLive.run { cue in
                let point = CGPoint(x: cue.x, y: cue.y)
                self.buddy.point(to: point, label: cue.label)
            } onPreview: { preview in
                self.notch.model.workBehind = preview
                if preview?.streaming == true { self.notch.show(.peek) }
                if preview == nil, self.notch.model.selectionEdit == nil { self.notch.show(.closed) }
            }
        }
        commands.onDebugSelection = { [weak self] edit in
            HandsHUD.shared.present(edit, notch: self?.notch)
        }
        commands.onDebugUpdate = { arg in
            let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "clear" {
                UpdateCoordinator.shared.setDebugFakeVersion(nil)
                return "update fake cleared"
            }
            if trimmed.hasPrefix("fake ") {
                let version = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                UpdateCoordinator.shared.setDebugFakeVersion(version)
                return "update fake \(version)"
            }
            if trimmed == "dismiss" {
                UpdateCoordinator.shared.dismissCurrent()
                return "update dismissed"
            }
            return "update usage: fake <version> | clear | dismiss"
        }
        commands.onDebugScreenShare = { arg in
            let store = SettingsStore.shared
            switch arg.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "on":
                store.set(ZeusScreenSharePolicy.showInSharingKey, "true")
                ZeusWindowSharing.refreshFromAppState(teleprompterSessionHidden: false)
                return "screen-share on"
            case "off":
                store.set(ZeusScreenSharePolicy.showInSharingKey, "false")
                ZeusWindowSharing.refreshFromAppState(teleprompterSessionHidden: false)
                return "screen-share off"
            case "state":
                let show = store.bool(ZeusScreenSharePolicy.showInSharingKey)
                let visible = ZeusScreenSharePolicy.zeusSurfacesVisible(
                    showInScreenSharing: show,
                    meetingActive: MeetingState.active,
                    teleprompterSessionHidden: false
                )
                return "showInScreenSharing=\(show) visibleInCapture=\(visible) statusItem=always"
            default:
                return "screen-share usage: on | off | state"
            }
        }
        commands.onDebugEngineLogos = { path async in
            let directory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            do {
                let paths = try EngineBrandSnapshotExport.writeRows(to: directory, scales: [2, 4])
                return paths.joined(separator: "\n")
            } catch {
                return "ERROR \(error)"
            }
        }
        commands.onDebugRecord = { arg async in
            await RecordlyController.shared.runDebug(plan: RecordlyDebugPlanParser.parse(arg))
        }
        commands.onDebugAnimate = { [weak self] effect in
            guard let self else { return false }
            let lower = effect.lowercased()
            let captureBoost: TimeInterval = 3.5
            NotchControllerBridge.controller?.boostCaptureVisibility(for: captureBoost)
            ScreenEdgeGlowController.shared.boostCaptureVisibility(for: captureBoost)
            EdgeWaveController.shared.boostCaptureVisibility(for: captureBoost)
            ScreenCornerOverlay.shared.boostCaptureVisibility(for: captureBoost)
            TilingFocusBorder.shared.boostCaptureVisibility(for: captureBoost)
            TilingKeySheet.shared.boostCaptureVisibility(for: captureBoost)
            return NotchDebugAnimator.run(lower, topBar: self.topBar)
        }
    }

    /// `Zeus --motion-open 3`: opens the notch 3 s after launch and again 4 s after that (each held
    /// 3 s, then closed), with no pointer involved, so a 60 fps recording of the open/close motion
    /// (or of tab clicks made below the hover zone) catches only Zeus, not Glance. The second open is
    /// the warm one, like a normal hover.
    private func motionOpenIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--motion-open"), flag + 1 < arguments.count,
              let delay = Double(arguments[flag + 1]) else { return }
        Task { @MainActor [notch] in
            try? await Task.sleep(for: .seconds(delay))
            for _ in 0..<2 {
                notch.show(.panel)
                try? await Task.sleep(for: .seconds(3))
                notch.show(.closed)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard on(.deepLinks) else { return }
        DeepLinks.isDictating = { [weak self] in self?.topBar.isDictating ?? false }
        DeepLinks.requestDictationStart = { [weak self] in
            guard let self else { return }
            if let tab = TopBarTab.allCases.first(where: { $0.rawValue.lowercased() == "dictation" || $0.title.lowercased() == "dictation"
                || $0.rawValue.lowercased() == "murmure" || $0.title.lowercased() == "murmure" }) {
                self.topBar.selectedTab = tab
            }
            self.notch.show(.panel)
            self.topBar.show(.hint("A link asked Zeus to start dictation. Press the dictation key or mic here to begin."))
        }
        DeepLinks.openSettings = { [weak self] section in
            self?.showSettings(GSSection.allCases.first { $0.rawValue.lowercased() == section && $0.isShown })
        }
        DeepLinks.handle(urls)
    }

    /// Opening ZEUS again (Finder, Spotlight) shows the panel, or Settings when the menu bar
    /// icon is hidden or crowded out, so ZEUS is always reachable.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard on(.panelUI) else { return false }
        if statusItem.isVisible, let buttonWindow = statusItem.button?.window, buttonWindow.frame.width > 0,
           buttonWindow.occlusionState.contains(.visible) {
            openPanel(below: buttonWindow.frame)
        } else if on(.settingsWindow) {
            showSettings()
        } else if let buttonWindow = statusItem.button?.window {
            openPanel(below: buttonWindow.frame)
        }
        return false
    }

    /// Whether a turn opened: false tells the key machine nothing is listening, so no release or cancel is owed.
    private func talkKeyPressed(builtinCue: Bool = true) -> Bool {
        guard on(.talkHotkey), voice != nil else { return false }
        switch CommandHotkeyAccess.press(voice: hotkeyVoice(VoicePermissions.access)) {
        case .start:
            return beginTalkHold(builtinCue: builtinCue)
        case .ask:
            ExplanationAudioArbitration.yieldToNewCapture()
            WakeWordController.shared.talkKeyHeld = true
            buddy.call()
            VoiceLog.log("key", "talk shortcut pressed (access \(VoicePermissions.access))")
            NotificationCenter.default.post(name: Speaker.talkKeyPressed, object: nil)
            Task { @MainActor in
                let access = await VoicePermissions.ensure(explicit: true)
                switch CommandHotkeyAccess.recover(voice: self.hotkeyVoice(access), keyStillDown: self.hotkey.shortcutIsDown()) {
                case .start:
                    self.hotkey.noteRecoveredHold()
                    if !self.beginTalkHold(builtinCue: builtinCue) { self.hotkey.cancelRecoveredHold() }
                case .degradeVoice:
                    WakeWordController.shared.talkKeyHeld = false
                case .wait:
                    WakeWordController.shared.talkKeyHeld = false
                    if access == .ready {
                        self.topBar.show(.hint("Zeus can hear you now: hold Control + Option again"))
                    }
                case .ask:
                    WakeWordController.shared.talkKeyHeld = false
                }
            }
            return false
        case .degradeVoice:
            WakeWordController.shared.talkKeyHeld = false
            Task { @MainActor in _ = await VoicePermissions.ensure(explicit: true) }
            return false
        case .wait:
            WakeWordController.shared.talkKeyHeld = false
            return false
        }
    }

    private func hotkeyVoice(_ access: VoiceAccess) -> CommandHotkeyAccess.Voice {
        switch access {
        case .ready: .ready
        case .needsPrompt: .needsPrompt
        case .denied: .denied
        }
    }

    /// Opens the talk hold. False means the microphone did not start.
    private func beginTalkHold(builtinCue: Bool) -> Bool {
        guard on(.talkHotkey), voice != nil else { return false }
        ExplanationAudioArbitration.yieldToNewCapture()
        WakeWordController.shared.talkKeyHeld = true
        buddy.call()
        VoiceLog.log("key", "talk shortcut pressed (access \(VoicePermissions.access))")
        NotificationCenter.default.post(name: Speaker.talkKeyPressed, object: nil)
        let took = voice?.press(builtinCue: builtinCue) ?? false
        if !took { WakeWordController.shared.talkKeyHeld = false }
        return took
    }

    /// Desktop pointing: on by default (`docs/FIRST-RUN-DEFAULTS.md`). Starting it only installs the key
    /// listener (gated by the owner's own Accessibility/Input Monitoring grant); no capture and no
    /// prompt happens until the keys are held, and a screenshot needs Screen Recording already granted.
    private func syncPointing() {
        guard on(.pointingHotkey) else { return }
        syncDictationPreset()
        if PointingSettings.enabled { pointingController().start() }
        else if let pointing { pointing.stop(); self.pointing = nil; pointingProviders = nil }
    }

    /// Tiling: off until the owner turns it on (`tiling.enabled`). Starting it installs the key layer and waits for
    /// Accessibility without a prompt; turning it off removes everything. Cheap when nothing changed, because the
    /// settings notify on every preference write.
    private func syncTiling() {
        guard on(.tiling) else { return }
        if FeatureSettings.tilingEnabled() { TilingController.shared.start() } else { TilingController.shared.stop() }
    }

    /// The optional Fn+Control dictation key. Off by default; turning it off restores the previous key.
    private func syncDictationPreset() {
        let defaults = UserDefaults.standard
        let current = Shortcut.stored(ShortcutStore.loadDictation(defaults))
        guard let step = DictationFnControlPreset.next(wanted: PointingSettings.dictationFnControl, current: current,
                                                       saved: defaults.string(forKey: DictationFnControlPreset.savedKey)) else { return }
        let next: Shortcut? = Shortcut.parse(step.key)
        guard next != nil || step.key == "off" else { return }
        if let saved = step.saved { defaults.set(saved, forKey: DictationFnControlPreset.savedKey) }
        else { defaults.removeObject(forKey: DictationFnControlPreset.savedKey) }
        DictationSettings.shared.key = next
    }

    private func pointingController() -> PointingController {
        if let pointing { return pointing }
        let acquire: () throws -> Void = { [weak self] in
            guard let self, !self.topBar.isDictating, self.voice?.isListening != true,
                  !ScribeController.shared.phase.isActive,
                  ![RecordlyController.Phase.starting, .recording, .stopping].contains(RecordlyController.shared.phase) else {
                throw ExplanationMicrophoneError.busy
            }
            self.voice?.stopSpeaking()
            WakeWordController.shared.talkKeyHeld = true
            ExplanationAudioArbitration.onTakeover = { [weak self] in self?.pointing?.interrupt() }
        }
        let release = {
            ExplanationAudioArbitration.onTakeover = nil
            WakeWordController.shared.talkKeyHeld = false
        }
        let providers = PointingProviders(
            anyLLM: { (AIConnections.shared.anyLLM, AIConnections.shared.anyLLMCredential()) },
            localOnly: { FeatureSettings.bool("explanation.localOnly", default: false) },
            anyLLMComplete: { AIConnections.shared.anyLLM.isComplete })
        // In memory only: a desktop session is never written to disk.
        let controller = ExplanationController(provider: providers.model, speechProvider: providers.speech,
            microphone: ExplanationMicrophone(acquire: acquire, release: release), acquireAudio: acquire, releaseAudio: release)
        controller.localInput = dictation?.whisperKit
        let marker = PointingController.Marker(
            listen: { [weak self] in self?.buddy.listen() },
            think: { [weak self] in self?.buddy.think() },
            idle: { [weak self] in self?.buddy.idle() },
            flight: { [weak self] point, label in self?.buddy.flight(to: point, label: label) != nil })
        let pointing = PointingController(explanation: controller, marker: marker,
            prepare: { await providers.prepareTurn() },
            recordAudio: { providers.recordFirstAudio(secondsSinceRelease: $0) })
        pointing.onNotice = { [weak self] notice in
            switch notice {
            case .hint(let text): self?.topBar.show(.hint(text))
            case .permission(let text, let pane): self?.topBar.show(.permission(text, pane: pane))
            }
        }
        pointing.hotkey.onUnavailable = { [weak self] in
            self?.topBar.show(.permission("Pointing needs Input Monitoring or Accessibility to see the hold keys.", pane: "Privacy_ListenEvent"))
        }
        self.pointing = pointing; pointingProviders = providers
        buddy.onPointingClick = { [weak pointing] point in
            if WalkthroughController.shared.isRunning { return true }
            return pointing?.guideClick(at: point) ?? false
        }
        return pointing
    }

    private func visualExplanation() -> ExplanationController? {
        guard on(.chatWindow), FeatureSettings.bool("explanation.enabled", default: false) else { return nil }
        if let explanation { return explanation }
        let acquire: () throws -> Void = { [weak self] in
            guard let self, !self.topBar.isDictating, self.voice?.isListening != true,
                  !ScribeController.shared.phase.isActive,
                  ![RecordlyController.Phase.starting, .recording, .stopping].contains(RecordlyController.shared.phase) else {
                throw ExplanationMicrophoneError.busy
            }
            self.voice?.stopSpeaking()
            WakeWordController.shared.talkKeyHeld = true
            ExplanationAudioArbitration.onTakeover = { [weak self] in self?.explanation?.stop() }
        }
        let release = {
            ExplanationAudioArbitration.onTakeover = nil
            WakeWordController.shared.talkKeyHeld = false
        }
        let provider = ExplanationHTTPProvider(configuration: {
            (AIConnections.shared.anyLLM, AIConnections.shared.anyLLMCredential())
        }, localOnly: { FeatureSettings.bool("explanation.localOnly", default: false) })
        let storeFactory: () throws -> ExplanationHistoryStore = {
            guard let root = ExplanationHistoryStore.productionRootURL() else { throw CocoaError(.fileNoSuchFile) }
            return try ExplanationHistoryStore(root: root)
        }
        let store = try? storeFactory()
        let microphone = ExplanationMicrophone(acquire: acquire, release: release)
        let controller = ExplanationController(provider: provider, speechProvider: SystemExplanationSpeechOutput(),
            microphone: microphone, store: store, storeFactory: storeFactory, acquireAudio: acquire, releaseAudio: release)
        controller.localInput = dictation?.whisperKit
        controller.onSubmission = { [weak controller] text in
            guard let history = controller?.history else { return }
            ChatModel.shared.retainVisualConversation(title: text, explanationID: history.id,
                                                     conversationID: history.canonicalScene.sessionID)
        }
        explanation = controller
        return controller
    }

    private func deleteExplanationHistory(_ id: UUID, historyID: UUID) {
        guard explanationDeletionTasks[historyID] == nil else { return }
        // Admission is synchronous: delete→quit in the same run loop cannot
        // outrun the asynchronous deletion task and silently retain the record.
        failedExplanationDeletions[historyID] = id
        explanationDeletionTasks[historyID] = Task { @MainActor [weak self] in
            guard let self else { return }
            let removed: Bool
            if let explanation = self.explanation { removed = await explanation.deleteConversation(id, expectedHistoryID: historyID) }
            else if let root = ExplanationHistoryStore.productionRootURL(), let store = try? ExplanationHistoryStore(root: root) {
                do {
                    do { try await store.delete(id: historyID) }
                    catch ExplanationHistoryStore.StoreError.notFound { /* Exact target is already absent. */ }
                    let list: ExplanationHistoryStore.Listing?
                    do { list = try await store.list() }
                    catch ExplanationHistoryStore.StoreError.notFound { list = nil }
                    for record in list?.records ?? [] where record.sessionID == id {
                        do { try await store.delete(id: record.id) }
                        catch ExplanationHistoryStore.StoreError.notFound { /* Already removed. */ }
                    }
                    removed = true
                } catch { removed = false }
            } else { removed = false }
            if removed { self.failedExplanationDeletions[historyID] = nil }
            else { self.topBar.show(.hint("Linked explanation history could not be deleted. Zeus will retry before quitting.")) }
            self.explanationDeletionTasks[historyID] = nil
        }
    }

    private func playDemo() {
        guard on(.demoPlayback) else { return }
        panel.close()
        demo.play()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // A QA startup keeps the status item but opens nothing from it: no panel, no context menu.
        guard on(.panelUI) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if panel.isVisible {
            panel.close()
        } else if let buttonWindow = sender.window {
            openPanel(below: buttonWindow.frame)
        }
    }

    private func openPanel(below frame: NSRect) {
        guard on(.panelUI) else { return }
        if on(.connectionsRefresh) { Task { await connections.refresh() } }
        permissions.refresh()
        panel.show(below: frame)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Set Up ZEUS…", action: #selector(setupFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Play Demo", action: #selector(playDemoFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Chat with ZEUS…", action: #selector(openChatFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Teleprompter Window", action: #selector(openPrompterFromMenu), keyEquivalent: "").target = self
        let stop = menu.addItem(withTitle: "Stop Speaking", action: #selector(stopSpeakingFromMenu), keyEquivalent: "")
        stop.target = self
        stop.isEnabled = voice?.isSpeaking == true || explanation?.isBusy == true
        menu.autoenablesItems = false
        menu.addItem(.separator())
        menu.addItem(ScreenShareQuickToggle.menuItem(target: self, action: #selector(toggleScreenShareFromMenu)))
        ScreenShareQuickToggle.installCatcher(on: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit ZEUS", action: #selector(quitFromMenu), keyEquivalent: "").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // keep left click for the panel
    }

    @objc private func setupFromMenu() { showOnboarding() }
    @objc private func playDemoFromMenu() { playDemo() }
    @objc private func openChatFromMenu() {
        guard on(.chatWindow) else { return }
        chatWindow?.show()
    }
    @objc private func openPrompterFromMenu() {
        guard on(.teleprompter) else { return }
        PrompterHub.shared.toggle()
    }
    @objc private func stopSpeakingFromMenu() { explanation?.stop(); voice?.stopSpeaking() }
    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func toggleScreenShareFromMenu() {
        guard ScreenShareQuickToggle.allowMenuAction() else { return }
        ScreenShareQuickToggle.toggle()
    }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    /// The welcome guide (Sources/Zeus/Onboarding), Glance's seven steps.
    private lazy var guideServices: OnboardingServices = {
        let services = OnboardingServices(permissions: permissions)
        services.prepareDictationModel = { [weak self] in self?.dictation.prepareModel() }
        return services
    }()

    private lazy var guide: OnboardingWindowController = {
        let guide = OnboardingWindowController(services: guideServices)
        guide.onFinish = { [weak self] in self?.permissions.refresh() }
        return guide
    }()

    private func showOnboarding(restart: Bool = true) {
        guard on(.onboardingWindow) else { return }
        panel?.close()
        // Lane B Glance guide (960×760, films + living mascot). Parity hook for frame tests.
        if let step = OnboardingParity.requestedStep { guide.flow.step = step }
        guide.show(restart: restart && OnboardingParity.requestedStep == nil)
    }

    /// "Allow all" (Settings > Permissions). One per app so a sweep macOS interrupts can resume at launch.
    private lazy var permissionSweep = PermissionSweepRunner(services: guideServices)

    /// Settings (Sources/Zeus/Settings), Glance's window and sections.
    private lazy var glanceSettings: GlanceSettingsWindowController = {
        let context = GSContext(services: guideServices)
        context.restartConnection = { [weak self] in
            self?.agentServer.stop()
            self?.agentServer.start()
        }
        context.connectionUp = { [weak self] in self?.agentServer.lastError == nil }
        context.copyLastDictation = { SettingsStore.shared.actions["dictation.copyLast"]?() }
        context.openGuide = { [weak self] in self?.showOnboarding() }
        context.showLicenses = { [weak self] in self?.showThirdPartyLicenses() }
        context.topBar = topBar
        context.drawnNotch = DrawnNotchModel.shared
        context.sweep = permissionSweep
        context.equaliser = { [weak self] in self?.equaliser }
        context.continuityTabShown = { [weak self] in self?.topBar.layout.contains(.continuity) ?? false }
        context.setContinuityTabShown = { [weak self] on in
            guard let layout = self?.topBar.layout, layout.contains(.continuity) != on else { return }
            self?.topBar.layout.toggle(.continuity)
        }
        return GlanceSettingsWindowController(context: context)
    }()

    private func showSettings(_ section: GSSection? = nil) {
        guard on(.settingsWindow) else { return }
        panel.close()
        glanceSettings.show(section)
    }

    /// What ships with Zeus that other people made, and where each project's license text lives.
    private func showThirdPartyLicenses() {
        let alert = NSAlert()
        alert.messageText = "Third-party licenses"
        alert.informativeText = """
        Apple's on-device speech recognition is part of macOS: no third-party model.

        Murmure's optional engines download only when you ask. Parakeet runs through the FluidAudio package (github.com/FluidInference/FluidAudio) and Whisper through WhisperKit (github.com/argmaxinc/argmax-oss-swift, MIT). Each project's license text is in its repository.

        Type: Plus Jakarta Sans, SIL Open Font License.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Every in-app "Allow" lands here: Settings > Permissions explains, then asks.
    private func showPermissions() {
        guard on(.settingsWindow) else { return }
        panel.close()
        permissions.refresh()
        glanceSettings.show(.permissions)
    }

    private var teleprompterPrivate = false
    private var lastHidden: Bool?
    private var chimePolicy = AgentChimePolicy()
    private var lastApprovalSeen = false
    private var approvalBoltShown = false
    private var lastFailed = 0
    private var feedTicks = 0
    private var lastMeetingCheck = Date.distantPast
    private let agentsAwake = KeepAwake(kind: .system)
    private let notificationPeeker = NotificationPeeker()
    private var menuBarBadgeHost: NSHostingView<MenuBarUpdateBadge>?

    /// Builds the equaliser with its live ports and runs the launch housekeeping. Only the owner's own stored switch
    /// starts it, so a switch left on carries over and one left off leaves no listener, no tap and no prompt.
    private func makeEqualiser() {
        let controller = EqualiserController(
            defaults: .standard,
            factory: LiveShapingTapFactory(),
            monitor: AudioProcessMonitor(),
            claim: EqualiserFileClaim(),
            scheduler: MainEqualiserScheduler(),
            ownBundleID: Bundle.main.bundleIdentifier ?? "",
            ownPID: ProcessInfo.processInfo.processIdentifier,
            zeusCaptures: {
                let polyglot = PolyglotController.shared
                let recordly = RecordlyController.shared
                return EqualiserPolicy.zeusCaptures(
                    scribe: ScribeController.shared.phase,
                    polyglotActive: polyglot.isListening || polyglot.isStarting,
                    recordlySystemAudio: recordly.isRecording && recordly.audio.systemAudio)
            },
            onProvenAllowed: { AudioSpectrumService.shared.recordProvenAllowed() },
            capturePermission: { AudioSpectrumService.shared.permission },
            observesSystem: true)
        controller.launch(switchOn: SettingsStore.shared.bool("audio.equaliser"))
        equaliser = controller
    }

    /// Actions and live facts behind catalog rows (Settings, generated from the Glance inventory).
    private func wireSettingsCatalog() {
        let store = SettingsStore.shared
        store.onChange = { [weak self] id in
            switch id {
            case "general.launchAtLogin": LaunchAtLogin.set(store.bool(id))
            case "shortcut.answerKeys": self?.registerShortcuts()
            case "notch.displays": self?.notch.refreshDisplays(force: true)
            case MusicAwakeHold.settingID: MusicAwakeHold.shared.setEnabled(store.bool(id))
            case ScribeAutoStartMode.settingID: ScribeCallWatcher.shared.follow()
            case ZeusScreenSharePolicy.showInSharingKey:
                ZeusWindowSharing.refreshFromAppState(teleprompterSessionHidden: self?.teleprompterPrivate ?? false)
            case FacePresenceController.switchID, FacePresenceController.lockAfterID:
                FacePresenceController.shared.settingChanged(id)
            case "about.autoUpdate", "about.updateFeedURL":
                UpdateCoordinator.shared.refreshBadge()
            case AudioSpectrumService.liveKey: AudioSpectrumService.shared.liveSpectrumChanged(on: store.bool(id))
            case "audio.equaliser": self?.equaliser?.setSwitch(store.bool(id))
            case ChimeSettingsKey.enabled, ChimeSettingsKey.volume, ChimeSettingsKey.closePath, ChimeSettingsKey.openPath:
                LockChimeController.shared.reload()
            case AudioSpectrumService.sensitivityKey: AudioSpectrumService.shared.sensitivityChanged()
            case "screen.roundBottomCorners", "screen.cornerRadius": ScreenCornerOverlay.shared.settingsChanged()
            default: break
            }
        }
        store.actions = [
            "general.runSetup": { [weak self] in self?.showOnboarding() },
            "voice.resetWords": {
                for id in ["voice.approveWords", "voice.denyWords", "voice.openWords"] {
                    store.set(id, SettingsCatalog.option(id)?.defaultValue ?? "")
                }
            },
            "dictation.copyLast": { [weak self] in
                guard let last = self?.topBar.dictationHistory.first?.result, !last.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(last, forType: .string)
            },
            "privacy.openAccessibility": {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            },
            "music.openExtensions": { ChromeInstaller.showExtensionsPage() },
            "diag.restart": { [weak self] in
                self?.agentServer.stop()
                self?.agentServer.start()
            },
            "dictation.licenses": { [weak self] in self?.showThirdPartyLicenses() },
        ]
    }

    private func syncMenuBarUpdateBadge() {
        guard let button = statusItem.button else { return }
        if case .available = UpdateCoordinator.shared.badgeState {
            if menuBarBadgeHost == nil {
                let host = NSHostingView(rootView: MenuBarUpdateBadge())
                host.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(host)
                NSLayoutConstraint.activate([
                    host.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
                    host.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: 4),
                ])
                menuBarBadgeHost = host
            }
            menuBarBadgeHost?.isHidden = false
        } else {
            menuBarBadgeHost?.isHidden = true
        }
    }

    /// Points at Approve and says the same line as Play Demo. A missing button shows "Not found".
    private func showLiveApproval() {
        let found = notch.approveButtonPoint != nil
        let step = PlayDemoScript.liveApproval(approveButtonFound: found)
        if let point = notch.approveButtonPoint {
            buddy.point(to: point, label: step.bolt)
        } else {
            buddy.showCaption(step.bolt)
        }
        voice?.say(step.spoken)
    }

    private func playAgentChime(_ cue: AgentChimePolicy.Cue?) {
        switch cue {
        case .start: ZeusSound.play(.start)
        case .done: ZeusSound.play(.done)
        case .approval: ZeusSound.play(.approval)
        case .answer: ZeusSound.play(.answer)
        case nil: break
        }
    }

    /// Sounds on new approvals and finished agents, and keeps windows out of screen shares when asked.
    private func feedExtras() {
        let extras = ExtraPreferences.shared
        let approval = notch.model.approval != nil
        let now = Date()
        playAgentChime(chimePolicy.approval(visible: approval, at: now))
        if approval != lastApprovalSeen {
            if approval, demo?.isPlaying != true {
                showLiveApproval()
                approvalBoltShown = true
            } else if !approval, approvalBoltShown {
                approvalBoltShown = false
                buddy.idle()
            }
            lastApprovalSeen = approval
            registerShortcuts()
        }
        let startEnabled = SettingsStore.shared.bool("sound.agentStart")
        for session in notch.model.sessions {
            playAgentChime(chimePolicy.session(session.id, status: session.status, at: now, startEnabled: startEnabled))
        }
        chimePolicy.forget(keeping: Set(notch.model.sessions.map(\.id)))
        let working = notch.model.sessions.filter { $0.status == .working }.count
        let failed = notch.model.sessions.filter { $0.status == .failed }.count
        if failed > lastFailed, SettingsStore.shared.bool("sound.failure") { ZeusSound.play(.failure) }
        lastFailed = failed
        // The loop also ends when Sound feedback is turned off or Meeting mode begins, not only when the agents stop.
        let loopWanted = working > 0 && SettingsStore.shared.bool("sound.runningLoop") && extras.soundsOn && !MeetingState.active
        if loopWanted { ZeusSound.startRunningLoop() } else { ZeusSound.stopRunningLoop() }
        WelcomeBackCoordinator.shared.poll(notch: notch)
        let options = SettingsStore.shared
        agentsAwake.set(options.bool("general.keepAwake") && working > 0)
        feedTicks += 1
        if now.timeIntervalSince(lastMeetingCheck) >= 2 {
            lastMeetingCheck = now
            MeetingState.refresh(ownMicInUse: topBar.isDictating || AvatarStatus.shared.current == .listening)
            earbudsWatch.poll()
            let agents = Dictionary(grouping: notch.model.sessions, by: \.agent).map { "\($0.key) · \($0.value.count)" }.sorted()
            options.statusOverrides["diag.agents"] = agents.isEmpty ? (false, "None yet") : (true, agents.joined(separator: ", "))
        }
        let show = SettingsStore.shared.bool(ZeusScreenSharePolicy.showInSharingKey)
        let policyHidden = !ZeusScreenSharePolicy.zeusSurfacesVisible(
            showInScreenSharing: show,
            meetingActive: MeetingState.active,
            teleprompterSessionHidden: teleprompterPrivate
        )
        if policyHidden != lastHidden {
            lastHidden = policyHidden
        }
        ZeusWindowSharing.refreshFromAppState(teleprompterSessionHidden: teleprompterPrivate)
    }

    /// Puts the Carbon registration that takes Control-Option-Space in step with the chord the clash rule allows right now, and
    /// stores that chord and the second talk key for the key path. A refused registration is asked again here, at the sync
    /// points, and not on every key.
    @discardableResult
    private func syncTalkChord() -> Shortcut? {
        let chord = TalkChordRouting.current(heard: hotkey.keyProvider(), shared: hotkey.sharedProvider()).chord
        TalkChordHotkey.shared.sync(chord, listening: KeyListenAccess.granted)
        let second = SecondTalkRouting.current().key
        let changed = cachedTalkChord != chord || cachedSecondTalkKey != second
        cachedTalkChord = chord
        cachedSecondTalkKey = second
        SecondTalkRouting.lastSynced = second
        // The monitor reads the stored values on events and ticks only, so one tick tells it of a change at once: the second key
        // turned off in the middle of a hands-free turn ends that turn now, not at the next key.
        if changed { hotkey.configChanged() }
        return chord
    }

    private func registerShortcuts() {
        let extras = ExtraPreferences.shared
        HotKeyCenter.shared.set(raw: [
            (extras.openNotch, { [weak self] in
                // The agent picker: the agent list with a highlighted row (arrows, Return, Esc).
                self?.notch.togglePicker()
            }),
            (extras.quickTodo, { [weak self] in self?.openQuickTodo() }),
        ].compactMap { preset, action in preset.keyCode.map { ($0, preset.modifiers, action) } } + answerKeys() + PrompterHub.shared.hotkeys())
    }

    /// Control Option Y, N, O answer a waiting request; registered only while one waits.
    private func answerKeys() -> [(UInt32, UInt32, () -> Void)] {
        guard SettingsStore.shared.bool("shortcut.answerKeys"), notch.model.approval != nil else { return [] }
        let mods = UInt32(controlKey | optionKey)
        func answer(_ verdict: HookDecision.Verdict) -> () -> Void {
            { [weak self] in self?.notch.model.approval?.resolve(verdict) }
        }
        return [(UInt32(kVK_ANSI_Y), mods, answer(.allow)), (UInt32(kVK_ANSI_N), mods, answer(.deny)), (UInt32(kVK_ANSI_O), mods, answer(.ask))]
    }

    private func openQuickTodo() {
        notch.topBar?.selectedTab = .todo
        notch.show(.panel)
        TodoController.shared.requestFocus()
    }

    /// Show-me drawing, drive mode and walkthroughs share the notch, the spark and the voice.
    private func startMacControl() {
        DriveController.shared.notch = notch
        DriveController.shared.say = { [weak self] text in self?.voice.say(text) }
        DriveController.shared.showSpark = { [weak self] text in self?.buddy.showCaption(text) }
        DriveController.shared.hideSpark = { [weak self] in self?.buddy.hideCaption() }
        BrowserAgentRunner.shared.notch = notch
        BrowserAgentRunner.shared.chrome = voice?.chrome
        BrowserAgentRunner.shared.say = { [weak self] text in self?.voice.browserSaid(text) }
        BrowserAgentRunner.shared.showSpark = { [weak self] text in self?.buddy.showCaption(text) }
        BrowserAgentRunner.shared.hideSpark = { [weak self] in self?.buddy.hideCaption() }
        CodeActions.shared.notch = notch
        CodeActions.shared.say = { [weak self] text in self?.voice.say(text) }
        ResearchRunner.shared.notch = notch
        ResearchRunner.shared.say = { [weak self] text in self?.voice.say(text) }
        ResearchRunner.shared.showSources = { [weak self] plan, speak in self?.voice.showResearch(plan, speak: speak) }
        ResearchRunner.shared.showReportSaved = { [weak self] plan, line, speak in self?.voice.showReportSaved(plan, line: line, speak: speak) }
        ResearchRunner.shared.showReportMiss = { [weak self] plan, line, speak in self?.voice.showReportMiss(plan, line: line, speak: speak) }
        ResearchRunner.shared.showResearchAsk = { [weak self] plan, line, speak in self?.voice.showResearchAsk(plan, line: line, speak: speak) }
        ResearchRunner.shared.showAnswerFail = { [weak self] plan, line, speak in self?.voice.showResearchFailure(plan, line: line, speak: speak) }
        ResearchRunner.shared.showClaudeTool = { [weak self] plan, line, speak in self?.voice.showResearchClaudeTool(plan, line: line, speak: speak) }
        earbudsNotch.topBar = topBar
        earbudsNotch.say = { [weak self] text in self?.voice.say(text) }
        earbudsNotch.hideDetails = { MeetingState.hideDetails }
        earbudsWatch.present = { [weak self] facts, id, speak in
            self?.earbudsNotch.present(facts, id: id, speak: speak)
        }
        WalkthroughController.shared.buddy = buddy
        WalkthroughController.shared.say = { [weak self] text in self?.voice.walkthroughSaid(text) }
        AnnotationController.shared.onMark = { [weak self] prompt, shots in
            guard let self else { return }
            Task { @MainActor in _ = await self.voice?.annotationTurn(prompt, screenshots: shots) }
        }
        AnnotationController.shared.start()
    }

    /// Feeds the avatar the ambient states it can't hear about directly.
    private func startAvatarFeed() {
        scheduleAvatarFeed(after: 0.25)
    }

    /// One feed tick, then the next one: 4 Hz while something is live (voice, approval,
    /// prompter), 1 Hz when ZEUS is idle, so an idle Mac wakes it a quarter as often.
    private func scheduleAvatarFeed(after interval: TimeInterval) {
        let feed = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                defer { self.scheduleAvatarFeed(after: self.feedIsLive ? 0.25 : 1) }
                let avatar = AvatarStatus.shared
                avatar.set(\.speaking, self.voice?.isSpeaking ?? false)
                avatar.set(\.needsApproval, self.notch.model.approval != nil)
                avatar.set(\.agentWorking, self.notch.model.sessions.contains { $0.status == .working })
                let phase = self.topBar.roll.phase
                avatar.set(\.prompting, phase == .countdown || phase == .rolling || phase == .paused)
                self.feedExtras()
                // Assign only on change: an equal write still wakes every observing view.
                let listening = self.voice?.isListening ?? false
                if self.topBar.micListening != listening { self.topBar.micListening = listening }
                let level = Double(self.buddy.model.audioLevel ?? 0)
                if self.topBar.micLevel != level { self.topBar.micLevel = level }
                let held = WakeWordController.shared.talkKeyHeld
                if self.topBar.talkHeld != held { self.topBar.talkHeld = held }
            }
        }
        feed.tolerance = interval * 0.4
    }

    private var feedIsLive: Bool {
        (voice?.isSpeaking ?? false) || (voice?.isListening ?? false) || WakeWordController.shared.talkKeyHeld
            || topBar.isDictating || notch.model.approval != nil
            || [.countdown, .rolling, .paused].contains(topBar.roll.phase)
    }
}
