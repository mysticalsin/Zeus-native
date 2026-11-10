import EventKit
import AppKit
import AudioToolbox
import CoreAudio
import ZeusCore

/// Carries out a `FastIntent` at once: NSWorkspace for apps and links, media keys, Core Audio for
/// the volume, the to-do list (same path as `zeus todo add`, so it lands in the second brain),
/// the notch timer, the lock screen and Spotify. "Classifier picks, code decides facts, then
/// deterministic execution": `resolve` checks the facts (is the app installed, is it running,
/// is the name ambiguous) before anything runs, and asks or hands on instead of guessing.
@MainActor
final class FastActions {
    static let shared = FastActions()

    weak var topBar: TopBarModel?
    var acks: AckLines = .persona
    /// A launch that fails after the ack has already been said.
    var onLateProblem: ((String) -> Void)?
    let apps: AppIndex

    init(apps: AppIndex = .shared) { self.apps = apps }

    struct Plan {
        let intent: FastIntent
        /// For the notch badge and the CLI ("Open Spotify").
        let summary: String
        let ack: String?
        /// Starts the action, calls `started` the moment it is under way, and returns a problem to say, if any.
        let run: @MainActor (_ started: @escaping @MainActor () -> Void) async -> String?
    }

    enum Resolution {
        case plan(Plan)
        /// Not sure enough to act: ask this instead.
        case ask(String)
        /// Not ours: let the next stage (engine, then the LLM) take it.
        case pass
    }

    func resolve(_ intent: FastIntent) -> Resolution {
        switch intent {
        case .openApp(let name, let website):
            switch apps.lookup(name) {
            case .app(let entry):
                return .plan(openApp(entry, intent: intent))
            case .ambiguous(let a, let b):
                return .ask("Did you mean \(a.name) or \(b.name)?")
            case .none:
                guard let website else { return .pass }
                return .plan(openURL(website, intent: intent))
            }
        case .quitApp(let name), .hideApp(let name):
            let hide: Bool = if case .hideApp = intent { true } else { false }
            guard let app = AppIndex.running(name) else {
                // Installed but not running: say so. Unknown name: not ours.
                if case .app(let entry) = apps.lookup(name) {
                    return .plan(Plan(intent: intent, summary: "\(entry.name) isn't open", ack: acks.line(.notRunning(entry.name))) { started in
                        started(); return nil
                    })
                }
                return .pass
            }
            let display = app.localizedName ?? name
            return .plan(Plan(intent: intent, summary: (hide ? "Hide " : "Quit ") + display,
                              ack: acks.line(hide ? .hiding(display) : .quitting(display))) { started in
                // A polite quit: an app with unsaved work shows its own save sheet. Never forced.
                let ok = hide ? app.hide() : app.terminate()
                started()
                return ok ? nil : AckLines.clamp("\(display) didn't respond.")
            })
        case .playOnSpotify(let query):
            guard SpotifyPlayer.isInstalled else {
                return .plan(Plan(intent: intent, summary: "Spotify isn't installed", ack: acks.line(.notInstalled("Spotify"))) { started in
                    started(); return nil
                })
            }
            return .plan(query.isEmpty ? resumeSpotify(intent) : playOnSpotify(query, intent: intent))
        case .media(let command):
            if command == .play {
                let choice = MediaPlayPolicy.choose(hasSession: topBar?.nowPlaying != nil, spotifyInstalled: SpotifyPlayer.isInstalled)
                if choice == .resumeSpotify { return .plan(resumeSpotify(intent)) }
            }
            return .plan(media(command, intent: intent))
        case .volume(let change):
            return .plan(volume(change, intent: intent))
        case .addTodos(let items):
            return .plan(addTodos(items, intent: intent))
        case .addEvent(let text):
            return addEvent(text, intent: intent)
        case .openURL(let url):
            return .plan(openURL(url, intent: intent))
        case .lockScreen:
            return .plan(Plan(intent: intent, summary: "Lock screen", ack: acks.line(.locking)) { started in
                let ok = ScreenLock.lock()
                started()
                return ok ? nil : AckLines.clamp("I couldn't lock the screen.")
            })
        case .openTerminal, .openProject, .codeAgent, .research:
            return resolveCode(intent)
        case .beamer(let command):
            return resolveBeamer(command, intent: intent)
        case .polyglot(let start):
            let polyglot = PolyglotController.shared
            guard polyglot.settings.enabled else {
                return .plan(Plan(intent: intent, summary: "Polyglot is off", ack: nil) { started in
                    started(); return "Polyglot is turned off in Settings."
                })
            }
            return .plan(Plan(intent: intent, summary: start ? "Start Polyglot" : "Stop Polyglot", ack: acks.line(.polyglot(start: start))) { started in
                if start {
                    polyglot.start()
                    self.topBar?.selectedTab = .polyglot
                } else {
                    polyglot.stop()
                }
                started()
                return nil
            })
        case .timer(let seconds):
            guard let topBar else { return .pass }
            return .plan(Plan(intent: intent, summary: "Timer \(AckLines.spoken(seconds))", ack: acks.line(.timer(seconds: seconds))) { started in
                topBar.focus.startTimer(seconds: TimeInterval(seconds))
                started()
                return nil
            })
        case .cancelTimer:
            guard let topBar else { return .pass }
            return .plan(Plan(intent: intent, summary: "Cancel timer", ack: acks.line(.timerCancelled)) { started in
                guard topBar.focus.phase != .idle else {
                    started()
                    return AckLines.clamp("No timer is running.")
                }
                topBar.focus.stop()
                started()
                return nil
            })
        }
    }

    // MARK: Terminals, projects and research

    /// The project an utterance names, checked against the index. Unknown: not ours, so the LLM
    /// (which sees the whole sentence) takes it. Two close matches: ask.
    private enum Pick {
        case found(ProjectEntry)
        case other(Resolution)
    }

    private func project(_ name: String) -> Pick {
        switch ProjectScanner.shared.lookup(name) {
        case .project(let entry): .found(entry)
        case .ambiguous(let a, let b): .other(.ask("Did you mean \(a.name) or \(b.name)?"))
        case .none: .other(.pass)
        }
    }

    private func resolveCode(_ intent: FastIntent) -> Resolution {
        let code = CodeActions.shared
        switch intent {
        case .openTerminal(let name):
            var entry: ProjectEntry?
            if let name {
                switch project(name) {
                case .found(let found): entry = found
                case .other(let resolution): return resolution
                }
            }
            return .plan(Plan(intent: intent, summary: "Terminal" + (entry.map { ": \($0.name)" } ?? ""),
                              ack: acks.line(.terminal(project: entry?.name))) { started in
                started()
                let result = await code.openTerminal(project: entry?.path, dir: nil)
                return result.ok ? nil : result.message
            })
        case .openProject(let name, let target):
            switch project(name) {
            case .other(let resolution): return resolution
            case .found(let entry):
                return .plan(Plan(intent: intent, summary: "\(entry.name) in \(target.rawValue)",
                                  ack: acks.line(.project(entry.name, target))) { started in
                    started()
                    return await Self.open(entry, in: target)
                })
            }
        case .codeAgent(let tool, let name, let task):
            var entry: ProjectEntry?
            if let name {
                switch project(name) {
                case .found(let found): entry = found
                case .other(let resolution): return resolution
                }
            }
            let chosen = tool ?? CodingTool.preferred()
            return .plan(Plan(intent: intent, summary: "\(chosen.title): \(task.prefix(40))",
                              ack: acks.line(.agent(chosen, project: entry?.name))) { started in
                started()
                let result = await code.startAgent(tool: chosen, project: entry?.path, dir: nil, task: task)
                return result.ok ? nil : result.message
            })
        case .research(let topic, let deep):
            return .plan(Plan(intent: intent, summary: "Research: \(topic.prefix(40))", ack: acks.line(.research(topic, deep: deep))) { started in
                started()
                // The report takes a while: it runs on its own, with its notch card and its own spoken answer.
                guard !ResearchRunner.shared.isRunning else { return "I'm already researching something. Stop it first." }
                Task { @MainActor in _ = await ResearchRunner.shared.start(question: topic, depth: deep ? .deep : .quick, speak: true) }
                return nil
            })
        default:
            return .pass
        }
    }

    /// "Open <project> in …": an editor, Xcode (its project or package when it has one), Finder or a terminal.
    private static func open(_ entry: ProjectEntry, in target: FastIntent.ProjectApp) async -> String? {
        let folder = URL(fileURLWithPath: entry.path, isDirectory: true)
        let workspace = NSWorkspace.shared
        func open(_ url: URL, bundleID: String, name: String) async -> String? {
            guard let app = workspace.urlForApplication(withBundleIdentifier: bundleID) else { return "\(name) isn't installed." }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            return await withCheckedContinuation { continuation in
                workspace.open([url], withApplicationAt: app, configuration: configuration) { _, error in
                    continuation.resume(returning: error.flatMap { _ in AckLines.clamp("\(name) didn't open \(entry.name).") })
                }
            }
        }
        switch target {
        case .vscode: return await open(folder, bundleID: "com.microsoft.VSCode", name: "VS Code")
        case .cursor: return await open(folder, bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor")
        case .xcode:
            let names = (try? FileManager.default.contentsOfDirectory(atPath: entry.path)) ?? []
            let pick = names.first { $0.hasSuffix(".xcworkspace") } ?? names.first { $0.hasSuffix(".xcodeproj") }
                ?? (names.contains("Package.swift") ? "Package.swift" : nil)
            return await open(pick.map { folder.appendingPathComponent($0) } ?? folder, bundleID: "com.apple.dt.Xcode", name: "Xcode")
        case .finder:
            workspace.activateFileViewerSelecting([folder])
            return nil
        case .terminal:
            let result = await CodeActions.shared.openTerminal(project: entry.path, dir: nil)
            return result.ok ? nil : result.message
        }
    }

    // MARK: Apps and links

    private func openApp(_ entry: AppEntry, intent: FastIntent) -> Plan {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleID).first
        return Plan(intent: intent, summary: (running == nil ? "Open " : "Switch to ") + entry.name,
                    ack: acks.line(running == nil ? .opening(entry.name) : .switching(entry.name))) { started in
            if let running, !running.isTerminated {
                running.unhide()
                running.activate(options: [.activateAllWindows])
                // An app with no window open (closed with the red button) shows a new one on reopen.
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) != nil {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: entry.path), configuration: configuration) { _, _ in }
                }
                started()
                return nil
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let url = entry.path.isEmpty ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) : URL(fileURLWithPath: entry.path)
            guard let url else { started(); return "\(entry.name) isn't installed." }
            started()
            let name = entry.name
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
                if error != nil {
                    Task { @MainActor in self?.onLateProblem?("\(name) didn't open.") }
                }
            }
            return nil
        }
    }

    private func openURL(_ url: URL, intent: FastIntent) -> Plan {
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        return Plan(intent: intent, summary: "Open \(host)", ack: acks.line(.openingSite(host))) { started in
            let ok = NSWorkspace.shared.open(url)
            started()
            return ok ? nil : AckLines.clamp("I couldn't open \(host).")
        }
    }

    // MARK: Spotify

    private func playOnSpotify(_ query: String, intent: FastIntent) -> Plan {
        Plan(intent: intent, summary: "Spotify: \(query)", ack: acks.line(.searchingSpotify(query))) { [weak self] started in
            let outcome = await SpotifyPlayer.play(query, started: started) { [weak self] in
                guard let playing = self?.topBar?.nowPlaying, playing.player == .spotify else { return nil }
                return playing.isPlaying
            }
            switch outcome {
            case .accessibility, .appleScript: return nil
            case .notInstalled: return "Spotify isn't installed."
            case .shownOnly: return AckLines.clamp("Spotify is showing \(query), but I couldn't press play.")
            }
        }
    }

    private func resumeSpotify(_ intent: FastIntent) -> Plan {
        Plan(intent: intent, summary: "Play Spotify", ack: acks.line(.resumingSpotify)) { [weak self] started in
            let id = SpotifyPlayer.bundleID
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                running.activate()
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                    if error != nil {
                        Task { @MainActor in self?.onLateProblem?("Spotify didn't open.") }
                    }
                }
            }
            // The ack is not waiting on launch. Playback continues after the turn returns.
            started()
            Task { @MainActor in
                if Automation.allowed(id) {
                    _ = await SpotifyPlayer.osascript("tell application id \"\(id)\" to play")
                } else {
                    MediaKeys.post(.play)
                }
            }
            return nil
        }
    }

    // MARK: Media and volume

    private func media(_ command: FastIntent.Media, intent: FastIntent) -> Plan {
        let summary = switch command {
        case .play: "Play"
        case .pause: "Pause"
        case .toggle: "Play/Pause"
        case .next: "Next track"
        case .previous: "Previous track"
        }
        return Plan(intent: intent, summary: summary, ack: acks.line(.media(command))) { [weak self] started in
            // The media keys reach whatever is playing (Spotify, Music, a browser tab) with no
            // Automation prompt. Play and pause share one key, so skip it when the state already fits.
            let playing = self?.topBar?.nowPlaying?.isPlaying
            switch command {
            case .play where playing == true, .pause where playing == false:
                break
            case .play, .pause, .toggle:
                MediaKeys.post(.play)
            case .next:
                MediaKeys.post(.next)
            case .previous:
                MediaKeys.post(.previous)
            }
            started()
            return nil
        }
    }

    private func volume(_ change: FastIntent.Volume, intent: FastIntent) -> Plan {
        let summary = switch change {
        case .up: "Volume up"
        case .down: "Volume down"
        case .mute: "Mute"
        case .unmute: "Unmute"
        case .set(let value): "Volume \(value)%"
        }
        return Plan(intent: intent, summary: summary, ack: acks.line(.volume(change))) { started in
            // The top bar's Core Audio listener shows the volume cue on its own.
            let ok = SystemVolume.apply(change)
            started()
            return ok ? nil : "This output doesn't let me change its volume."
        }
    }

    // MARK: Calendar events

    private func addEvent(_ text: String, intent: FastIntent) -> Resolution {
        guard let topBar, let parsed = CalendarQuickAdd.parse(text), parsed.hadDate else { return .pass }
        // Ack up front only when Calendar access is already granted; otherwise the outcome (access
        // asked, refused, or added) is reported after the attempt, never "Added" and "I need access" together.
        let granted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        return .plan(Plan(intent: intent, summary: "Event: \(parsed.title)", ack: granted ? acks.line(.eventAdded(parsed.title)) : nil) { started in
            // Calendar access is asked for here, the first time an event is made (a system sheet); then the cyan ribbon lights.
            let problem = await topBar.addEvent(from: text)
            started()
            if problem == nil { ZeusSound.play(.todo) }
            return problem
        })
    }

    // MARK: To-dos

    private func addTodos(_ items: [String], intent: FastIntent) -> Plan {
        let titles = items.map { TodoQuickAdd.parse($0).title }
        return Plan(intent: intent, summary: titles.count == 1 ? "To-do: \(titles[0])" : "\(titles.count) to-dos",
                    ack: acks.line(.added(titles))) { started in
            // The same path as `zeus todo add`: todos.json plus the connected second-brain note.
            let added = items.compactMap { TodoController.shared.add($0) }
            started()
            if !added.isEmpty { ZeusSound.play(.todo) }
            return added.isEmpty ? AckLines.clamp("I couldn't add that to-do.") : nil
        }
    }
}

// MARK: - System helpers

/// Hardware media keys (play/pause, next, previous) posted as system-defined events.
enum MediaKeys {
    enum Key: Int { case play = 16, next = 17, previous = 18 }

    static func post(_ key: Key) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (key.rawValue << 16) | ((down ? 0xA : 0xB) << 8)
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                           windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

/// The default output device's volume and mute through Core Audio.
enum SystemVolume {
    static let step: Float32 = 1.0 / 16

    static func apply(_ change: FastIntent.Volume) -> Bool {
        guard let device = defaultOutput() else { return false }
        switch change {
        case .mute: return setMute(true, device)
        case .unmute: return setMute(false, device)
        case .set(let percent):
            _ = setMute(false, device)
            return setVolume(Float32(percent) / 100, device)
        case .up, .down:
            guard let current = volume(device) else { return false }
            _ = setMute(false, device)
            return setVolume(min(max(current + (change == .up ? step : -step), 0), 1), device)
        }
    }

    static func defaultOutput() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func volume(_ device: AudioObjectID) -> Float32? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func setVolume(_ value: Float32, _ device: AudioObjectID) -> Bool {
        var value = value
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                 mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    static func setMute(_ muted: Bool, _ device: AudioObjectID) -> Bool {
        var value: UInt32 = muted ? 1 : 0
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}

/// Locks the screen at once, like Control-Command-Q. Uses the login framework's
/// `SACLockScreenImmediate` when present, else posts the shortcut.
enum ScreenLock {
    private typealias Lock = @convention(c) () -> Int32
    private static let lockFunction: Lock? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(symbol, to: Lock.self)
    }()

    static func lock() -> Bool {
        if let lockFunction { return lockFunction() == 0 }
        guard AXIsProcessTrusted() else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let q: CGKeyCode = 12
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: q, keyDown: down)
            event?.flags = [.maskControl, .maskCommand]
            event?.post(tap: .cghidEventTap)
        }
        return true
    }
}
