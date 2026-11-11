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

    /// `https://docs.google.com/presentation/d/…` (editor, present or presenter view).
    public static func isPresentation(url: String) -> Bool {
        guard let components = URLComponents(string: url), let host = components.host?.lowercased() else { return false }
        return host == "docs.google.com" && components.path.hasPrefix("/presentation/")
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
