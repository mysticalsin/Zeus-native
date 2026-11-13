import AppKit
import CoreAudio
import AudioToolbox
import EventKit
import IOKit.ps
import ZeusCore

/// Feeds `TopBarModel` from the system. Every source is optional: nothing here asks for a
/// permission until the person opens the matching page and taps the button that needs it.
@MainActor
final class TopBarServices {
    let model: TopBarModel
    /// A voice timer ran out (the voice says so; the notch cue and sound play either way).
    var onTimerFinished: () -> Void = {}
    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var musicSyncTasks: [NowPlaying.Player: Task<Void, Never>] = [:]
    /// Bumped by each player notification, so a slower state read started earlier never overwrites it.
    private var musicRevision: [NowPlaying.Player: Int] = [:]
    /// Runs the shuffle and repeat sends and reads one after another, so a press is read back after its own script.
    private var musicModesTask: Task<Void, Never>?
    /// Bumped by each press, reset and new read, so a slower earlier read never overwrites a newer state.
    private var musicModesRevision = 0
    private var flagsMonitor: Any?
    private var capsOn = NSEvent.modifierFlags.contains(.capsLock)
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let eventStore = EKEventStore()
    private var volumeDevice = AudioObjectID(kAudioObjectUnknown)
    private var lastVolume: Float32 = -1
    private var lastWeatherFetch = Date.distantPast
    private var lastBatteryCue: Int?
    private var keyMonitor: Any?
    private var systemKeyMonitor: Any?
    private var shiftGate = ShiftPeekGate()
    private var rainGate = RainAlertGate()
    private var hudMonitor: SystemHUDMonitor?
    private var intakeWatcher: AirDropScreenshotWatcher?

    init(model: TopBarModel) {
        self.model = model
    }

    func start() {
        model.musicCommand = { [weak self] command in self?.music(command) }
        model.seek = { [weak self] seconds in self?.seek(to: seconds) }
        model.chooseOutputDevice = { [weak self] in self?.showOutputDevices() }
        model.requestCalendarAccess = { [weak self] in self?.requestCalendar() }
        model.refreshWeather = { [weak self] in self?.fetchWeather(force: true) }
        model.fetchEvents = { [weak self] start, end in self?.events(from: start, to: end) ?? [] }
        model.createEvent = { [weak self] parsed in await self?.saveEvent(parsed) ?? .failed("Calendar isn't available.") }

        observeMusic()
        observeClipboard()
        observeCapsLock()
        observeVolume()
        let monitor = SystemHUDMonitor(model: model)
        hudMonitor = monitor
        monitor.start(volumeDevice: { [weak self] in self?.volumeDevice ?? AudioObjectID(kAudioObjectUnknown) },
                      currentVolume: { [weak self] in self?.currentVolume() })
        pollBattery()
        refreshCalendarIfAllowed()
        fetchWeather(force: false)
        updateIntakeWatcher()
        BannerAutoDismisser.shared.update()

        every(1) { [weak self] in self?.tickFocus() }
        every(60) { [weak self] in
            self?.pollBattery()
            self?.refreshCalendarIfAllowed()
            self?.fetchWeather(force: false)
            self?.updateIntakeWatcher()
            BannerAutoDismisser.shared.update()
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCalendarIfAllowed() }
        })
    }

    /// Removes the app launch/quit observers and stops pending music reads.
    func stop() {
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        for task in musicSyncTasks.values { task.cancel() }
        musicSyncTasks.removeAll()
        musicModesTask?.cancel()
        musicModesTask = nil
    }

    private func every(_ seconds: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in MainActor.assumeIsolated { body() } }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    // MARK: Music (public player notifications; controls through Apple Events on first tap)

    private func observeMusic() {
        let center = DistributedNotificationCenter.default()
        for player in [NowPlaying.Player.music, .spotify] {
            observers.append(center.addObserver(forName: .init(player.notificationName), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                let parsed = NowPlaying.parse(info, player: player)
                MainActor.assumeIsolated {
                    self?.musicRevision[player, default: 0] += 1
                    self?.updateMusic(parsed, player: player)
                }
            })
        }
        // Apps launching or quitting: catch music already playing, and drop a track whose player is gone.
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let player = app?.bundleIdentifier.flatMap(NowPlaying.Player.init(bundleID:)) else { return }
            MainActor.assumeIsolated { self?.syncMusicSoon(player, delays: [2, 5, 10]) }
        })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let player = app?.bundleIdentifier.flatMap(NowPlaying.Player.init(bundleID:)) else { return }
            MainActor.assumeIsolated {
                self?.musicSyncTasks[player]?.cancel()
                self?.updateMusic(nil, player: player)
            }
        })
        // Music already playing at launch sends no notification. The Automation check is asynchronous,
        // so the first tries may find it unresolved; each try stops once it could read (or nothing runs).
        for player in [NowPlaying.Player.music, .spotify] { syncMusicSoon(player, delays: [1.5, 4, 9]) }
    }

    /// Reads the player's current state a few times with growing gaps, stopping after the first try that could.
    private func syncMusicSoon(_ player: NowPlaying.Player, delays: [TimeInterval]) {
        musicSyncTasks[player]?.cancel()
        musicSyncTasks[player] = Task { @MainActor [weak self] in
            for delay in delays {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                if await self.syncMusic(player) { return }
            }
        }
    }

    /// One read of the player's state through Apple Events. True when it is settled (answered, or the
    /// player isn't running); false when Automation isn't confirmed yet. Never prompts: without
    /// consent no AppleScript runs at all.
    private func syncMusic(_ player: NowPlaying.Player) async -> Bool {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty == false else { return true }
        guard Automation.allowed(player.bundleID) else { return false }
        let revision = musicRevision[player, default: 0]
        let output = await SpotifyPlayer.osascript(NowPlaying.probeScript(player: player))
        // A notification that arrived during the read is newer than this answer.
        guard musicRevision[player, default: 0] == revision else { return true }
        guard !Task.isCancelled,
              NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty == false else { return true }
        let playing = NowPlaying.parseProbe(output, player: player)
        // A notification that arrived during the read is fresher; don't override another player that is playing.
        if let current = model.nowPlaying, current.player != player, current.isPlaying { return true }
        if let playing {
            updateMusic(playing, player: player, announce: false)
        } else if output != nil {
            // A stopped player (or one with no track) leaves nothing to show; a failed read changes nothing.
            updateMusic(nil, player: player)
        }
        return true
    }

    private func updateMusic(_ playing: NowPlaying?, player: NowPlaying.Player, announce: Bool = true) {
        let previous = model.nowPlaying
        if let playing {
            model.nowPlaying = playing
            // Shuffle and repeat belong to one player: another player starts from unknown. They are read
            // again when the player or the track changes, never on a timer.
            if previous?.player != playing.player { resetMusicModes() }
            if previous?.player != playing.player || previous?.title != playing.title || previous?.artist != playing.artist {
                refreshMusicModes(playing.player)
            }
            if announce, previous?.title != playing.title, playing.isPlaying {
                model.show(.trackChanged(title: playing.title, artist: playing.artist))
            }
        } else if previous?.player == player {
            model.nowPlaying = nil
            resetMusicModes()
        }
        ArtworkStore.shared.request(for: model.nowPlaying)
    }

    /// Scrub: `set player position` through Apple Events, only for a running player Zeus may already
    /// script (it never prompts here). The bar moves at once; the player confirms on its next notification.
    private func seek(to seconds: Double) {
        guard var playing = model.nowPlaying else { return }
        let target = MusicSeek.clampedTarget(seconds, duration: playing.duration)
        let player = playing.player
        guard NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty == false else { return }
        guard Automation.allowed(player.bundleID) else {
            model.show(.hint(PermissionsModel.hint(.automation)))
            return
        }
        playing.position = target
        playing.positionAt = Date()
        model.nowPlaying = playing
        let source = MusicSeek.script(player: player, seconds: target)
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { NSLog("[ZEUS] seek failed: %@", error) }
        }
    }

    // MARK: Output devices

    private func showOutputDevices() {
        let devices = OutputDevices.all()
        let menu = NSMenu(title: "Output")
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(OutputDeviceTarget.choose(_:)), keyEquivalent: "")
            item.target = OutputDeviceTarget.shared
            item.representedObject = device.id
            item.state = device.isDefault ? .on : .off
            menu.addItem(item)
        }
        if devices.isEmpty { menu.addItem(withTitle: "No outputs found", action: nil, keyEquivalent: "") }
        model.menuOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        model.menuOpen = false
    }

    private func music(_ command: TopBarModel.MusicCommand) {
        let player = model.nowPlaying?.player ?? .music
        if command == .open {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            return
        }
        let verb: String? = switch command {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        case .toggleShuffle, .cycleRepeat, .open: nil
        }
        // Only talk to a player that is already running, so a tap never launches one.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty == false else { return }
        // Apple Events would prompt the first time; without consent the notch points to Settings.
        guard Automation.allowed(player.bundleID) else {
            NSLog("[ZEUS] permissions: Automation off for %@, showing hint", player.bundleID)
            model.show(.hint(PermissionsModel.hint(.automation)))
            return
        }
        guard let verb else {
            changeMusicMode(command, player: player)
            return
        }
        // Off the main thread and bounded: a hung player must never freeze the notch.
        let source = "tell application id \"\(player.bundleID)\" to \(verb)"
        Task.detached(priority: .userInitiated) { _ = await SpotifyPlayer.osascript(source) }
        if command == .playPause, var playing = model.nowPlaying {
            playing.position = playing.elapsed()
            playing.positionAt = Date()
            playing.isPlaying.toggle()
            model.nowPlaying = playing
        }
    }

    // MARK: Shuffle and repeat

    private func isRunning(_ player: NowPlaying.Player) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty == false
    }

    /// The control moves at once, the change is sent, then the player is read once and the control
    /// follows what it says. Runs after `music(_:)` has checked the player is running and allowed.
    private func changeMusicMode(_ command: TopBarModel.MusicCommand, player: NowPlaying.Player) {
        var modes = model.musicModes
        let source: String
        switch command {
        case .toggleShuffle:
            let on = !(modes.shuffle ?? false)
            modes.shuffle = on
            source = MusicModeRules.setShuffleScript(player: player, on: on)
        case .cycleRepeat:
            let next = MusicModeRules.nextRepeat(after: modes.repeatMode, player: player)
            modes.repeatMode = next
            source = MusicModeRules.setRepeatScript(player: player, mode: next)
        case .playPause, .next, .previous, .open:
            return
        }
        model.musicModes = modes
        musicModesRevision += 1
        let revision = musicModesRevision
        enqueueMusicModes { services in
            _ = await SpotifyPlayer.osascript(source)
            await services.readMusicModes(player, revision: revision)
        }
    }

    /// Reads the modes for a new player or track. Skipped when the player is not running or not allowed.
    private func refreshMusicModes(_ player: NowPlaying.Player) {
        musicModesRevision += 1
        let revision = musicModesRevision
        enqueueMusicModes { await $0.readMusicModes(player, revision: revision) }
    }

    private func resetMusicModes() {
        musicModesRevision += 1
        model.musicModes = MusicModes()
    }

    private func enqueueMusicModes(_ work: @escaping @MainActor (TopBarServices) async -> Void) {
        let previous = musicModesTask
        musicModesTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await work(self)
        }
    }

    /// One bounded read through Apple Events; never prompts, and only for a running player Zeus may script.
    /// A failed read changes nothing; an empty or unreadable answer leaves the modes unknown.
    private func readMusicModes(_ player: NowPlaying.Player, revision: Int) async {
        guard musicModesRevision == revision, isRunning(player), Automation.allowed(player.bundleID) else { return }
        let output = await SpotifyPlayer.osascript(MusicModeRules.readScript(player: player))
        guard let output, musicModesRevision == revision, !Task.isCancelled, isRunning(player) else { return }
        model.musicModes = MusicModeRules.parse(output, player: player) ?? MusicModes()
    }

    // MARK: Clipboard (concealed and transient items, like passwords, are never kept)

    private func observeClipboard() {
        every(0.5) { [weak self] in self?.checkClipboard() }
    }

    private func checkClipboard() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount
        let types = board.types ?? []
        let skip = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
        guard !types.contains(where: { skip.contains($0.rawValue) }) else { return }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName
        let added: Bool
        switch ClipboardMedia.read(board) {
        case .files(let urls): added = model.clipboard.addFiles(urls.map(\.path), sourceApp: app)
        case .image(let file, let width, let height): added = model.clipboard.addImage(file: file, width: width, height: height, sourceApp: app)
        case .none:
            guard let text = board.string(forType: .string) else { return }
            added = model.clipboard.add(text, sourceApp: app)
        }
        if added {
            ClipboardMedia.prune(keeping: model.clipboard.imageFilesInUse)
            model.show(.copied(model.clipboard.entries.first?.preview ?? ""))
            model.flash(.copySweep)
        }
    }

    // MARK: Caps Lock

    private func observeCapsLock() {
        AccessibilityGate.whenTrusted { [weak self] in self?.observeKeys() }
    }

    private func observeKeys() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let on = flags.contains(.capsLock)
            let shiftAlone = flags.subtracting(.capsLock) == .shift
            MainActor.assumeIsolated {
                guard let self else { return }
                self.shift(down: shiftAlone)
                guard on != self.capsOn else { return }
                self.capsOn = on
                self.model.show(.capsLock(on))
                self.model.flash(.capsLock(on))
            }
        }
        // ⌘ shortcut peeks, and any key cancels a pending Shift peek. Needs Accessibility; silent without it.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let command = flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option)
            let chars = event.charactersIgnoringModifiers ?? ""
            let shift = flags.contains(.shift)
            let code = event.keyCode
            MainActor.assumeIsolated {
                guard let self else { return }
                self.shiftGate.otherKey()
                if code == 144 || code == 145 { self.brightnessChanged() }
                guard command, let peek = ShortcutPeek.lookup(chars, shift: shift),
                      SettingsStore.shared.bool("lights.shortcutPeeks") else { return }
                self.model.show(.shortcut(peek))
                self.model.flash(.shortcut(peek.motion))
            }
        }
        // Brightness keys arrive as system-defined events (subtype 8, key 2 up / 3 down).
        systemKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8 else { return }
            let key = (event.data1 & 0xFFFF0000) >> 16
            let down = ((event.data1 & 0xFF00) >> 8) == 0xA
            guard down, key == 2 || key == 3 else { return }
            MainActor.assumeIsolated { self?.brightnessChanged() }
        }
    }

    private func shift(down: Bool) {
        shiftGate.shift(down: down, at: Date())
        guard down else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(520))
            guard let self, self.shiftGate.fire(at: Date()) else { return }
            self.model.flash(.shiftCrest)
        }
    }

    private func brightnessChanged() {
        hudMonitor?.brightnessAccelerator()
    }

    // MARK: Volume (Core Audio listener on the default output)

    private func observeVolume() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachVolumeListener() }
        }
        attachVolumeListener()
    }

    private func attachVolumeListener() {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != volumeDevice else { return }
        volumeDevice = device
        lastVolume = currentVolume() ?? -1
        VoiceLog.log("cue", "volume listener on output device \(device), volume \(lastVolume)")
        // The virtual main volume is synthesized by AudioHardwareService and often never notifies;
        // the device's own scalar volume (main element and the stereo channels) does. Listen to all.
        let listens: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1), (kAudioDevicePropertyVolumeScalar, 2),
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
        ]
        for (selector, element) in listens {
            var volumeAddress = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(device, &volumeAddress) else { continue }
            AudioObjectAddPropertyListenerBlock(device, &volumeAddress, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.volumeChanged() }
            }
        }
    }

    private func currentVolume() -> Float32? {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(volumeDevice, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    private func isMuted() -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(volumeDevice, &address, 0, nil, &size, &muted) == noErr else { return false }
        return muted != 0
    }

    private func volumeChanged() {
        guard let volume = currentVolume() else { return }
        let muted = isMuted()
        defer { lastVolume = volume }
        guard abs(volume - lastVolume) > 0.001 || muted else { return }
        hudMonitor?.volumeChanged(volume: volume, muted: muted)
    }

    // MARK: Battery

    private func pollBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let level = current * 100 / max
            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let previous = model.battery
            model.battery = .init(level: level, charging: charging, pluggedIn: plugged)
            if let previous, previous.pluggedIn != plugged {
                if plugged { model.show(.charging(level)) }
                model.flash(.battery(level: Double(level) / 100, charging: plugged))
            } else if !plugged, level <= 10, lastBatteryCue != level {
                lastBatteryCue = level
                model.show(.lowBattery(level))
            }
            return
        }
    }

    // MARK: Calendar and reminders (EventKit, asked only from the Calendar page)

    private func requestCalendar() {
        Task { @MainActor in
            let events = (try? await eventStore.requestFullAccessToEvents()) ?? false
            _ = try? await eventStore.requestFullAccessToReminders()
            model.calendarAccess = events ? .granted : .denied
            refreshCalendarIfAllowed()
        }
    }

    /// Events between two dates, as the page shows them (nothing without full access; never asks).
    private func events(from start: Date, to end: Date) -> [TopBarModel.CalendarItem] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(300)
            .map(Self.item)
    }

    private static func item(_ event: EKEvent) -> TopBarModel.CalendarItem {
        TopBarModel.CalendarItem(
            id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "Event",
            start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
            colorHex: hex(event.calendar?.color), location: event.location,
            meetingURL: event.url.flatMap { MeetingLink.find(in: [$0.absoluteString]) } ?? MeetingLink.find(in: [event.location, event.notes]),
            calendarName: event.calendar?.title, notes: event.notes
        )
    }

    /// Saves an event on the default calendar. Calendar access is asked for here, the first time someone
    /// adds an event (the system sheet), and never before.
    private func saveEvent(_ parsed: CalendarQuickAdd.Parsed) async -> TopBarModel.EventCreateResult {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            break
        case .notDetermined:
            let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
            guard granted else { model.calendarAccess = .denied; return .needsAccess }
            model.calendarAccess = .granted
        default:
            model.calendarAccess = .denied
            return .needsAccess
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents else { return .failed("No calendar accepts new events. Add one in Calendar.") }
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = parsed.title
        event.startDate = parsed.start
        event.endDate = parsed.end
        event.isAllDay = parsed.isAllDay
        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            return .failed("The calendar wouldn't save that event.")
        }
        refreshCalendarIfAllowed()
        return .created(id: event.eventIdentifier ?? "")
    }

    private func refreshCalendarIfAllowed() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess: model.calendarAccess = .granted
        case .denied, .restricted, .writeOnly: model.calendarAccess = .denied; return
        default: model.calendarAccess = .unknown; return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? start
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        model.events = eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(20)
            .map(Self.item)
        model.refreshCalendarMonth()
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        let reminderPredicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        eventStore.fetchReminders(matching: reminderPredicate) { [weak self] reminders in
            let items = (reminders ?? []).prefix(20).map {
                TopBarModel.ReminderItem(id: $0.calendarItemIdentifier, title: $0.title ?? "Reminder",
                                         due: $0.dueDateComponents?.date, done: $0.isCompleted)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.model.reminders = Array(items) } }
        }
    }

    private static func hex(_ color: NSColor?) -> UInt32 {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return 0x4DA3FF }
        return UInt32(rgb.redComponent * 255) << 16 | UInt32(rgb.greenComponent * 255) << 8 | UInt32(rgb.blueComponent * 255)
    }

    // MARK: Weather (Open-Meteo: free, no key; the city comes from Settings or the time zone)

    private func fetchWeather(force: Bool) {
        guard force || Date().timeIntervalSince(lastWeatherFetch) > 20 * 60 else { return }
        lastWeatherFetch = Date()
        let city = model.weatherCity.isEmpty ? Self.cityFromTimeZone() : model.weatherCity
        guard !city.isEmpty else { return }
        Task { @MainActor in
            do {
                let place = try await Self.geocode(city)
                let (data, _) = try await URLSession.shared.data(from: WeatherSnapshot.url(latitude: place.lat, longitude: place.lon))
                let snapshot = try WeatherSnapshot.decode(data)
                model.weather = snapshot
                if let minutes = rainGate.minutesUntilRain(snapshot) { model.show(.rain(minutes: minutes)) }
                model.weatherPlace = place.name
                model.weatherError = nil
            } catch {
                model.weatherError = "Weather is unavailable right now."
            }
        }
    }

    /// "America/Sao_Paulo" → "Sao Paulo". Good enough for a zero-setup default.
    static func cityFromTimeZone() -> String {
        let id = TimeZone.current.identifier
        guard id.contains("/") else { return "" }
        return String(id.split(separator: "/").last ?? "").replacingOccurrences(of: "_", with: " ")
    }

    private struct Place: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        var lat: Double { latitude }
        var lon: Double { longitude }
    }

    private static func geocode(_ city: String) async throws -> Place {
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        parts.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1")]
        struct Response: Decodable { let results: [Place]? }
        let (data, _) = try await URLSession.shared.data(from: parts.url!)
        guard let place = try JSONDecoder().decode(Response.self, from: data).results?.first else {
            throw URLError(.cannotFindHost)
        }
        return place
    }

    // MARK: Intake (AirDrop and Screenshots)

    func updateIntakeWatcher() {
        let store = SettingsStore.shared
        let airDropEnabled = store.bool("lights.airDrop") && FolderAccess.status(for: .downloads) == .granted
        let screenshotEnabled = store.bool("lights.screenshot") && FolderAccess.status(for: .desktop) == .granted

        guard airDropEnabled || screenshotEnabled else {
            intakeWatcher = nil
            return
        }

        intakeWatcher = AirDropScreenshotWatcher(
            watchDownloads: airDropEnabled,
            watchScreenshots: screenshotEnabled,
            onAirDrop: { [weak self] url in
                MainActor.assumeIsolated {
                    self?.model.addToShelf([url], isAirDrop: true)
                }
            },
            onScreenshot: { [weak self] url in
                MainActor.assumeIsolated {
                    self?.model.show(.screenshot(title: url.lastPathComponent))
                    self?.model.addToShelf([url], isAirDrop: false)
                }
            }
        )
    }

    // MARK: Focus

    private func tickFocus() {
        let plainTimer = model.focus.isPlainTimer
        guard let finished = model.focus.tick() else { return }
        if plainTimer {
            model.show(.focusFinished("Time's up."))
            onTimerFinished()
        } else {
            model.show(.focusFinished(finished == .focus ? "Focus done. Take a break." : "Break over. Back to it."))
        }
    }
}

