import Foundation

/// One slide's speaker notes.
public struct SlideNotes: Equatable, Sendable {
    public var number: Int
    public var title: String
    public var notes: String

    public init(number: Int, title: String = "", notes: String) {
        self.number = number
        self.title = title
        self.notes = notes
    }
}

/// The open presentation: its slides' notes and the slide on screen.
public struct PresenterDeck: Equatable, Sendable {
    public enum App: String, Sendable {
        case keynote, powerPoint, googleSlides

        public var title: String {
            switch self {
            case .keynote: "Keynote"
            case .powerPoint: "PowerPoint"
            case .googleSlides: "Google Slides"
            }
        }
    }

    public var app: App
    public var name: String
    public var slides: [SlideNotes]
    public var current: Int?

    public init(app: App, name: String, slides: [SlideNotes], current: Int? = nil) {
        self.app = app
        self.name = name
        self.slides = slides
        self.current = current
    }

    /// The teleprompter script: a cue per slide (`# 3 · Roadmap`), then its notes. Slides
    /// without notes keep their cue so the slide count stays in step.
    public var script: String {
        slides.map { slide in
            let title = slide.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cue = "# \(slide.number)" + (title.isEmpty ? "" : " · \(title.replacingOccurrences(of: "\n", with: " "))")
            let notes = slide.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return notes.isEmpty ? cue : cue + "\n" + notes
        }.joined(separator: "\n\n")
    }

    public var slideCount: Int { slides.count }

    /// Whether any slide has speaker notes.
    public var hasNotes: Bool {
        slides.contains { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public func slide(_ number: Int) -> SlideNotes? { slides.first { $0.number == number } }

    /// The slide after `number` in show order, nil on the last one.
    public func slide(after number: Int) -> SlideNotes? { slides.first { $0.number > number } }

    /// One slide's notes as a prompter script. No cue line: the prompter shows the slide
    /// number and the next slide's title above the text instead.
    public func script(forSlide number: Int) -> String {
        slide(number)?.notes.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// "Slide 7/24".
    public func position(ofSlide number: Int) -> String { "Slide \(number)/\(max(slideCount, number))" }

    /// The small cue for what comes next: "Next: Roadmap", "Next: slide 8", or "Last slide".
    public func nextCue(after number: Int) -> String {
        guard let next = slide(after: number) else { return "Last slide" }
        let title = next.title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Next: slide \(next.number)" : "Next: \(title)"
    }

    /// Whether a document name the app reports is this deck. Apps report "Talk.pptx" or
    /// "Talk.key" where the deck may be named "Talk".
    public func isSameDocument(_ name: String) -> Bool {
        Self.baseName(name) == Self.baseName(self.name)
    }

    static func baseName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for ext in [".key", ".pptx", ".pptm", ".ppt", ".ppsx", ".pps", ".potx"] where lower.hasSuffix(ext) {
            return String(trimmed.dropLast(ext.count))
        }
        return trimmed
    }

    /// The slide a spoken word belongs to, counting words the same way `ScriptFollower` does.
    public func slide(forWord index: Int) -> Int? {
        var start = 0
        for slide in slides {
            let count = ScriptFollower.normalize(slide.notes).count
            if index < start + count { return slide.number }
            start += count
        }
        return slides.last?.number
    }

    /// Where the next slide's words begin; nil on the last slide.
    public func firstWord(ofSlide number: Int) -> Int? {
        var start = 0
        for slide in slides {
            if slide.number == number { return start }
            start += ScriptFollower.normalize(slide.notes).count
        }
        return nil
    }
}

/// Moves the slides along with voice-follow, only forward, one slide per step, and only
/// marks a slide shown once the app confirmed it. A failed advance is retried on the next word.
public struct SlideAdvancer: Equatable, Sendable {
    /// The furthest slide shown so far.
    public private(set) var shown: Int?
    /// A request in flight, so words heard meanwhile don't send a second one.
    public private(set) var pending: Int?
    public private(set) var failures = 0

    public init(current: Int?) { shown = current }

    /// The slide to show now, if the reader moved past the shown one.
    public mutating func next(forWord index: Int, in deck: PresenterDeck) -> Int? {
        guard pending == nil, let slide = deck.slide(forWord: index), let shown, slide > shown else { return nil }
        let target = shown + 1
        pending = target
        return target
    }

    public mutating func confirm() {
        if let pending { shown = max(shown ?? pending, pending) }
        pending = nil
        failures = 0
    }

    public mutating func failed() {
        pending = nil
        failures += 1
    }

    /// The slideshow moved by itself (a clicker, the arrow keys): that slide is now the one
    /// shown, forwards or back, and a request in flight is forgotten.
    public mutating func sync(to slide: Int) {
        shown = slide
        pending = nil
    }
}

/// Whether ZEUS may script a presentation app. It never asks macOS mid-use: permission is
/// requested in setup or Settings › Permissions, and loading notes only checks it.
public enum AutomationGate {
    public enum Status: Equatable, Sendable { case granted, denied, notAsked, appNotRunning }

    public static func message(_ status: Status, app: String) -> String? {
        switch status {
        case .granted: nil
        case .appNotRunning: "Open your presentation in \(app) first."
        case .notAsked, .denied: "Allow Zeus to control \(app) in Settings > Permissions > Automation, then try again."
        }
    }
}

/// Runs an AppleScript and returns its text result. Injected so tests never talk to an app.
public protocol AppleScriptRunner: Sendable {
    func run(_ source: String) throws -> String
}

public protocol PresenterNotesProvider: Sendable {
    var app: PresenterDeck.App { get }
    func load() throws -> PresenterDeck
    /// Cheap check of the slideshow: is it playing, and which slide is on screen. Nil when no
    /// presentation is open. Polled while you present, so it never reads the notes.
    func status() throws -> SlideshowStatus?
    /// The script that shows the next slide.
    var nextSlideScript: String { get }
}

public enum PresenterNotesError: LocalizedError, Equatable {
    /// Neither Keynote nor PowerPoint is running.
    case noApp
    case noPresentation(String)
    case unreadable(String)
    /// macOS has not allowed ZEUS to script this app (Automation).
    case automationNotAllowed(String)
    /// A Google Slides deck is open in Chrome; reading its notes is not built yet.
    case googleSlidesNotYet

    public var errorDescription: String? {
        switch self {
        case .noApp: "Open your deck in Keynote or PowerPoint first."
        case .noPresentation(let app): "Open a presentation in \(app) first."
        case .unreadable(let detail): "Could not read the speaker notes: \(detail)"
        case .automationNotAllowed(let app): AutomationGate.message(.denied, app: app)
        case .googleSlidesNotYet: "Google Slides notes: not yet. Open the deck in Keynote or PowerPoint."
        }
    }
}

/// Field and record separators that never appear in notes (ASCII unit / record separators).
enum Separators {
    static let unit = "\u{1F}"
    static let record = "\u{1E}"
}

/// Keynote through AppleScript: number, title and presenter notes of every slide, plus the
/// current slide.
public struct KeynoteNotesProvider: PresenterNotesProvider {
    public let app = PresenterDeck.App.keynote
    let runner: AppleScriptRunner

    public init(runner: AppleScriptRunner) { self.runner = runner }

    public static let loadScript = """
    set US to (ASCII character 31)
    set RS to (ASCII character 30)
    tell application "Keynote"
        if (count of documents) is 0 then return ""
        set doc to front document
        set out to (name of doc) & RS
        try
            set out to out & (slide number of current slide of doc)
        end try
        repeat with s in slides of doc
            set t to ""
            try
                set t to object text of default title item of s
            end try
            set out to out & RS & (slide number of s) & US & t & US & (presenter notes of s)
        end repeat
        return out
    end tell
    """

    /// `playing US slide US count US name`, or "" with no document. Two-second timeout so a
    /// busy Keynote never stalls the poll.
    public static let statusScript = """
    set US to (ASCII character 31)
    tell application "Keynote"
        with timeout of 2 seconds
            if (count of documents) is 0 then return ""
            set doc to front document
            set n to ""
            try
                set n to (slide number of current slide of doc) as text
            end try
            return ((playing) as text) & US & n & US & ((count of slides of doc) as text) & US & (name of doc)
        end timeout
    end tell
    """

    public var nextSlideScript: String { #"tell application "Keynote" to show next"# }

    public func load() throws -> PresenterDeck {
        try Self.parse(runner.run(Self.loadScript))
    }

    public func status() throws -> SlideshowStatus? {
        SlideshowStatus.parse(try runner.run(Self.statusScript))
    }

    /// `name RS current RS n US title US notes RS …`
    public static func parse(_ output: String) throws -> PresenterDeck {
        let records = output.components(separatedBy: Separators.record)
        guard records.count >= 2, !records[0].isEmpty else { throw PresenterNotesError.noPresentation("Keynote") }
        let slides = records.dropFirst(2).compactMap { record -> SlideNotes? in
            let fields = record.components(separatedBy: Separators.unit)
            guard fields.count >= 3, let number = Int(fields[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            return SlideNotes(number: number, title: fields[1], notes: fields[2...].joined(separator: Separators.unit))
        }
        return PresenterDeck(app: .keynote, name: records[0], slides: slides,
                             current: Int(records[1].trimmingCharacters(in: .whitespaces)))
    }
}

/// PowerPoint: AppleScript gives the file and the slide on screen; the notes come from the
/// .pptx itself (`ppt/notesSlides/*.xml`), read offline. A deck that isn't a local .pptx (never
/// saved, or open from the cloud) falls back to asking PowerPoint for each slide's notes.
public struct PowerPointNotesProvider: PresenterNotesProvider {
    public let app = PresenterDeck.App.powerPoint
    let runner: AppleScriptRunner
    /// Reads one entry of the .pptx zip (the app uses `unzip -p`); injected for tests.
    let readEntry: @Sendable (_ file: String, _ entry: String) -> Data?
    /// Lists the zip's entries; injected for tests.
    let listEntries: @Sendable (_ file: String) -> [String]

    public init(runner: AppleScriptRunner, listEntries: @escaping @Sendable (String) -> [String],
                readEntry: @escaping @Sendable (String, String) -> Data?) {
        self.runner = runner
        self.listEntries = listEntries
        self.readEntry = readEntry
    }

    /// `path RS slide`. While a slideshow runs, its presentation and the slide it shows win
    /// over the active window.
    public static let locateScript = """
    set RS to (ASCII character 30)
    tell application "Microsoft PowerPoint"
        with timeout of 5 seconds
            if (count of presentations) is 0 then return ""
            set p to active presentation
            set n to ""
            if (count of slide show windows) > 0 then
                try
                    set p to presentation of slide show window 1
                end try
                try
                    set n to (slide index of slide of slide show view of slide show window 1) as text
                on error
                    try
                        set n to (current show position of slide show view of slide show window 1) as text
                    end try
                end try
            else
                try
                    set n to (slide index of slide range of selection of document window 1) as text
                end try
            end if
            return (full name of p) & RS & n
        end timeout
    end tell
    """

    /// `playing US slide US count US name`, or "" with no presentation.
    public static let statusScript = """
    set US to (ASCII character 31)
    tell application "Microsoft PowerPoint"
        with timeout of 2 seconds
            if (count of presentations) is 0 then return ""
            set p to active presentation
            set showing to "false"
            set n to ""
            if (count of slide show windows) > 0 then
                set showing to "true"
                try
                    set p to presentation of slide show window 1
                end try
                try
                    set n to (slide index of slide of slide show view of slide show window 1) as text
                on error
                    try
                        set n to (current show position of slide show view of slide show window 1) as text
                    end try
                end try
            else
                try
                    set n to (slide index of slide range of selection of document window 1) as text
                end try
            end if
            set c to ""
            try
                set c to (count of slides of p) as text
            end try
            return showing & US & n & US & c & US & (name of p)
        end timeout
    end tell
    """

    /// Fallback when the file can't be read: the notes placeholder of each slide, in the same
    /// `name RS current RS n US title US notes` shape as Keynote.
    public static let notesScript = """
    set US to (ASCII character 31)
    set RS to (ASCII character 30)
    tell application "Microsoft PowerPoint"
        with timeout of 20 seconds
            if (count of presentations) is 0 then return ""
            set p to active presentation
            if (count of slide show windows) > 0 then
                try
                    set p to presentation of slide show window 1
                end try
            end if
            set out to (name of p) & RS
            repeat with i from 1 to (count of slides of p)
                set t to ""
                try
                    set t to content of text range of text frame of place holder 1 of slide i of p
                end try
                set nt to ""
                try
                    set nt to content of text range of text frame of place holder 2 of notes page of slide i of p
                end try
                set out to out & RS & i & US & t & US & nt
            end repeat
            return out
        end timeout
    end tell
    """

    public var nextSlideScript: String {
        #"tell application "Microsoft PowerPoint" to go to next slide slide show view of slide show window 1"#
    }

    public func load() throws -> PresenterDeck {
        let output = try runner.run(Self.locateScript)
        let parts = output.components(separatedBy: Separators.record)
        guard let path = parts.first, !path.isEmpty else { throw PresenterNotesError.noPresentation("PowerPoint") }
        let current = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
        var deck: PresenterDeck
        if path.hasPrefix("/"), let fromFile = try? Self.deck(fromPPTX: path, listEntries: listEntries, readEntry: readEntry) {
            deck = fromFile
        } else {
            deck = try Self.parseNotes(runner.run(Self.notesScript))
        }
        deck.current = current
        return deck
    }

    public func status() throws -> SlideshowStatus? {
        SlideshowStatus.parse(try runner.run(Self.statusScript))
    }

    /// Output of `notesScript` (no current slide in it; `load` adds it).
    public static func parseNotes(_ output: String) throws -> PresenterDeck {
        let records = output.components(separatedBy: Separators.record)
        guard records.count >= 1, !records[0].isEmpty else { throw PresenterNotesError.noPresentation("PowerPoint") }
        let slides = records.dropFirst(2).compactMap { record -> SlideNotes? in
            let fields = record.components(separatedBy: Separators.unit)
            guard fields.count >= 3, let number = Int(fields[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            return SlideNotes(number: number, title: fields[1], notes: fields[2...].joined(separator: Separators.unit))
        }
        return PresenterDeck(app: .powerPoint, name: PresenterDeck.baseName(records[0]), slides: slides)
    }

    /// Reads every notes slide and its relationship file to know which slide it belongs to.
    /// Slides are numbered in show order (`ppt/presentation.xml`), which is not always the
    /// order of the `slideN.xml` files once slides have been moved around.
    public static func deck(fromPPTX path: String, listEntries: (String) -> [String], readEntry: (String, String) -> Data?) throws -> PresenterDeck {
        let entries = listEntries(path)
        guard !entries.isEmpty else { throw PresenterNotesError.unreadable("\(URL(fileURLWithPath: path).lastPathComponent) is not a .pptx file") }
        let fileNumbers = entries.compactMap { PPTXNotes.fileNumber($0, folder: "ppt/slides/slide") }.sorted()
        let order = PPTXNotes.slideOrder(
            presentation: readEntry(path, "ppt/presentation.xml") ?? Data(),
            relationships: readEntry(path, "ppt/_rels/presentation.xml.rels") ?? Data()
        ).filter(fileNumbers.contains)
        // Files missing from presentation.xml (or no presentation.xml) go last, by file number.
        let shown = order + fileNumbers.filter { !order.contains($0) }
        var position: [Int: Int] = [:]
        for (index, file) in shown.enumerated() { position[file] = index + 1 }

        var notes: [Int: String] = [:]
        for entry in entries {
            guard let file = PPTXNotes.fileNumber(entry, folder: "ppt/notesSlides/notesSlide"), let xml = readEntry(path, entry) else { continue }
            let rels = readEntry(path, "ppt/notesSlides/_rels/notesSlide\(file).xml.rels")
            let slideFile = rels.flatMap(PPTXNotes.slideNumber(fromRelationships:)) ?? file
            let number = position[slideFile] ?? slideFile
            notes[number] = PPTXNotes.notesText(fromXML: xml)
        }
        var slides: [SlideNotes] = shown.enumerated().map { index, file in
            let title = readEntry(path, "ppt/slides/slide\(file).xml").map(PPTXNotes.titleText(fromXML:)) ?? ""
            return SlideNotes(number: index + 1, title: title, notes: notes[index + 1] ?? "")
        }
        // Notes whose slide is gone from the file list still show, so nothing is lost.
        for (number, text) in notes where !slides.contains(where: { $0.number == number }) {
            slides.append(SlideNotes(number: number, notes: text))
        }
        return PresenterDeck(app: .powerPoint, name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                             slides: slides.sorted { $0.number < $1.number })
    }
}

/// The bits of Office Open XML needed for speaker notes.
public enum PPTXNotes {
    /// Text of the notes body placeholder (`<p:ph type="body"/>`): one line per paragraph,
    /// leaving out the slide image and slide number placeholders.
    public static func notesText(fromXML data: Data) -> String {
        paragraphs(in: data, placeholders: ["body"]).joined(separator: "\n")
    }

    /// A slide's title (`title` or `ctrTitle` placeholder) on one line.
    public static func titleText(fromXML data: Data) -> String {
        paragraphs(in: data, placeholders: ["title", "ctrTitle"]).joined(separator: " ")
    }

    private static func paragraphs(in data: Data, placeholders: Set<String>) -> [String] {
        let parser = XMLParser(data: data)
        let delegate = NotesDelegate(placeholders: placeholders)
        parser.delegate = delegate
        parser.parse()
        return delegate.paragraphs.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// `ppt/slides/slide12.xml` → 12 for folder `ppt/slides/slide`.
    static func fileNumber(_ entry: String, folder: String) -> Int? {
        guard entry.hasPrefix(folder), entry.hasSuffix(".xml") else { return nil }
        return Int(entry.dropFirst(folder.count).dropLast(4))
    }

    /// Slide file numbers in show order: `<p:sldId r:id="rId7"/>` in presentation.xml, each
    /// id resolved through presentation.xml.rels to `slides/slideN.xml`.
    public static func slideOrder(presentation: Data, relationships: Data) -> [Int] {
        let rels = String(decoding: relationships, as: UTF8.self)
        var target: [String: Int] = [:]
        for element in matches(#"<Relationship\b[^>]*>"#, in: rels) {
            guard let id = firstGroup(#"\sId="([^"]+)""#, in: element),
                  let path = firstGroup(#"Target="([^"]+)""#, in: element),
                  let number = firstGroup(#"slides/slide(\d+)\.xml$"#, in: path).flatMap(Int.init) else { continue }
            target[id] = number
        }
        let presentationText = String(decoding: presentation, as: UTF8.self)
        guard let list = firstGroup(#"<(?:\w+:)?sldIdLst>([\s\S]*?)</(?:\w+:)?sldIdLst>"#, in: presentationText) else { return [] }
        return matches(#"<(?:\w+:)?sldId\b[^>]*>"#, in: list).compactMap { element in
            firstGroup(#"\w+:id="([^"]+)""#, in: element).flatMap { target[$0] }
        }
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// The slide a notes page belongs to, from its relationships (`../slides/slide7.xml` → 7).
    public static func slideNumber(fromRelationships data: Data) -> Int? {
        let text = String(decoding: data, as: UTF8.self)
        guard let range = text.range(of: #"slides/slide(\d+)\.xml"#, options: .regularExpression) else { return nil }
        let digits = text[range].filter(\.isNumber)
        return Int(digits)
    }

    private final class NotesDelegate: NSObject, XMLParserDelegate {
        let placeholders: Set<String>
        var paragraphs: [String] = []
        private var shapeIsBody = false
        private var inShape = false
        private var inText = false
        private var current = ""

        init(placeholders: Set<String>) { self.placeholders = placeholders }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch local(name) {
            case "sp": inShape = true; shapeIsBody = false
            case "ph" where inShape: shapeIsBody = attributes["type"].map(placeholders.contains) ?? false
            case "p" where shapeIsBody: current = ""
            case "t" where shapeIsBody: inText = true
            case "br" where shapeIsBody: current += " "
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { current += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch local(name) {
            case "t": inText = false
            case "p" where shapeIsBody: paragraphs.append(current)
            case "sp": inShape = false; shapeIsBody = false
            default: break
            }
        }

        private func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }
    }
}
