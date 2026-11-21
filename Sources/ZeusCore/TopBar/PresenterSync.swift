import CoreGraphics
import Foundation

// Following a live slideshow with the floating prompter: which slide is on screen, what to
// show for it, when to ask the app again, and where the prompter sits. Kept free of AppKit
// so every rule here is tested without Keynote or PowerPoint.

/// One cheap look at the presentation app: is a slideshow playing, and which slide is up.
public struct SlideshowStatus: Equatable, Sendable {
    public var document: String
    public var playing: Bool
    public var slide: Int?
    public var slideCount: Int?

    public init(document: String, playing: Bool, slide: Int?, slideCount: Int? = nil) {
        self.document = document
        self.playing = playing
        self.slide = slide
        self.slideCount = slideCount
    }

    /// `playing US slide US count US name`. Nil when the app has no presentation open ("").
    public static func parse(_ output: String) -> SlideshowStatus? {
        let fields = output.trimmingCharacters(in: .newlines).components(separatedBy: Separators.unit)
        guard fields.count >= 4 else { return nil }
        let number = { (text: String) in Int(text.trimmingCharacters(in: .whitespaces)) }
        return SlideshowStatus(document: fields[3...].joined(separator: Separators.unit),
                               playing: fields[0].trimmingCharacters(in: .whitespaces).lowercased() == "true",
                               slide: number(fields[1]).flatMap { $0 > 0 ? $0 : nil },
                               slideCount: number(fields[2]))
    }
}

/// Keeps the prompter on the slide the audience sees. Feed it each poll; it says what changed.
public struct SlideSync: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        /// The slideshow moved to this slide (forwards or back): show its notes from the top.
        case jump(Int)
        /// A different deck, or slides were added or removed: read the notes again.
        case reload
        case started
        case ended
        /// The presentation was closed.
        case closed
    }

    public private(set) var deck: PresenterDeck
    public private(set) var slide: Int
    public private(set) var playing: Bool
    /// Slide count the app last reported, so a stale file doesn't reload on every poll.
    private var seenCount: Int?

    public init(deck: PresenterDeck, playing: Bool = false) {
        self.deck = deck
        slide = deck.current ?? deck.slides.first?.number ?? 1
        self.playing = playing
        seenCount = deck.slideCount
    }

    public mutating func update(_ status: SlideshowStatus?) -> [Change] {
        guard let status else { return [.closed] }
        guard deck.isSameDocument(status.document) else { return [.reload] }
        if let count = status.slideCount, count != seenCount {
            seenCount = count
            if count != deck.slideCount { return [.reload] }
        }
        var changes: [Change] = []
        if status.playing != playing {
            playing = status.playing
            changes.append(playing ? .started : .ended)
        }
        if let shown = status.slide, shown != slide {
            slide = shown
            changes.append(.jump(shown))
        }
        return changes
    }

    /// Notes were read again (after `.reload`): keep the slide the app reports. The count the
    /// app reported stays, so a file saved before slides were added reloads once, not forever.
    public mutating func replace(deck: PresenterDeck) {
        self.deck = deck
        if let current = deck.current { slide = current }
    }
}

/// What the prompter shows for one slide.
public struct PresenterPage: Equatable, Sendable {
    public var slide: Int
    /// "Slide 7/24".
    public var position: String
    /// "Next: Roadmap", "Next: slide 8" or "Last slide".
    public var next: String
    public var script: PrompterScript
    /// Set when there is nothing to read on this slide.
    public var empty: PresenterEmptyState?

    public init(deck: PresenterDeck, slide: Int) {
        self.slide = slide
        position = deck.position(ofSlide: slide)
        next = deck.nextCue(after: slide)
        script = PrompterScript(deck.script(forSlide: slide))
        empty = PresenterEmptyState.forSlide(slide, in: deck)
    }

    /// A new follower for this slide's words, and the roll back at the top. A roll that was
    /// running keeps running (no countdown); a paused one stays paused.
    public func begin(roll: inout PrompterRoll, at now: Date = Date()) -> ScriptFollower {
        roll.restartSection(at: now)
        return ScriptFollower(script: script)
    }
}

/// Why the prompter has nothing to read, each with a one-line fix.
public enum PresenterEmptyState: Equatable, Sendable {
    case noApp
    case noPresentation(app: String)
    case noNotesInDeck(name: String)
    case noNotesOnSlide(Int)
    case automation(app: String)
    case googleSlides
    case failed(String)

    public var title: String {
        switch self {
        case .noApp: "No presentation open"
        case .noPresentation(let app): "No presentation open in \(app)"
        case .noNotesInDeck(let name): "No speaker notes in \(name)"
        case .noNotesOnSlide(let slide): "No notes on slide \(slide)"
        case .automation(let app): "Zeus can't read \(app) yet"
        case .googleSlides: "Google Slides notes: not yet"
        case .failed: "Couldn't read the speaker notes"
        }
    }

    /// The one-line fix.
    public var detail: String {
        switch self {
        case .noApp: "Open your deck in Keynote or PowerPoint and start the slideshow."
        case .noPresentation(let app): "Open your deck in \(app), then start the slideshow."
        case .noNotesInDeck: "Add speaker notes to your slides, save, then press Reload."
        case .noNotesOnSlide: "Keep presenting: the next slide's notes show when you move on."
        case .automation(let app): "Allow Zeus to control \(app) under Automation in Settings › Permissions."
        case .googleSlides: "Open the deck in Keynote or PowerPoint to read its notes here."
        case .failed(let detail): detail
        }
    }

    /// Shows the "Open Settings › Permissions" button.
    public var opensPermissions: Bool { if case .automation = self { true } else { false } }

    /// A slide without notes is a quiet note above the text; everything else fills the window.
    public var isBlocking: Bool { if case .noNotesOnSlide = self { false } else { true } }

    public static func from(_ error: Error) -> PresenterEmptyState {
        switch error as? PresenterNotesError {
        case .noApp: .noApp
        case .noPresentation(let app): .noPresentation(app: app)
        case .automationNotAllowed(let app): .automation(app: app)
        case .googleSlidesNotYet: .googleSlides
        case .unreadable(let detail): .failed(detail)
        case nil: .failed(error.localizedDescription)
        }
    }

    public static func forSlide(_ slide: Int, in deck: PresenterDeck) -> PresenterEmptyState? {
        guard deck.hasNotes else { return .noNotesInDeck(name: deck.name) }
        return deck.script(forSlide: slide).isEmpty ? .noNotesOnSlide(slide) : nil
    }
}

extension PresenterNotesError {
    /// osascript's error text → the error to show. -1743 is "not authorized to send Apple
    /// events", -1728 / -600 mean the app has nothing open or isn't running.
    public static func fromScriptFailure(_ message: String, app: String) -> PresenterNotesError {
        if message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized") { return .automationNotAllowed(app) }
        if message.contains("-600") { return .noPresentation(app) }
        return .unreadable(message.isEmpty ? "\(app) did not answer" : message)
    }
}

/// How often to ask the presentation app, so following a talk costs next to nothing.
public enum PresenterPolling {
    /// While a slideshow plays: a slide change shows within half a second.
    public static let presenting: TimeInterval = 0.5
    /// Following a deck that isn't playing (rehearsing in the editor).
    public static let editing: TimeInterval = 1.5

    public static func followInterval(playing: Bool) -> TimeInterval { playing ? presenting : editing }

    /// "Follow my presentation" watching for a slideshow to start. Nil: don't ask the app at
    /// all (it isn't running, or nothing suggests a slideshow), which keeps the idle cost at a
    /// window-list read.
    public static func watchInterval(appRunning: Bool, frontmost: Bool, fullScreenWindow: Bool) -> TimeInterval? {
        guard appRunning else { return nil }
        if fullScreenWindow { return 1 }
        return frontmost ? 3 : nil
    }

    /// A window of the app covering a whole display: a slideshow (or a deck in full screen).
    public static func hasFullScreenWindow(_ windows: [CGRect], screens: [CGRect]) -> Bool {
        windows.contains { window in
            screens.contains { screen in
                abs(window.width - screen.width) < 2 && abs(window.height - screen.height) < 2
            }
        }
    }
}

/// Google Slides runs in Chrome. The bridge can read the page's visible text, but the speaker
/// notes of every slide are not on the page during a slideshow, so this is a clear stub.
public struct GoogleSlidesNotesProvider: PresenterNotesProvider {
    public let app = PresenterDeck.App.googleSlides

    public init() {}

    public func load() throws -> PresenterDeck { throw PresenterNotesError.googleSlidesNotYet }
    public func status() throws -> SlideshowStatus? { nil }
    public var nextSlideScript: String { "" }

    /// The deck URL predicate. Visible page text is not a stand-in for speaker notes, and `load` still refuses to turn a browser deck into the floating script.
    public static func isPresentation(url: String) -> Bool {
        DeckNotesURL.isDeck(url)
    }
}

/// A display the prompter can sit on.
public struct PrompterDisplay: Equatable, Sendable {
    public var id: String
    public var name: String
    public var frame: CGRect
    /// Height of the notch or menu bar at the top, so the prompter sits just below it.
    public var topInset: Double
    /// The built-in display with the camera in its notch.
    public var hasCamera: Bool

    public init(id: String, name: String, frame: CGRect, topInset: Double, hasCamera: Bool) {
        self.id = id
        self.name = name
        self.frame = frame
        self.topInset = topInset
        self.hasCamera = hasCamera
    }
}

/// Where the prompter goes: near the camera by default, or on the display you picked.
public enum PrompterPlacement {
    /// The id stored for "next to the camera".
    public static let camera = "camera"

    public static func display(preferred: String?, among displays: [PrompterDisplay]) -> PrompterDisplay? {
        if let preferred, preferred != camera, let match = displays.first(where: { $0.id == preferred }) { return match }
        return displays.first(where: \.hasCamera) ?? displays.first
    }

    /// Centred at the top of the display, just under the notch or menu bar.
    public static func origin(for size: CGSize, on display: PrompterDisplay, gap: Double = 6) -> CGPoint {
        let top = display.frame.maxY - display.topInset - gap
        return CGPoint(x: display.frame.midX - size.width / 2, y: max(display.frame.minY, top - size.height))
    }

    /// Whether the window must move to reach the display (it stays where you dragged it on
    /// the right display).
    public static func needsMove(window: CGRect, to display: PrompterDisplay) -> Bool {
        !display.frame.contains(CGPoint(x: window.midX, y: window.midY))
    }
}

// MARK: In-browser deck notes

/// Which route may read speaker notes. Only the bundled extension is eligible, and this feature never raises a prompt.
public struct DeckNotesRoute: Equatable, Sendable {
    public enum Read: Equatable, Sendable {
        case yes, sometimes, poorly, pixels
    }

    public var rank: Int
    public var reads: Read
    /// What that route would ask the system for. This feature does not take it.
    public var newTCCPrompt: Bool
    public var eligible: Bool
    /// Always false: the reader does not raise a permission prompt.
    public var prompts: Bool

    public init(rank: Int, reads: Read, newTCCPrompt: Bool, eligible: Bool, prompts: Bool) {
        self.rank = rank
        self.reads = reads
        self.newTCCPrompt = newTCCPrompt
        self.eligible = eligible
        self.prompts = prompts
    }
}

public enum DeckNotesRoutes {
    public static let all: [DeckNotesRoute] = [
        DeckNotesRoute(rank: 1, reads: .yes, newTCCPrompt: false, eligible: true, prompts: false),
        DeckNotesRoute(rank: 2, reads: .sometimes, newTCCPrompt: false, eligible: false, prompts: false),
        DeckNotesRoute(rank: 3, reads: .poorly, newTCCPrompt: true, eligible: false, prompts: false),
        DeckNotesRoute(rank: 4, reads: .pixels, newTCCPrompt: true, eligible: false, prompts: false),
    ]

    public static let chosen = all[0]
}

/// Frame sizes already accepted by the host. This feature does not raise them.
public enum DeckNotesLimits {
    public static let notesCap = 8_000
    public static let hostToBrowser = NativeMessagingFrame.maxHostToChromeBytes
    public static let browserToHost = NativeMessagingFrame.maxChromeToHostBytes
}

/// The local socket stays mode 0600, and the host lists one extension origin.
public enum DeckNotesHost {
    public static let socketMode = 0o600

    public static func allowedOrigins(extensionID: String) -> [String] {
        let letters = Set("abcdefghijklmnopqrstuvwxyz")
        guard extensionID.count == 32, extensionID.allSatisfy({ letters.contains($0) }) else { return [] }
        return ["chrome-extension://\(extensionID)/"]
    }
}

/// Format characters, line and paragraph separators, and variation selectors leave the notes before they are held.
public enum DeckNotesText {
    public static func cleaned(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars where !strip(scalar) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func strip(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.generalCategory == .format { return true }
        let value = scalar.value
        if value == 0x2028 || value == 0x2029 { return true }
        if value >= 0xFE00 && value <= 0xFE0F { return true }
        if value >= 0xE0100 && value <= 0xE01EF { return true }
        return false
    }
}

/// `https`, exact host `docs.google.com`, path prefix `/presentation/`. The extension uses the same check before it runs a script.
public enum DeckNotesURL {
    public static func isDeck(_ url: String) -> Bool { matches(url) }

    public static func allowsExecuteScript(_ url: String) -> Bool { matches(url) }

    private static func matches(_ raw: String) -> Bool {
        guard DeckURL.isPresentation(raw) else { return false }
        if raw.unicodeScalars.contains(where: { $0.value < 0x20 || $0 == " " || $0 == "\u{7F}" }) {
            return false
        }
        guard let schemeSep = raw.range(of: "://") else { return false }
        let rest = raw[schemeSep.upperBound...]
        let authorityEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
        let authority = rest[..<authorityEnd]
        if authority.hasSuffix(".") || authority.contains("%") || authority.contains("\\") { return false }
        return true
    }
}

public struct DeckNotesTarget: Equatable, Sendable {
    public var tabID: Int
    public var documentID: String
    public var url: String

    public init(tabID: Int, documentID: String, url: String) {
        self.tabID = tabID
        self.documentID = documentID
        self.url = url
    }
}

public struct DeckNotesFields: Equatable, Sendable {
    public var title: String
    public var slide: Int
    public var count: Int
    public var notes: String
    public var notesInDocument: Bool
    public var truncated: Bool

    public init(title: String, slide: Int, count: Int, notes: String, notesInDocument: Bool, truncated: Bool) {
        self.title = title
        self.slide = slide
        self.count = count
        self.notes = notes
        self.notesInDocument = notesInDocument
        self.truncated = truncated
    }
}

public enum DeckNotesParser {
    public static func parse(_ data: Data) -> DeckNotesFields? {
        if data.count > DeckNotesLimits.browserToHost { return nil }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let object) = value else { return nil }
        return parse(object: object)
    }

    public static func parse(object: [String: JSONValue]) -> DeckNotesFields? {
        let allowed: Set<String> = ["title", "slide", "count", "notes", "notesInDocument"]
        guard Set(object.keys) == allowed else { return nil }
        guard case .string(let rawTitle)? = object["title"],
              case .string(let rawNotes)? = object["notes"],
              case .bool(let notesInDocument)? = object["notesInDocument"],
              case .number(let slideNumber)? = object["slide"],
              case .number(let countNumber)? = object["count"],
              let slide = whole(slideNumber),
              let count = whole(countNumber),
              count >= 1, slide >= 1, slide <= count else { return nil }
        let title = String(DeckNotesText.cleaned(rawTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(200))
        let notes = DeckNotesText.cleaned(rawNotes)
        let truncated = notes.count > DeckNotesLimits.notesCap
        let capped = truncated ? String(notes.prefix(DeckNotesLimits.notesCap)) : notes
        return DeckNotesFields(
            title: title, slide: slide, count: count, notes: capped,
            notesInDocument: notesInDocument, truncated: truncated
        )
    }

    public static func whole(_ number: Double) -> Int? {
        guard number.isFinite, number.rounded() == number,
              number >= Double(Int.min), number <= Double(Int.max) else { return nil }
        return Int(number)
    }
}

public struct DeckNotesTabProbe: Equatable, Sendable {
    public var tabID: Int
    public var documentID: String
    public var url: String
    /// Nil when the bridge did not say. Unknown is refused.
    public var isPrivate: Bool?

    public init(tabID: Int, documentID: String, url: String, isPrivate: Bool?) {
        self.tabID = tabID
        self.documentID = documentID
        self.url = url
        self.isPrivate = isPrivate
    }
}

public enum DeckNotesBridgeMap {
    public static func tab(from value: JSONValue) -> DeckNotesTabProbe? {
        guard case .object(let object) = value else { return nil }
        let nested = object["target"]
        let url = string(object["url"]) ?? string(nested?["url"])
        let tabID = integer(object["tabId"]) ?? integer(nested?["tabId"])
        let documentID = string(object["documentId"]) ?? string(nested?["documentId"])
        guard let url, !url.isEmpty, let tabID, tabID >= 0, let documentID, !documentID.isEmpty else { return nil }
        let flag = boolean(object["private"]) ?? boolean(nested?["private"])
            ?? boolean(object["incognito"]) ?? boolean(nested?["incognito"])
        return DeckNotesTabProbe(tabID: tabID, documentID: documentID, url: url, isPrivate: flag)
    }

    /// Transport keys are not speaker-note fields. Any other extra key stays, and the parser then fails closed.
    public static func fields(from value: JSONValue) -> DeckNotesFields? {
        guard case .object(var object) = value else { return nil }
        object["documentId"] = nil
        object["stale"] = nil
        return DeckNotesParser.parse(object: object)
    }

    public static func index(from value: JSONValue) -> (slide: Int, count: Int)? {
        guard case .object(let object) = value, Set(object.keys) == ["slide", "count"],
              case .number(let slideNumber)? = object["slide"],
              case .number(let countNumber)? = object["count"],
              let slide = DeckNotesParser.whole(slideNumber),
              let count = DeckNotesParser.whole(countNumber),
              count >= 1, slide >= 1, slide <= count else { return nil }
        return (slide, count)
    }

    private static func string(_ value: JSONValue?) -> String? {
        if case .string(let text)? = value, !text.isEmpty { return text }
        return nil
    }

    private static func integer(_ value: JSONValue?) -> Int? {
        if case .number(let number)? = value { return DeckNotesParser.whole(number) }
        return nil
    }

    private static func boolean(_ value: JSONValue?) -> Bool? {
        if case .bool(let bit)? = value { return bit }
        return nil
    }
}

public enum DeckNotesFailure: Equatable, Sendable, CustomStringConvertible, CaseIterable {
    case extensionOff
    case noDeck
    case privateWindow
    case notesNotOnPage
    case deckChanged
    case unreadable
    case timedOut

    public static let all: [DeckNotesFailure] = allCases

    public var title: String {
        switch self {
        case .extensionOff: "The browser extension is off"
        case .noDeck: "No slide deck in the browser"
        case .privateWindow: "Private window"
        case .notesNotOnPage: "Notes are not on this page"
        case .deckChanged: "The deck changed"
        case .unreadable: "Could not read the speaker notes"
        case .timedOut: "The browser did not answer"
        }
    }

    public var line: String {
        switch self {
        case .extensionOff: "Turn on the Zeus extension in the browser, then press Read."
        case .noDeck: "Open the deck in the browser, then press Read."
        case .privateWindow: "Zeus does not read a private window."
        case .notesNotOnPage: "Open the speaker notes in the browser, then press Read."
        case .deckChanged: "Press Read to load the slide in front."
        case .unreadable, .timedOut: "Press Read to try again."
        }
    }

    public var description: String {
        switch self {
        case .extensionOff: "extensionOff"
        case .noDeck: "noDeck"
        case .privateWindow: "privateWindow"
        case .notesNotOnPage: "notesNotOnPage"
        case .deckChanged: "deckChanged"
        case .unreadable: "unreadable"
        case .timedOut: "timedOut"
        }
    }
}

public struct DeckNotesHeld: Equatable, Sendable {
    public var title: String
    public var slide: Int
    public var count: Int
    public var notes: String
    public var truncated: Bool
    public var target: DeckNotesTarget

    public init(title: String, slide: Int, count: Int, notes: String, truncated: Bool, target: DeckNotesTarget) {
        self.title = title
        self.slide = slide
        self.count = count
        self.notes = notes
        self.truncated = truncated
        self.target = target
    }
}

public enum DeckNotesState: Equatable, Sendable, CustomStringConvertible {
    case idle
    case checking
    case reading(DeckNotesTarget)
    case showing(DeckNotesHeld)
    case following(DeckNotesHeld, polls: Int, watching: Bool)
    case failed(DeckNotesFailure)

    public var description: String {
        switch self {
        case .idle: "idle"
        case .checking: "checking"
        case .reading: "reading"
        case .showing: "showing"
        case .following: "following"
        case .failed(let failure): "failed \(failure.description)"
        }
    }
}

public enum DeckNotesLink: Equatable, Sendable {
    case socketGone
    case noReply
}

public enum DeckNotesPayload: Equatable, Sendable {
    case document(id: String, fields: DeckNotesFields?)
    case stale(id: String)
}

public struct DeckNotesIndex: Equatable, Sendable {
    public var slide: Int
    public var count: Int
    public var url: String
    public var isPrivate: Bool?
    public var documentID: String

    public init(slide: Int, count: Int, url: String, isPrivate: Bool?, documentID: String) {
        self.slide = slide
        self.count = count
        self.url = url
        self.isPrivate = isPrivate
        self.documentID = documentID
    }
}

public enum DeckNotesEvent: Equatable, Sendable {
    case read
    case bridgeDown(DeckNotesLink)
    case activePrivate
    case noMatch
    case matched(DeckNotesTarget)
    case payload(DeckNotesPayload)
    case index(DeckNotesIndex)
    case follow
    case stop
    case clear
    case dismiss
}

public enum DeckNotesEffect: Equatable, Sendable {
    case findDeck
    case readNotes(DeckNotesTarget)
    case watchIndex(DeckNotesTarget)
    case cancelWatch
}

public enum DeckNotesFollow {
    public static let interval = PresenterPolling.presenting
    public static let maximumPolls = 120
}

/// Pure reader. The app performs the effects. Browser notes are not a floating script.
public struct DeckNotesReader: Equatable, Sendable {
    public private(set) var state: DeckNotesState
    /// Set when a follow poll asked for a new slide, so the notes return to the watch.
    private var resumePolls: Int?

    public init() { state = .idle }

    public var heldNotes: String {
        switch state {
        case .showing(let held), .following(let held, _, _): held.notes
        default: ""
        }
    }

    public var isHolding: Bool {
        switch state {
        case .showing, .following: true
        default: false
        }
    }

    public var watchRunning: Bool {
        if case .following(_, _, let watching) = state { return watching }
        return false
    }

    public mutating func send(_ event: DeckNotesEvent) -> [DeckNotesEffect] {
        switch event {
        case .read:
            switch state {
            case .idle, .failed:
                resumePolls = nil
                state = .checking
                return [.findDeck]
            case .showing:
                resumePolls = nil
                state = .checking
                return [.cancelWatch, .findDeck]
            case .checking, .reading, .following:
                return []
            }
        case .bridgeDown(let link):
            switch state {
            case .checking:
                state = .failed(.extensionOff)
                return []
            case .reading:
                let cancel = resumePolls == nil ? [] : [DeckNotesEffect.cancelWatch]
                resumePolls = nil
                state = .failed(link == .noReply ? .timedOut : .extensionOff)
                return cancel
            case .following:
                resumePolls = nil
                state = .failed(.extensionOff)
                return [.cancelWatch]
            case .idle, .showing, .failed:
                return []
            }
        case .activePrivate:
            guard case .checking = state else { return [] }
            state = .failed(.privateWindow)
            return []
        case .noMatch:
            guard case .checking = state else { return [] }
            state = .failed(.noDeck)
            return []
        case .matched(let target):
            guard case .checking = state else { return [] }
            guard DeckNotesURL.isDeck(target.url), !target.documentID.isEmpty else {
                state = .failed(.noDeck)
                return []
            }
            resumePolls = nil
            state = .reading(target)
            return [.readNotes(target)]
        case .payload(let payload):
            guard case .reading(let target) = state else { return [] }
            let resume = resumePolls
            resumePolls = nil
            switch payload {
            case .document(let id, _) where id != target.documentID:
                resumePolls = resume
                return []
            case .document(_, let fields):
                guard let fields else {
                    state = .failed(.unreadable)
                    return resume == nil ? [] : [.cancelWatch]
                }
                guard fields.notesInDocument else {
                    state = .failed(.notesNotOnPage)
                    return resume == nil ? [] : [.cancelWatch]
                }
                let held = DeckNotesHeld(
                    title: fields.title, slide: fields.slide, count: fields.count,
                    notes: fields.notes, truncated: fields.truncated, target: target
                )
                if let resume {
                    let stop = resume >= DeckNotesFollow.maximumPolls
                    state = .following(held, polls: resume, watching: !stop)
                    return stop ? [.cancelWatch] : []
                }
                state = .showing(held)
                return []
            case .stale(let id) where id == target.documentID:
                state = .failed(.deckChanged)
                return resume == nil ? [] : [.cancelWatch]
            case .stale:
                resumePolls = resume
                return []
            }
        case .index(let index):
            guard case .following(let held, let polls, true) = state else { return [] }
            if index.isPrivate != false {
                resumePolls = nil
                state = .failed(.privateWindow)
                return [.cancelWatch]
            }
            if !DeckNotesURL.isDeck(index.url) || index.documentID != held.target.documentID {
                resumePolls = nil
                state = .failed(.deckChanged)
                return [.cancelWatch]
            }
            let nextPolls = polls + 1
            let same = index.slide == held.slide && index.count == held.count
            if same {
                let stop = nextPolls >= DeckNotesFollow.maximumPolls
                state = .following(held, polls: nextPolls, watching: !stop)
                return stop ? [.cancelWatch] : []
            }
            guard index.slide >= 1, index.count >= 1, index.slide <= index.count else {
                resumePolls = nil
                state = .failed(.unreadable)
                return [.cancelWatch]
            }
            resumePolls = nextPolls
            state = .reading(held.target)
            return [.readNotes(held.target)]
        case .follow:
            guard case .showing(let held) = state else { return [] }
            resumePolls = nil
            state = .following(held, polls: 0, watching: true)
            return [.watchIndex(held.target)]
        case .stop:
            guard case .following(let held, _, _) = state else { return [] }
            resumePolls = nil
            state = .showing(held)
            return [.cancelWatch]
        case .clear, .dismiss:
            if case .idle = state { return [] }
            let cancel: [DeckNotesEffect]
            if case .following(_, _, true) = state {
                cancel = [.cancelWatch]
            } else if case .reading = state, resumePolls != nil {
                cancel = [.cancelWatch]
            } else {
                cancel = []
            }
            resumePolls = nil
            state = .idle
            return cancel
        }
    }
}

public enum DeckNotesSelector {
    /// The browser machine is sent `read` only when no presentation app is running and the person asked.
    public static func sendsBrowserRead(presentationAppRunning: Bool, personAsked: Bool) -> Bool {
        personAsked && !presentationAppRunning
    }
}

public enum DeckNotesCopy {
    public static let loading = "Reading speaker notes"
    public static let kicker = "Speaker notes"
    public static let truncated = "Truncated"
    public static let emptyDetail = "Read again when you move on."
    public static let footer = "On this Mac. Cleared when you leave."

    public static func emptyTitle(slide: Int) -> String { "No notes on slide \(slide)" }
    public static func position(slide: Int, count: Int) -> String { "\(slide) / \(count)" }
    public static func voiceOver(slide: Int, count: Int) -> String { "Speaker notes, slide \(slide) of \(count)" }
}

/// Notes stay plain text. A line that starts with a mark is not a script cue, and the floating script is left as it was.
public enum DeckNotesScriptGuard {
    public static func floatingScript(existing: String, notes: String) -> String {
        _ = notes
        return existing
    }
}

public struct DeckNotesPage: Equatable, Sendable {
    public var kicker: String
    public var position: String
    public var notes: String
    public var caption: String?
    public var captionDetail: String?
    public var failureTitle: String?
    public var failureLine: String?
    public var loadingLine: String?
    public var accessibilityLabel: String
    /// The notes body is not an accessibility value.
    public var accessibilityValue: String?
    public var notesAreAccessibilityValue: Bool

    public static func displayedNotes(_ notes: String) -> String { notes }

    public static func make(_ state: DeckNotesState) -> DeckNotesPage {
        switch state {
        case .showing(let held), .following(let held, _, _):
            let empty = held.notes.isEmpty
            return DeckNotesPage(
                kicker: DeckNotesCopy.kicker,
                position: DeckNotesCopy.position(slide: held.slide, count: held.count),
                notes: displayedNotes(held.notes),
                caption: held.truncated ? DeckNotesCopy.truncated : (empty ? DeckNotesCopy.emptyTitle(slide: held.slide) : nil),
                captionDetail: empty ? DeckNotesCopy.emptyDetail : nil,
                failureTitle: nil,
                failureLine: nil,
                loadingLine: nil,
                accessibilityLabel: DeckNotesCopy.voiceOver(slide: held.slide, count: held.count),
                accessibilityValue: nil,
                notesAreAccessibilityValue: false
            )
        case .failed(let failure):
            return DeckNotesPage(
                kicker: "",
                position: "",
                notes: "",
                caption: nil,
                captionDetail: nil,
                failureTitle: failure.title,
                failureLine: failure.line,
                loadingLine: nil,
                accessibilityLabel: failure.title,
                accessibilityValue: nil,
                notesAreAccessibilityValue: false
            )
        case .checking, .reading:
            return DeckNotesPage(
                kicker: "",
                position: "",
                notes: "",
                caption: nil,
                captionDetail: nil,
                failureTitle: nil,
                failureLine: nil,
                loadingLine: DeckNotesCopy.loading,
                accessibilityLabel: DeckNotesCopy.loading,
                accessibilityValue: nil,
                notesAreAccessibilityValue: false
            )
        case .idle:
            return DeckNotesPage(
                kicker: "",
                position: "",
                notes: "",
                caption: nil,
                captionDetail: nil,
                failureTitle: nil,
                failureLine: nil,
                loadingLine: nil,
                accessibilityLabel: "",
                accessibilityValue: nil,
                notesAreAccessibilityValue: false
            )
        }
    }
}

/// The flag is an input. Nothing here writes the Reduce Motion setting.
public struct DeckNotesMotion: Equatable, Sendable {
    public var replacesInPlace: Bool
    public var rolls: Bool
    public var crossfades: Bool
    public var buttonScales: Bool

    public static func presentation(reduceMotion: Bool) -> DeckNotesMotion {
        if reduceMotion {
            return DeckNotesMotion(replacesInPlace: true, rolls: false, crossfades: false, buttonScales: false)
        }
        return DeckNotesMotion(replacesInPlace: true, rolls: false, crossfades: false, buttonScales: false)
    }
}

/// Capture exclusion is per window. While notes are showing or following, the whole bar stays at `sharingType` `.none`. A share detector is not required.
public enum DeckNotesCapturePolicy {
    public enum Surface: Equatable, Sendable { case existingBar }
    public enum BarSharing: Equatable, Sendable {
        /// Leave the bar on the sharing type it already has.
        case unchanged
        /// `NSWindow.SharingType.none` for the whole bar window.
        case none
    }

    public static let notesSurface = Surface.existingBar
    public static let opensAnotherWindow = false
    public static let canHideOneViewInsideTheBar = false

    public static func barSharing(notesVisible: Bool, screenShareDetected: Bool, recordingDetected: Bool, showInScreenSharing: Bool) -> BarSharing {
        _ = (screenShareDetected, recordingDetected, showInScreenSharing)
        return notesVisible ? .none : .unchanged
    }

    /// Another refresh asked to show or hide the bar. Notes that are up keep the whole bar at `.none`.
    public static func sharingAfterRefresh(notesVisible: Bool, requestedVisibleInShare: Bool) -> BarSharing {
        _ = requestedVisibleInShare
        return notesVisible ? .none : .unchanged
    }
}

/// The bar window reads this when some other caller applies the share policy.
@MainActor
public enum DeckNotesCaptureHold {
    public private(set) static var notesAreUp = false

    public static func setNotesAreUp(_ up: Bool) { notesAreUp = up }
}
