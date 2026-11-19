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
            // Google Slides in Chrome: say so plainly instead of "nothing open".
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
}
