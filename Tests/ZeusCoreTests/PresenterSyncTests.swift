import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

/// Following a live slideshow, with fake providers: no Keynote, PowerPoint or Chrome is touched.
@Suite("Presenter sync")
struct PresenterSyncTests {
    let US = "\u{1F}", RS = "\u{1E}"

    struct FakeRunner: AppleScriptRunner {
        let output: String
        func run(_ source: String) throws -> String { output }
    }

    /// Answers each script by what it asks for, so one runner serves load and status.
    struct ScriptedRunner: AppleScriptRunner {
        let replies: [String: String]
        func run(_ source: String) throws -> String {
            for (needle, reply) in replies where source.contains(needle) { return reply }
            throw PresenterNotesError.unreadable("unexpected script")
        }
    }

    /// A presentation app that plays back a list of statuses, one per poll.
    final class FakeProvider: PresenterNotesProvider, @unchecked Sendable {
        let app = PresenterDeck.App.keynote
        let deck: PresenterDeck
        private var statuses: [SlideshowStatus?]
        private let lock = NSLock()
        init(deck: PresenterDeck, statuses: [SlideshowStatus?]) {
            self.deck = deck
            self.statuses = statuses
        }
        func load() throws -> PresenterDeck { deck }
        func status() throws -> SlideshowStatus? {
            lock.lock(); defer { lock.unlock() }
            return statuses.isEmpty ? nil : statuses.removeFirst()
        }
        var nextSlideScript: String { "" }
    }

    let deck = PresenterDeck(app: .keynote, name: "Launch.key", slides: [
        SlideNotes(number: 1, title: "Welcome", notes: "Hi everyone, thanks for coming."),
        SlideNotes(number: 2, title: "Roadmap", notes: "Three things this quarter.\n\nFirst, speed."),
        SlideNotes(number: 3, title: "", notes: ""),
        SlideNotes(number: 4, title: "Thanks", notes: "Questions?"),
    ], current: 1)

    // MARK: Deck parsing

    @Test func keynoteStatusParses() throws {
        let provider = KeynoteNotesProvider(runner: FakeRunner(output: "true\(US)7\(US)24\(US)Launch.key"))
        #expect(try provider.status() == SlideshowStatus(document: "Launch.key", playing: true, slide: 7, slideCount: 24))
        #expect(SlideshowStatus.parse("false\(US)\(US)3\(US)Draft") == SlideshowStatus(document: "Draft", playing: false, slide: nil, slideCount: 3))
        #expect(SlideshowStatus.parse("") == nil)
        #expect(SlideshowStatus.parse("true\(US)0\(US)3\(US)D")?.slide == nil)
        #expect(KeynoteNotesProvider.statusScript.contains("with timeout of 2 seconds"))
    }

    @Test func powerPointStatusParses() throws {
        let provider = PowerPointNotesProvider(runner: FakeRunner(output: "true\(US)2\(US)3\(US)Talk.pptx\n"),
                                               listEntries: { _ in [] }, readEntry: { _, _ in nil })
        let status = try #require(try provider.status())
        #expect(status.playing && status.slide == 2 && status.slideCount == 3 && status.document == "Talk.pptx")
    }

    @Test func powerPointSlidesFollowShowOrderAndKeepTitles() throws {
        // slide3.xml was moved to the front of the show.
        let presentation = #"<p:presentation xmlns:p="p" xmlns:r="r"><p:sldIdLst><p:sldId id="258" r:id="rId4"/><p:sldId id="256" r:id="rId2"/><p:sldId id="257" r:id="rId3"/></p:sldIdLst></p:presentation>"#
        let rels = #"<Relationships><Relationship Id="rId1" Type="master" Target="slideMasters/slideMaster1.xml"/><Relationship Target="slides/slide1.xml" Id="rId2" Type="slide"/><Relationship Id="rId3" Type="slide" Target="slides/slide2.xml"/><Relationship Id="rId4" Type="slide" Target="slides/slide3.xml"/></Relationships>"#
        func slide(_ title: String) -> String {
            #"<p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree><p:sp><p:nvSpPr><p:nvPr><p:ph type="ctrTitle"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>"# + title + #"</a:t></a:r></a:p></p:txBody></p:sp><p:sp><p:nvSpPr><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>Body text</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>"#
        }
        func notes(_ text: String) -> String {
            #"<p:notes xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree><p:sp><p:nvSpPr><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>"# + text + #"</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:notes>"#
        }
        let files: [String: String] = [
            "ppt/presentation.xml": presentation, "ppt/_rels/presentation.xml.rels": rels,
            "ppt/slides/slide1.xml": slide("Intro"), "ppt/slides/slide2.xml": slide("Plan"), "ppt/slides/slide3.xml": slide("Hook"),
            "ppt/notesSlides/notesSlide1.xml": notes("Open with the hook."),
            "ppt/notesSlides/_rels/notesSlide1.xml.rels": #"<R Target="../slides/slide3.xml"/>"#,
            "ppt/notesSlides/notesSlide2.xml": notes("Walk the plan."),
            "ppt/notesSlides/_rels/notesSlide2.xml.rels": #"<R Target="../slides/slide2.xml"/>"#,
        ]
        let deck = try PowerPointNotesProvider.deck(fromPPTX: "/x/Talk.pptx", listEntries: { _ in Array(files.keys) },
                                                    readEntry: { _, entry in files[entry].map { Data($0.utf8) } })
        #expect(deck.slides.map(\.title) == ["Hook", "Intro", "Plan"])
        #expect(deck.slides.map(\.notes) == ["Open with the hook.", "", "Walk the plan."])
        #expect(PPTXNotes.slideOrder(presentation: Data(presentation.utf8), relationships: Data(rels.utf8)) == [3, 1, 2])
        #expect(PPTXNotes.titleText(fromXML: Data(slide("A title").utf8)) == "A title")
    }

    @Test func powerPointWithoutAFileAsksTheApp() throws {
        // Never saved: PowerPoint reports a bare name, so the notes come from AppleScript.
        let runner = ScriptedRunner(replies: [
            "full name of p": "Presentation1\(RS)2",
            "notes page": "Presentation1\(RS)\(RS)1\(US)Hello\(US)First notes\(RS)2\(US)\(US)Second notes",
        ])
        let provider = PowerPointNotesProvider(runner: runner, listEntries: { _ in [] }, readEntry: { _, _ in nil })
        let deck = try provider.load()
        #expect(deck.name == "Presentation1" && deck.current == 2)
        #expect(deck.slides.map(\.notes) == ["First notes", "Second notes"])
        #expect(deck.slides[0].title == "Hello")
    }

    @Test func deckHelpers() {
        #expect(deck.position(ofSlide: 2) == "Slide 2/4")
        #expect(deck.nextCue(after: 1) == "Next: Roadmap")
        #expect(deck.nextCue(after: 2) == "Next: slide 3")
        #expect(deck.nextCue(after: 4) == "Last slide")
        #expect(deck.script(forSlide: 2) == "Three things this quarter.\n\nFirst, speed.")
        #expect(deck.script(forSlide: 9).isEmpty)
        #expect(deck.isSameDocument("Launch") && deck.isSameDocument("Launch.key") && !deck.isSameDocument("Other.key"))
        #expect(PresenterDeck(app: .powerPoint, name: "Talk", slides: []).isSameDocument("Talk.pptx"))
        #expect(deck.hasNotes && !PresenterDeck(app: .keynote, name: "d", slides: [SlideNotes(number: 1, notes: " ")]).hasNotes)
    }

    // MARK: Slide change → notes jump

    @Test func slideChangesJumpToThatSlidesNotes() {
        var sync = SlideSync(deck: deck)
        #expect(sync.slide == 1)
        #expect(sync.update(SlideshowStatus(document: "Launch.key", playing: true, slide: 1, slideCount: 4)) == [.started])
        #expect(sync.update(SlideshowStatus(document: "Launch.key", playing: true, slide: 2, slideCount: 4)) == [.jump(2)])
        #expect(sync.update(SlideshowStatus(document: "Launch.key", playing: true, slide: 2, slideCount: 4)) == [])
        // Back with the clicker.
        #expect(sync.update(SlideshowStatus(document: "Launch.key", playing: true, slide: 1, slideCount: 4)) == [.jump(1)])
        #expect(sync.update(SlideshowStatus(document: "Launch.key", playing: false, slide: 1, slideCount: 4)) == [.ended])
        #expect(sync.update(nil) == [.closed])
        #expect(sync.update(SlideshowStatus(document: "Other.key", playing: true, slide: 1, slideCount: 4)) == [.reload])
    }

    @Test func startingOnALaterSlideStartsAndJumps() {
        var sync = SlideSync(deck: deck)
        #expect(sync.update(SlideshowStatus(document: "Launch", playing: true, slide: 4, slideCount: 4)) == [.started, .jump(4)])
        #expect(sync.playing && sync.slide == 4)
    }

    @Test func addedSlidesReloadOnceEvenFromAStaleFile() {
        var sync = SlideSync(deck: deck)
        let five = SlideshowStatus(document: "Launch.key", playing: true, slide: 1, slideCount: 5)
        #expect(sync.update(five) == [.reload])
        // The file on disk still has 4 slides: no reload loop.
        sync.replace(deck: deck)
        #expect(sync.update(five) == [.started])
        #expect(sync.update(five) == [])
    }

    @Test func pageShowsTheSlideAndItsCue() {
        let page = PresenterPage(deck: deck, slide: 2)
        #expect(page.position == "Slide 2/4" && page.next == "Next: slide 3")
        #expect(page.script.blocks.map(\.text) == ["Three things this quarter.", "First, speed."])
        #expect(page.empty == nil)
        #expect(PresenterPage(deck: deck, slide: 3).empty == .noNotesOnSlide(3))
    }

    @Test func aFakeSlideshowDrivesTheNotes() throws {
        let provider = FakeProvider(deck: deck, statuses: [
            SlideshowStatus(document: "Launch.key", playing: true, slide: 1, slideCount: 4),
            SlideshowStatus(document: "Launch.key", playing: true, slide: 2, slideCount: 4),
            SlideshowStatus(document: "Launch.key", playing: true, slide: 4, slideCount: 4),
            nil,
        ])
        var sync = SlideSync(deck: try provider.load())
        var roll = PrompterRoll(speed: 40, voiceFollow: false)
        var shown: [String] = []
        var follower = PresenterPage(deck: sync.deck, slide: sync.slide).begin(roll: &roll)
        var ended = false
        for _ in 0..<4 {
            for change in sync.update(try provider.status()) {
                switch change {
                case .started: roll.start(countdown: false)
                case .jump(let slide):
                    let page = PresenterPage(deck: sync.deck, slide: slide)
                    follower = page.begin(roll: &roll)
                    shown.append(page.script.text)
                case .closed: ended = true
                case .ended, .reload: break
                }
            }
            roll.tick(0.5, hovered: false, maxOffset: 500)
        }
        #expect(shown == ["Three things this quarter.\n\nFirst, speed.", "Questions?"])
        #expect(follower.words == ["questions"])
        #expect(ended)
    }

    // MARK: Scroll reset

    @Test func newSlideRestartsTheScroll() {
        var roll = PrompterRoll(speed: 40, voiceFollow: false)
        roll.start(countdown: false)
        roll.tick(1, hovered: false, maxOffset: 500)
        #expect(roll.offset == 40)
        let follower = PresenterPage(deck: deck, slide: 2).begin(roll: &roll)
        #expect(roll.offset == 0 && roll.phase == .rolling)
        #expect(follower.position == 0 && follower.words.first == "three")
        // It keeps rolling on the new notes.
        roll.tick(0.5, hovered: false, maxOffset: 500)
        #expect(roll.offset == 20)
    }

    @Test func scrollResetKeepsPauseAndPicksUpAFinishedRoll() {
        var paused = PrompterRoll(speed: 40, voiceFollow: false)
        paused.start(countdown: false)
        paused.tick(1, hovered: false, maxOffset: 500)
        paused.pause()
        paused.restartSection()
        #expect(paused.offset == 0 && paused.phase == .paused)

        var finished = PrompterRoll(speed: 40, voiceFollow: false)
        finished.start(countdown: false)
        finished.tick(1, hovered: false, maxOffset: 20)
        #expect(finished.phase == .finished)
        finished.restartSection()
        #expect(finished.phase == .rolling && finished.offset == 0)

        var idle = PrompterRoll()
        idle.restartSection()
        #expect(idle.phase == .idle)

        // Voice follow: a moment of grace so the first words of the new slide aren't missed.
        var voice = PrompterRoll(speed: 40, voiceFollow: true)
        let now = Date()
        voice.start(at: now, countdown: false)
        voice.restartSection(at: now)
        #expect(voice.isSpeaking(at: now.addingTimeInterval(0.3)))
    }

    @Test func voiceAdvanceFollowsTheClicker() {
        var advancer = SlideAdvancer(current: 1)
        advancer.sync(to: 3)
        #expect(advancer.shown == 3 && advancer.pending == nil)
        // Words of slide 4 move it on to 4, not 2.
        #expect(advancer.next(forWord: deck.firstWord(ofSlide: 4)!, in: deck) == 4)
        advancer.sync(to: 2)
        #expect(advancer.pending == nil && advancer.shown == 2)
    }

    // MARK: Empty states

    @Test func emptyStates() {
        #expect(PresenterEmptyState.from(PresenterNotesError.noApp) == .noApp)
        #expect(PresenterEmptyState.from(PresenterNotesError.noPresentation("Keynote")) == .noPresentation(app: "Keynote"))
        #expect(PresenterEmptyState.from(PresenterNotesError.automationNotAllowed("PowerPoint")) == .automation(app: "PowerPoint"))
        #expect(PresenterEmptyState.from(PresenterNotesError.googleSlidesNotYet) == .googleSlides)
        #expect(PresenterEmptyState.from(PresenterNotesError.unreadable("boom")) == .failed("boom"))
        #expect(PresenterEmptyState.from(CocoaError(.fileNoSuchFile)) != .noApp)

        // No presentation open.
        #expect(PresenterEmptyState.noApp.title == "No presentation open")
        #expect(PresenterEmptyState.noApp.detail.contains("Keynote or PowerPoint"))
        // A presentation open without notes.
        let bare = PresenterDeck(app: .keynote, name: "Bare", slides: [SlideNotes(number: 1, notes: ""), SlideNotes(number: 2, notes: "")])
        #expect(PresenterEmptyState.forSlide(1, in: bare) == .noNotesInDeck(name: "Bare"))
        #expect(PresenterEmptyState.forSlide(3, in: deck) == .noNotesOnSlide(3))
        #expect(PresenterEmptyState.forSlide(1, in: deck) == nil)
        #expect(!PresenterEmptyState.noNotesOnSlide(3).isBlocking && PresenterEmptyState.noNotesInDeck(name: "Bare").isBlocking)
        // Automation not granted: one-line fix and the Permissions button.
        let automation = PresenterEmptyState.automation(app: "Keynote")
        #expect(automation.opensPermissions && automation.detail.contains("Settings › Permissions"))
        #expect(!PresenterEmptyState.noApp.opensPermissions)
        #expect(PresenterEmptyState.googleSlides.title == "Google Slides notes: not yet")
    }

    @Test func scriptFailuresBecomeTheRightState() {
        #expect(PresenterNotesError.fromScriptFailure("execution error: Not authorized to send Apple events to Keynote. (-1743)", app: "Keynote") == .automationNotAllowed("Keynote"))
        #expect(PresenterNotesError.fromScriptFailure("Application isn't running. (-600)", app: "Keynote") == .noPresentation("Keynote"))
        #expect(PresenterNotesError.fromScriptFailure("", app: "PowerPoint") == .unreadable("PowerPoint did not answer"))
    }

    @Test func googleSlidesIsAClearStub() throws {
        #expect(GoogleSlidesNotesProvider.isPresentation(url: "https://docs.google.com/presentation/d/abc/present?slide=id.p"))
        #expect(!GoogleSlidesNotesProvider.isPresentation(url: "https://docs.google.com/document/d/abc/edit"))
        #expect(!GoogleSlidesNotesProvider.isPresentation(url: "https://evil.example/docs.google.com/presentation/"))
        #expect(throws: PresenterNotesError.googleSlidesNotYet) { try GoogleSlidesNotesProvider().load() }
        #expect(try GoogleSlidesNotesProvider().status() == nil)
    }

    // MARK: Polling and placement

    @Test func pollingStaysCheap() {
        #expect(PresenterPolling.followInterval(playing: true) == 0.5)
        #expect(PresenterPolling.followInterval(playing: false) == 1.5)
        #expect(PresenterPolling.watchInterval(appRunning: false, frontmost: true, fullScreenWindow: true) == nil)
        #expect(PresenterPolling.watchInterval(appRunning: true, frontmost: false, fullScreenWindow: false) == nil)
        #expect(PresenterPolling.watchInterval(appRunning: true, frontmost: true, fullScreenWindow: false) == 3)
        #expect(PresenterPolling.watchInterval(appRunning: true, frontmost: false, fullScreenWindow: true) == 1)
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)]
        #expect(PresenterPolling.hasFullScreenWindow([CGRect(x: 1512, y: 0, width: 1920, height: 1080)], screens: screens))
        #expect(!PresenterPolling.hasFullScreenWindow([CGRect(x: 100, y: 100, width: 1200, height: 800)], screens: screens))
    }

    @Test func placementPrefersTheCameraOrYourDisplay() {
        let laptop = PrompterDisplay(id: "A", name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), topInset: 38, hasCamera: true)
        let tv = PrompterDisplay(id: "B", name: "TV", frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), topInset: 24, hasCamera: false)
        #expect(PrompterPlacement.display(preferred: PrompterPlacement.camera, among: [tv, laptop]) == laptop)
        #expect(PrompterPlacement.display(preferred: "B", among: [laptop, tv]) == tv)
        #expect(PrompterPlacement.display(preferred: "gone", among: [tv, laptop]) == laptop)
        #expect(PrompterPlacement.display(preferred: nil, among: [tv]) == tv)
        let origin = PrompterPlacement.origin(for: CGSize(width: 640, height: 300), on: laptop)
        #expect(origin == CGPoint(x: 436, y: 982 - 38 - 6 - 300))
        #expect(PrompterPlacement.needsMove(window: CGRect(origin: origin, size: CGSize(width: 640, height: 300)), to: tv))
        #expect(!PrompterPlacement.needsMove(window: CGRect(origin: origin, size: CGSize(width: 640, height: 300)), to: laptop))
    }
}
