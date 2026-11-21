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
    /// What the notch shows from Music, Spotify and later sources, and where a music command goes.
    let nowPlayingHub: NowPlayingHub
    private let musicFeed: MusicPlayerFeed
    private let browserFeed: BrowserMediaFeed
    /// A voice timer ran out (the voice says so; the notch cue and sound play either way).
    var onTimerFinished: () -> Void = {}
    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []
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
    /// The single sleep that asks the Shift gate whether the hold has lasted long enough.
    private var shiftCheck: Task<Void, Never>?
    private var rainGate = RainAlertGate()
    private var hudMonitor: SystemHUDMonitor?
    private var intakeWatcher: AirDropScreenshotWatcher?
    private(set) var flingService: FlingService?
    private var flingPrompts: FlingPromptPanelController?
    private var flingPapers: FlingPaperController?
    /// Whether the notch is open. Fling reads it only when background receiving is off.
    var notchIsOpen: @MainActor () -> Bool = { true }

    init(model: TopBarModel) {
        self.model = model
        nowPlayingHub = NowPlayingHub(model: model, ports: NowPlayingHub.livePorts(model: model))
        musicFeed = MusicPlayerFeed(hub: nowPlayingHub, model: model)
        browserFeed = BrowserMediaFeed(hub: nowPlayingHub, model: model)
    }

    func start() {
        nowPlayingHub.attach()
        model.chooseOutputDevice = { [weak self] in self?.showOutputDevices() }
        model.requestCalendarAccess = { [weak self] in self?.requestCalendar() }
        model.refreshWeather = { [weak self] in self?.fetchWeather(force: true) }
        model.fetchEvents = { [weak self] start, end in self?.events(from: start, to: end) ?? [] }
        model.createEvent = { [weak self] parsed in await self?.saveEvent(parsed) ?? .failed("Calendar isn't available.") }

        musicFeed.start()
        browserFeed.start()
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
        updateFlingService()
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

    /// Removes the music observers, stops pending music reads and takes the players and tabs off the notch.
    func stop() {
        browserFeed.stop()
        musicFeed.stop()
    }

    private func every(_ seconds: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in MainActor.assumeIsolated { body() } }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
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
                self.performShift(ShiftPeekPolicy.otherKey(&self.shiftGate))
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
        let effects: [ShiftPeekPolicy.Effect]
        if down {
            effects = ShiftPeekPolicy.shiftDown(&shiftGate, at: Date())
        } else {
            let revealed = shiftGate.release()
            effects = ShiftPeekPolicy.shiftedUp(revealed: revealed)
        }
        performShift(effects)
    }

    private func performShift(_ effects: [ShiftPeekPolicy.Effect]) {
        for effect in effects {
            switch effect {
            case .scheduleCheck:
                shiftCheck?.cancel()
                shiftCheck = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(ShiftPeekPolicy.checkAfter))
                    guard let self, !Task.isCancelled else { return }
                    self.performShift(ShiftPeekPolicy.checkDue(&self.shiftGate, at: Date()))
                }
            case .cancelPending:
                shiftCheck?.cancel()
                shiftCheck = nil
            case .showCrest:
                model.flash(.shiftCrest)
            case .fadeExistingCrest:
                break
            }
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

    // MARK: Fling

    /// Builds Fling once and lets Settings drive it. Nothing listens until `fling.enabled` is on.
    func updateFlingService() {
        if flingService == nil {
            let service = FlingService(model: model, transport: FlingService.liveEndpoint())
            service.notchIsOpen = { [weak self] in self?.notchIsOpen() ?? true }
            model.shelfPersistence = FlingShelfPersistence(url: FlingService.supportDirectory.appendingPathComponent("Shelf/shelf.json"))
            model.loadPersistedShelf()
            model.fling = service
            flingService = service
            FlingService.current = service
            flingPrompts = FlingPromptPanelController(fling: service)
            let papers = FlingPaperController()
            flingPapers = papers
            service.presentPapers = { [weak papers] urls, peer in papers?.show(urls: urls, from: peer) }
            service.observeSettings()
        }
        flingService?.reconfigure()
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

