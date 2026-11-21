import AppKit
import ZeusCore

/// Runs AppleScript through `/usr/bin/osascript`, so it can run off the main thread and a slow
/// app never freezes ZEUS. Only used after `Automation.gate` said ZEUS is allowed.
struct OsascriptRunner: AppleScriptRunner {
    func run(_ source: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PresenterNotesError.unreadable(message.isEmpty ? "the app did not answer" : message)
        }
        // osascript ends its result with a newline.
        var text = String(decoding: data, as: UTF8.self)
        if text.hasSuffix("\n") { text.removeLast() }
        return text
    }
}

/// Reads entries of a .pptx (a zip) with the system unzip, offline.
enum PPTXArchive {
    static func list(_ file: String) -> [String] {
        String(decoding: run(["-Z1", file]) ?? Data(), as: UTF8.self).split(separator: "\n").map(String.init)
    }

    static func read(_ file: String, _ entry: String) -> Data? {
        run(["-p", file, entry]).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func run(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}

/// Speaker notes from the open presentation, the slide on screen, and moving the slides along
/// with your voice. Never raises a permission prompt: Automation is asked for in setup or Settings.
@MainActor
final class PresenterNotesController {
    static let keynote = "com.apple.iWork.Keynote"
    static let powerPoint = "com.microsoft.Powerpoint"
    static let chrome = "com.google.Chrome"

    private(set) var deck: PresenterDeck?
    private var provider: PresenterNotesProvider?
    private var running: (app: PresenterDeck.App, bundleID: String, name: String)?
    private var advancer = SlideAdvancer(current: nil)
    /// A status poll in flight, so a slow app never piles requests up.
    private var polling = false
    /// Move to the next slide when you finish reading a slide's notes.
    var advanceSlides = UserDefaults.standard.object(forKey: "prompter.advanceSlides") as? Bool ?? true
    /// A problem to show in the teleprompter (a failed slide change).
    var onProblem: (String) -> Void = { _ in }
    /// In-browser notes for the existing bar. Never written into `deck`.
    private(set) var deckNotes = DeckNotesReader()
    private var deckNotesWatch: Task<Void, Never>?
    private var screenShareDetected = false
    private var recordingDetected = false
    /// The stored recording flag. A same-named parameter must not hide it.
    var notedRecording: Bool { recordingDetected }
    private var barExcludedForNotes = false

    /// The running presentation app, Keynote first.
    static func runningApp() -> (app: PresenterDeck.App, bundleID: String, name: String)? {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: keynote).isEmpty { return (.keynote, keynote, "Keynote") }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: powerPoint).isEmpty { return (.powerPoint, powerPoint, "PowerPoint") }
        return nil
    }

    static func provider(for app: PresenterDeck.App) -> PresenterNotesProvider {
        switch app {
        case .keynote: KeynoteNotesProvider(runner: OsascriptRunner())
        case .powerPoint: PowerPointNotesProvider(runner: OsascriptRunner(), listEntries: PPTXArchive.list, readEntry: PPTXArchive.read)
        case .googleSlides: GoogleSlidesNotesProvider()
        }
    }

    /// Checks permission without asking, then reads the notes off the main thread. Errors are
    /// `PresenterNotesError`s, ready for `PresenterEmptyState.from`.
    func load() async throws -> PresenterDeck {
        guard let running = Self.runningApp() else {
            // The person asked, and no presentation app is running. Notes stay out of the floating script.
            await readDeckNotes()
            if UserDefaults.standard.bool(forKey: PrompterHub.followKey) {
                await followDeckNotes()
            }
            if await Self.googleSlidesOpen() { throw PresenterNotesError.googleSlidesNotYet }
            throw PresenterNotesError.noApp
        }
        switch Automation.gate(running.bundleID) {
        case .granted: break
        case .appNotRunning: throw PresenterNotesError.noApp
        case .denied, .notAsked: throw PresenterNotesError.automationNotAllowed(running.name)
        }
        let provider = Self.provider(for: running.app)
        let name = running.name
        let deck: PresenterDeck
        do {
            deck = try await Task.detached(priority: .userInitiated) { try provider.load() }.value
        } catch PresenterNotesError.unreadable(let message) {
            throw PresenterNotesError.fromScriptFailure(message, app: name)
        }
        self.provider = provider
        self.running = running
        self.deck = deck
        advancer = SlideAdvancer(current: deck.current ?? 1)
        return deck
    }

    /// One cheap look at the slideshow (playing, slide on screen) off the main thread. Nil
    /// result: no presentation open. Throws `.noApp` once the app quit. Returns `.skipped` while
    /// the previous poll is still out.
    enum Poll { case status(SlideshowStatus?), skipped }

    func poll() async throws -> Poll {
        guard let provider, let running else { throw PresenterNotesError.noApp }
        guard !polling else { return .skipped }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: running.bundleID).isEmpty else { throw PresenterNotesError.noApp }
        polling = true
        defer { polling = false }
        let name = running.name
        do {
            return .status(try await Task.detached(priority: .userInitiated) { try provider.status() }.value)
        } catch PresenterNotesError.unreadable(let message) {
            throw PresenterNotesError.fromScriptFailure(message, app: name)
        }
    }

    /// The slideshow moved by itself (clicker, arrows): voice advance counts from there.
    func shown(slide: Int) { advancer.sync(to: slide) }

    func replace(deck: PresenterDeck) { self.deck = deck }

    func clear() {
        deck = nil
        provider = nil
        running = nil
        advancer = SlideAdvancer(current: nil)
    }

    /// The active Chrome tab is a Google Slides deck (asked only when notes are loaded, never polled).
    static func googleSlidesOpen() async -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: chrome).isEmpty,
              let tab = await ChromeBridge.activeTab(timeout: 1) else { return false }
        return GoogleSlidesNotesProvider.isPresentation(url: tab.url)
    }

    /// Called as voice-follow moves, with the word index in the whole deck. One slide forward
    /// at a time, confirmed by the app; a failure is reported and retried on the next word.
    func heard(wordIndex: Int, enabled: Bool? = nil) {
        guard enabled ?? advanceSlides, let deck, let provider, advancer.next(forWord: wordIndex, in: deck) != nil else { return }
        if let running = Self.runningApp(), Automation.gate(running.bundleID) != .granted {
            advancer.failed()
            onProblem(AutomationGate.message(Automation.gate(running.bundleID), app: running.name) ?? "")
            return
        }
        let script = provider.nextSlideScript
        Task {
            let ok = await Task.detached(priority: .userInitiated) { (try? OsascriptRunner().run(script)) != nil }.value
            if ok {
                advancer.confirm()
            } else {
                advancer.failed()
                onProblem("The slide did not change. Zeus will try again as you keep reading.")
            }
        }
    }

    /// The person asked for the notes of the deck in the browser. A running presentation app keeps the desktop path, and the notes are not copied into the floating script.
    func readDeckNotes() async {
        guard DeckNotesSelector.sendsBrowserRead(presentationAppRunning: Self.runningApp() != nil, personAsked: true) else { return }
        await drive(.read)
    }

    func followDeckNotes() async {
        guard Self.runningApp() == nil else { return }
        await drive(.follow)
    }

    func stopDeckNotes() async { await drive(.stop) }

    func clearDeckNotes() async { await drive(.clear) }

    func dismissDeckNotes() async { await drive(.dismiss) }

    /// Stores a reported share or recording. Exclusion does not wait for this: notes that are up keep the bar at `.none`.
    func noteScreenCapture(shareDetected: Bool, recordingDetected: Bool) {
        screenShareDetected = shareDetected
        self.recordingDetected = recordingDetected
        applyBarCapture()
    }

    private func drive(_ event: DeckNotesEvent) async {
        await driveEffects(deckNotes.send(event))
        applyBarCapture()
    }

    private func driveEffects(_ initial: [DeckNotesEffect]) async {
        var effects = initial
        var steps = 0
        while !effects.isEmpty, steps < 8 {
            steps += 1
            effects = await perform(effects)
        }
    }

    private func perform(_ effects: [DeckNotesEffect]) async -> [DeckNotesEffect] {
        var next: [DeckNotesEffect] = []
        for effect in effects {
            switch effect {
            case .findDeck:
                next += deckNotes.send(await findEvent())
            case .readNotes(let target):
                next += deckNotes.send(await notesEvent(target))
            case .watchIndex(let target):
                startWatch(target)
            case .cancelWatch:
                deckNotesWatch?.cancel()
                deckNotesWatch = nil
            }
        }
        return next
    }

    private func findEvent() async -> DeckNotesEvent {
        switch await ChromeBridge.callOutcome("page.context", timeout: 3) {
        case .notConnected: return .bridgeDown(.socketGone)
        case .timedOut: return .bridgeDown(.noReply)
        case .failed: return .bridgeDown(.socketGone)
        case .ok(let value):
            guard let value, let probe = DeckNotesBridgeMap.tab(from: value) else { return .noMatch }
            if probe.isPrivate != false { return .activePrivate }
            guard DeckNotesURL.isDeck(probe.url) else { return .noMatch }
            return .matched(DeckNotesTarget(tabID: probe.tabID, documentID: probe.documentID, url: probe.url))
        }
    }

    private func notesEvent(_ target: DeckNotesTarget) async -> DeckNotesEvent {
        let params = deckParams(target)
        switch await ChromeBridge.callOutcome("deck.notes", params, timeout: 8) {
        case .notConnected: return .bridgeDown(.socketGone)
        case .timedOut: return .bridgeDown(.noReply)
        case .failed(let error):
            if error.code == "stale_target" || error.code == "stale_document" {
                return .payload(.stale(id: target.documentID))
            }
            return .payload(.document(id: target.documentID, fields: nil))
        case .ok(let value):
            guard let value, case .object(var object) = value else {
                return .payload(.document(id: target.documentID, fields: nil))
            }
            if object["stale"]?.boolValue == true { return .payload(.stale(id: target.documentID)) }
            let documentID = object["documentId"]?.stringValue
            object["documentId"] = nil
            object["stale"] = nil
            if let documentID, documentID != target.documentID {
                return .payload(.document(id: documentID, fields: nil))
            }
            return .payload(.document(id: target.documentID, fields: DeckNotesParser.parse(object: object)))
        }
    }

    private func startWatch(_ target: DeckNotesTarget) {
        deckNotesWatch?.cancel()
        let interval = DeckNotesFollow.interval
        deckNotesWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled, self.deckNotes.watchRunning else { return }
                let event = await self.indexEvent(target)
                guard !Task.isCancelled, self.deckNotes.watchRunning else { return }
                await self.driveEffects(self.deckNotes.send(event))
                self.applyBarCapture()
                if !self.deckNotes.watchRunning { return }
            }
        }
    }

    /// Re-checks the tab before any script. A failed check does not call `deck.index`.
    private func indexEvent(_ target: DeckNotesTarget) async -> DeckNotesEvent {
        switch await ChromeBridge.callOutcome("page.context", timeout: 3) {
        case .notConnected: return .bridgeDown(.socketGone)
        case .timedOut: return .bridgeDown(.noReply)
        case .failed: return .bridgeDown(.socketGone)
        case .ok(let value):
            guard let value, let probe = DeckNotesBridgeMap.tab(from: value) else {
                return .index(DeckNotesIndex(slide: 1, count: 1, url: "", isPrivate: false, documentID: ""))
            }
            if probe.isPrivate != false || !DeckNotesURL.isDeck(probe.url) || probe.documentID != target.documentID {
                return .index(DeckNotesIndex(
                    slide: 1, count: 1, url: probe.url, isPrivate: probe.isPrivate, documentID: probe.documentID
                ))
            }
            switch await ChromeBridge.callOutcome("deck.index", deckParams(target), timeout: 3) {
            case .notConnected: return .bridgeDown(.socketGone)
            case .timedOut: return .bridgeDown(.noReply)
            case .failed(let error):
                if error.code == "stale_target" || error.code == "stale_document" {
                    return .index(DeckNotesIndex(slide: 1, count: 1, url: "", isPrivate: false, documentID: probe.documentID))
                }
                return .index(DeckNotesIndex(slide: 0, count: 1, url: probe.url, isPrivate: false, documentID: probe.documentID))
            case .ok(let reply):
                guard let reply, let parsed = DeckNotesBridgeMap.index(from: reply) else {
                    return .index(DeckNotesIndex(slide: 0, count: 1, url: probe.url, isPrivate: false, documentID: probe.documentID))
                }
                return .index(DeckNotesIndex(
                    slide: parsed.slide, count: parsed.count, url: probe.url, isPrivate: false, documentID: probe.documentID
                ))
            }
        }
    }

    private func deckParams(_ target: DeckNotesTarget) -> [String: JSONValue] {
        [
            "tabId": .number(Double(target.tabID)),
            "documentId": .string(target.documentID),
            "url": .string(target.url),
        ]
    }

    /// Reads the share setting. It does not write it, and it does not write Reduce Motion.
    private func applyBarCapture() {
        let show = ZeusScreenSharePolicy.showInScreenSharing(from: .standard)
        let notesVisible: Bool
        switch deckNotes.state {
        case .showing, .following: notesVisible = true
        default: notesVisible = false
        }
        DeckNotesCaptureHold.setNotesAreUp(notesVisible)
        let decision = DeckNotesCapturePolicy.barSharing(
            notesVisible: notesVisible,
            screenShareDetected: screenShareDetected,
            recordingDetected: recordingDetected,
            showInScreenSharing: show
        )
        switch decision {
        case .none:
            NotchControllerBridge.applyScreenSharePolicy(visibleInShare: false)
            barExcludedForNotes = true
        case .unchanged:
            guard barExcludedForNotes else { return }
            let visible = ZeusScreenSharePolicy.zeusSurfacesVisible(
                showInScreenSharing: show,
                meetingActive: MeetingState.active,
                teleprompterSessionHidden: false
            )
            NotchControllerBridge.applyScreenSharePolicy(visibleInShare: visible)
            barExcludedForNotes = false
        }
    }
}
