import Foundation
import Testing
@testable import ZeusCore

/// The in-browser deck notes contract. Synthetic strings only: no browser, no socket, no prompt.
@Suite("Deck notes reader")
struct DeckNotesReaderTests {
    private static let sentence = "Open on the quarter, then the two numbers. Pause after the second. If they ask about the hiring plan, it is on the next slide. Leave the chart up while you answer."
    private static let deckTitle = "Quarterly review"
    private static let documentID = "doc-1"
    private static let deck = "https://docs.google.com/presentation/d/abc/edit"
    private static let target = DeckNotesTarget(tabID: 7, documentID: documentID, url: deck)

    private static let refusedURLs = [
        "http://docs.google.com/presentation/d/abc",
        "https://docs.google.com.evil.example/presentation/d/abc",
        "https://docs.google.com.evil.example/presentation/d/abc/present",
        "https://evil.docs.google.com/presentation/d/abc",
        "https://docs.google.com.attacker.test/presentation/d/abc",
        "https://user:secret@docs.google.com/presentation/d/abc",
        "https://docs.google.com:444/presentation/d/abc",
        "https://docs.google.com./presentation/d/abc",
        "https://docs.google.com%2e.evil.example/presentation/d/abc",
        "https://docs.google.com%00.evil.example/presentation/d/abc",
        "https://docs.google.com%2f.evil.example/presentation/d/abc",
        "https://evil.example/presentation/d/abc?next=https://docs.google.com/presentation/d/abc",
        "https://evil.example\\@docs.google.com/presentation/d/abc",
        "javascript:https://docs.google.com/presentation/d/abc",
        "data:text/html,https://docs.google.com/presentation/d/abc",
        "//docs.google.com/presentation/d/abc",
        "https://docs.google.com/presentation",
        "https://docs.google.com/presentations/d/abc",
        "https://127.0.0.1/presentation/d/abc",
        "",
    ]

    // MARK: Route table

    @Test func routeTableMatchesTheSpec() {
        let routes = DeckNotesRoutes.all
        #expect(routes.map(\.rank) == [1, 2, 3, 4])
        #expect(routes.map(\.reads) == [.yes, .sometimes, .poorly, .pixels])
        #expect(routes.map(\.newTCCPrompt) == [false, false, true, true])
        #expect(routes.map(\.eligible) == [true, false, false, false])
        #expect(routes.allSatisfy { $0.prompts == false })
        #expect(routes.filter(\.eligible).map(\.rank) == [1])
        #expect(DeckNotesRoutes.chosen.rank == 1)
        #expect(DeckNotesRoutes.chosen.eligible)
        #expect(DeckNotesRoutes.chosen.prompts == false)
    }

    // MARK: Parser and text

    @Test func parserAcceptsTheFiveFields() throws {
        let parsed = try #require(DeckNotesParser.parse(json(
            title: "  \(Self.deckTitle)  ", slide: 4, count: 18, notes: "one\ntwo\n\nthree", notesInDocument: true
        )))
        #expect(parsed.title == Self.deckTitle)
        #expect(parsed.slide == 4 && parsed.count == 18)
        #expect(parsed.notes == "one\ntwo\n\nthree")
        #expect(parsed.notesInDocument)
        #expect(parsed.truncated == false)
    }

    @Test func parserRejectsABadPayload() throws {
        #expect(DeckNotesParser.parse(try object([
            "title": "T", "slide": 1, "count": 1, "notes": "n", "notesInDocument": true, "text": "visible page",
        ])) == nil)
        #expect(DeckNotesParser.parse(try object([
            "slide": 1, "count": 1, "notes": "n", "notesInDocument": true,
        ])) == nil)
        #expect(DeckNotesParser.parse(try json(title: "T", slide: 0, count: 1, notes: "n", notesInDocument: true)) == nil)
        #expect(DeckNotesParser.parse(try json(title: "T", slide: 2, count: 1, notes: "n", notesInDocument: true)) == nil)
        #expect(DeckNotesParser.parse(try object([
            "title": "T", "slide": 1, "count": 1, "notes": 4, "notesInDocument": true,
        ])) == nil)
        #expect(DeckNotesParser.parse(Data("[]".utf8)) == nil)
    }

    @Test func notesCapKeepsLineBreaksAndDropsThe8001stCharacter() throws {
        let notes = String(repeating: "a", count: 8_000) + "Z"
        let parsed = try #require(DeckNotesParser.parse(json(
            title: "T", slide: 1, count: 1, notes: notes, notesInDocument: true
        )))
        #expect(parsed.notes.count == 8_000)
        #expect(parsed.notes.hasSuffix("a"))
        #expect(parsed.truncated)
        let broken = "one\ntwo"
        let kept = try #require(DeckNotesParser.parse(json(
            title: "T", slide: 1, count: 1, notes: broken, notesInDocument: true
        )))
        #expect(kept.notes == broken)
        let longTitle = " " + String(repeating: "Q", count: 201) + " "
        let titled = try #require(DeckNotesParser.parse(json(
            title: longTitle, slide: 1, count: 1, notes: "n", notesInDocument: true
        )))
        #expect(titled.title.count == 200)
        #expect(titled.truncated == false)
    }

    @Test func stripsFormatCharactersSeparatorsAndVariationSelectors() throws {
        var value: UInt32 = 0
        var stayed: [UInt32] = []
        while value <= 0x10FFFF {
            if let scalar = Unicode.Scalar(value), scalar.properties.generalCategory == .format,
               !DeckNotesText.cleaned(String(scalar)).isEmpty {
                stayed.append(value)
            }
            value += 1
        }
        #expect(stayed.isEmpty)
        #expect(DeckNotesText.cleaned("A\u{2028}B\u{2029}C") == "ABC")
        for unit in 0xFE00...0xFE0F {
            let scalar = try #require(Unicode.Scalar(unit))
            #expect(DeckNotesText.cleaned("A\(String(scalar))B") == "AB")
        }
        for unit in [0xE0100, 0xE0101, 0xE01EF] {
            let scalar = try #require(Unicode.Scalar(unit))
            #expect(DeckNotesText.cleaned("A\(String(scalar))B") == "AB")
        }
        #expect(DeckNotesText.cleaned("A\nB\r\nC") == "A\nB\r\nC")
        #expect(DeckNotesText.cleaned("A\u{200A}B") == "A\u{200A}B")
        let dirty = "Open\u{200B} on\u{202E} the\u{FE0F} quarter\u{2028}."
        let parsed = try #require(DeckNotesParser.parse(json(
            title: "Q\u{202E}uarter", slide: 1, count: 1, notes: dirty, notesInDocument: true
        )))
        #expect(parsed.notes == "Open on the quarter.")
        #expect(parsed.title == "Quarter")
        let capped = String(repeating: "a", count: 8_000) + "\u{FEFF}"
        let exact = try #require(DeckNotesParser.parse(json(
            title: "T", slide: 1, count: 1, notes: capped, notesInDocument: true
        )))
        #expect(exact.notes.count == 8_000)
        #expect(exact.truncated == false)
    }

    @Test func anOversizedFrameIsRejectedBeforeItIsParsed() {
        #expect(DeckNotesLimits.notesCap == 8_000)
        #expect(DeckNotesLimits.hostToBrowser == NativeMessagingFrame.maxHostToChromeBytes)
        #expect(DeckNotesLimits.browserToHost == NativeMessagingFrame.maxChromeToHostBytes)
        #expect(DeckNotesLimits.hostToBrowser == 1_048_576)
        #expect(DeckNotesLimits.browserToHost == 4_194_304)
        let oversized = Data(repeating: 0x7B, count: DeckNotesLimits.browserToHost + 1)
        #expect(DeckNotesParser.parse(oversized) == nil)
        #expect(DeckNotesHost.socketMode == 0o600)
        let origins = DeckNotesHost.allowedOrigins(extensionID: "abcdefghijklmnopabcdefghijklmnop")
        #expect(origins == ["chrome-extension://abcdefghijklmnopabcdefghijklmnop/"])
        #expect(DeckNotesHost.allowedOrigins(extensionID: "*").isEmpty)
        #expect(DeckNotesHost.allowedOrigins(extensionID: "ab/cd").isEmpty)
    }

    // MARK: Predicate

    @Test func predicateMatchesTheDeckHostAndRefusesTheHostileList() {
        let accepted = [
            "https://docs.google.com/presentation/d/abc/edit",
            "https://docs.google.com/presentation/d/abc/present",
            "https://docs.google.com/presentation/d/abc/edit?usp=sharing#slide=id.p",
            "https://docs.google.com:443/presentation/d/abc",
            "HTTPS://docs.google.com/presentation/d/abc/present",
        ]
        for url in accepted {
            #expect(DeckNotesURL.isDeck(url), "expected a deck: \(url)")
            #expect(DeckNotesURL.allowsExecuteScript(url) == DeckNotesURL.isDeck(url))
        }
        for url in Self.refusedURLs {
            #expect(!DeckNotesURL.isDeck(url), "expected refusal: \(url)")
            #expect(DeckNotesURL.allowsExecuteScript(url) == false)
        }
        #expect(GoogleSlidesNotesProvider.isPresentation(url: accepted[0]))
        #expect(!GoogleSlidesNotesProvider.isPresentation(url: Self.refusedURLs[0]))
    }

    // MARK: Machine

    @Test func readFromIdleFindsADeckAndDoesNotReadNotes() {
        var reader = DeckNotesReader()
        #expect(reader.send(.read) == [.findDeck])
        #expect(reader.state == .checking)
        #expect(reader.isHolding == false)
        #expect(reader.send(.read).isEmpty)
        #expect(reader.state == .checking)
    }

    @Test func choosingTheTab() {
        var down = DeckNotesReader()
        #expect(down.send(.read) == [.findDeck])
        #expect(down.send(.bridgeDown(.socketGone)) == [])
        #expect(down.state == .failed(.extensionOff))

        var quiet = DeckNotesReader()
        _ = quiet.send(.read)
        #expect(quiet.send(.bridgeDown(.noReply)) == [])
        #expect(quiet.state == .failed(.extensionOff))

        var priv = DeckNotesReader()
        _ = priv.send(.read)
        #expect(priv.send(.activePrivate) == [])
        #expect(priv.state == .failed(.privateWindow))

        var none = DeckNotesReader()
        _ = none.send(.read)
        #expect(none.send(.noMatch) == [])
        #expect(none.state == .failed(.noDeck))

        var ok = DeckNotesReader()
        _ = ok.send(.read)
        #expect(ok.send(.matched(Self.target)) == [.readNotes(Self.target)])
        if case .reading(let target) = ok.state {
            #expect(target == Self.target)
        } else {
            Issue.record("expected reading")
        }
        #expect(ok.send(.read).isEmpty)
        #expect(ok.send(.matched(Self.target)).isEmpty)

        var hostile = DeckNotesReader()
        _ = hostile.send(.read)
        let bad = DeckNotesTarget(tabID: 1, documentID: "d", url: "https://evil.example/presentation/d/abc")
        #expect(hostile.send(.matched(bad)).isEmpty)
        #expect(hostile.state == .failed(.noDeck))
    }

    @Test func showNotesAndTheEmptySlide() {
        var reader = DeckNotesReader()
        show(&reader, notes: Self.sentence)
        guard case .showing(let held) = reader.state else {
            Issue.record("expected showing")
            return
        }
        #expect(held.title == Self.deckTitle)
        #expect(held.slide == 4 && held.count == 18)
        #expect(held.notes == Self.sentence)
        #expect(held.truncated == false)
        let page = DeckNotesPage.make(reader.state)
        #expect(page.kicker == "Speaker notes")
        #expect(page.position == "4 / 18")
        #expect(page.notes == Self.sentence)
        #expect(page.accessibilityLabel == "Speaker notes, slide 4 of 18")
        #expect(page.accessibilityValue == nil)
        #expect(!page.accessibilityLabel.contains(Self.sentence))
        #expect(page.notesAreAccessibilityValue == false)

        var empty = DeckNotesReader()
        show(&empty, notes: "", slide: 4, count: 18)
        let emptyPage = DeckNotesPage.make(empty.state)
        #expect(empty.isHolding)
        #expect(empty.heldNotes.isEmpty)
        #expect(emptyPage.caption == "No notes on slide 4")
        #expect(emptyPage.captionDetail == "Read again when you move on.")

        var missing = DeckNotesReader()
        _ = missing.send(.read)
        _ = missing.send(.matched(Self.target))
        let body = DeckNotesFields(title: "T", slide: 1, count: 1, notes: "visible slide body", notesInDocument: false, truncated: false)
        #expect(missing.send(.payload(.document(id: Self.documentID, fields: body))).isEmpty)
        #expect(missing.state == .failed(.notesNotOnPage))
        #expect(missing.isHolding == false)
        #expect(missing.heldNotes.isEmpty)
        let failed = DeckNotesPage.make(missing.state)
        #expect(failed.failureTitle == "Notes are not on this page")
        #expect(failed.failureLine == "Open the speaker notes in the browser, then press Read.")
        #expect(failed.notes.isEmpty)
    }

    @Test func aMalformedOrStalePayloadDropsTheBuffer() {
        var bad = DeckNotesReader()
        _ = bad.send(.read)
        _ = bad.send(.matched(Self.target))
        #expect(bad.send(.payload(.document(id: Self.documentID, fields: nil))).isEmpty)
        #expect(bad.state == .failed(.unreadable))
        #expect(bad.heldNotes.isEmpty && bad.isHolding == false)

        var stale = DeckNotesReader()
        _ = stale.send(.read)
        _ = stale.send(.matched(Self.target))
        #expect(stale.send(.payload(.stale(id: Self.documentID))).isEmpty)
        #expect(stale.state == .failed(.deckChanged))
        #expect(stale.heldNotes.isEmpty)

        var late = DeckNotesReader()
        _ = late.send(.read)
        _ = late.send(.matched(Self.target))
        let other = DeckNotesFields(title: "Other", slide: 1, count: 1, notes: "nope", notesInDocument: true, truncated: false)
        #expect(late.send(.payload(.document(id: "other-doc", fields: other))).isEmpty)
        if case .reading = late.state {} else { Issue.record("a late payload is dropped") }

        var idle = DeckNotesReader()
        #expect(idle.send(.payload(.document(id: Self.documentID, fields: other))).isEmpty)
        #expect(idle.state == .idle)
        #expect(idle.send(.matched(Self.target)).isEmpty)
    }

    @Test func followWatchesTheSlideAndStopsAfter120Polls() {
        #expect(DeckNotesFollow.interval == 0.5)
        #expect(DeckNotesFollow.maximumPolls == 120)

        var idle = DeckNotesReader()
        #expect(idle.send(.follow).isEmpty)
        #expect(idle.state == .idle)

        var reader = DeckNotesReader()
        show(&reader, notes: Self.sentence)
        #expect(reader.send(.follow) == [.watchIndex(Self.target)])
        #expect(reader.watchRunning)
        let same = index(slide: 4, count: 18)
        #expect(reader.send(.index(same)).isEmpty)
        #expect(reader.watchRunning)
        #expect(reader.send(.index(index(slide: 5, count: 18))) == [.readNotes(Self.target)])
        if case .reading = reader.state {} else { Issue.record("a new slide reads notes") }

        var watching = DeckNotesReader()
        show(&watching, notes: Self.sentence)
        _ = watching.send(.follow)
        #expect(watching.send(.stop) == [.cancelWatch])
        if case .showing = watching.state {} else { Issue.record("stop returns to showing") }
        #expect(watching.watchRunning == false)
        #expect(watching.heldNotes == Self.sentence)

        var polls = DeckNotesReader()
        show(&polls, notes: Self.sentence)
        _ = polls.send(.follow)
        for _ in 1..<120 {
            #expect(polls.send(.index(same)).isEmpty)
        }
        #expect(polls.send(.index(same)) == [.cancelWatch])
        #expect(polls.watchRunning == false)
        #expect(polls.send(.index(same)).isEmpty)
        #expect(polls.heldNotes == Self.sentence)

        var left = DeckNotesReader()
        show(&left, notes: Self.sentence)
        _ = left.send(.follow)
        #expect(left.send(.index(index(slide: 4, count: 18, url: "https://evil.example/presentation/d/abc")) ) == [.cancelWatch])
        #expect(left.state == .failed(.deckChanged))
        #expect(left.heldNotes.isEmpty)

        var priv = DeckNotesReader()
        show(&priv, notes: Self.sentence)
        _ = priv.send(.follow)
        #expect(priv.send(.index(index(slide: 4, count: 18, isPrivate: true))) == [.cancelWatch])
        #expect(priv.state == .failed(.privateWindow))
        #expect(priv.heldNotes.isEmpty)

        var unknown = DeckNotesReader()
        show(&unknown, notes: Self.sentence)
        _ = unknown.send(.follow)
        #expect(unknown.send(.index(index(slide: 4, count: 18, isPrivate: nil))) == [.cancelWatch])
        #expect(unknown.state == .failed(.privateWindow))
        #expect(unknown.heldNotes.isEmpty)
    }

    @Test func clearAndDismissDropTheBuffer() {
        for failure in DeckNotesFailure.all {
            var reader = failed(failure)
            let effects = reader.send(.clear)
            #expect(effects.isEmpty)
            #expect(reader.state == .idle)
            #expect(reader.heldNotes.isEmpty && reader.isHolding == false)
            var again = failed(failure)
            #expect(again.send(.dismiss).isEmpty)
            #expect(again.state == .idle)
        }

        var shown = DeckNotesReader()
        show(&shown, notes: Self.sentence)
        #expect(shown.send(.clear).isEmpty)
        #expect(shown.state == .idle)
        #expect(shown.send(.payload(.document(id: Self.documentID, fields: sampleFields()))).isEmpty)
        #expect(shown.state == .idle)
        #expect(shown.send(.read) == [.findDeck])

        var watching = DeckNotesReader()
        show(&watching, notes: Self.sentence)
        _ = watching.send(.follow)
        #expect(watching.send(.dismiss) == [.cancelWatch])
        #expect(watching.state == .idle)
        #expect(watching.heldNotes.isEmpty)

        var idle = DeckNotesReader()
        #expect(idle.send(.clear).isEmpty)
        #expect(idle.state == .idle)
    }

    @Test func aSessionUsesOnlyTheFourEffects() {
        var reader = DeckNotesReader()
        var effects: [DeckNotesEffect] = []
        effects += reader.send(.read)
        effects += reader.send(.matched(Self.target))
        effects += reader.send(.payload(.document(id: Self.documentID, fields: sampleFields())))
        effects += reader.send(.follow)
        effects += reader.send(.index(index(slide: 5, count: 18)))
        effects += reader.send(.payload(.document(id: Self.documentID, fields: sampleFields(slide: 5))))
        effects += reader.send(.dismiss)
        #expect(!effects.isEmpty)
        for effect in effects {
            switch effect {
            case .findDeck, .readNotes, .watchIndex, .cancelWatch:
                break
            }
        }
        #expect(effects.contains(.findDeck))
        #expect(effects.contains(.readNotes(Self.target)))
        #expect(effects.contains(.watchIndex(Self.target)))
        #expect(effects.contains(.cancelWatch))
    }

    @Test func theLogNameOmitsTheNotesTheTitleAndTheURL() {
        var reader = DeckNotesReader()
        show(&reader, notes: Self.sentence)
        let described = String(describing: reader.state)
        #expect(described == "showing")
        #expect(!described.contains(Self.sentence))
        #expect(!described.contains(Self.deckTitle))
        #expect(!described.contains("docs.google.com"))
        #expect(!described.contains(Self.documentID))
        #expect(String(describing: DeckNotesState.idle) == "idle")
        #expect(String(describing: DeckNotesState.checking) == "checking")
        #expect(String(describing: DeckNotesState.reading(Self.target)) == "reading")
        #expect(String(describing: DeckNotesState.failed(.timedOut)) == "failed timedOut")
        let names = DeckNotesFailure.all.map { "failed \($0)" }
        #expect(names == [
            "failed extensionOff", "failed noDeck", "failed privateWindow", "failed notesNotOnPage",
            "failed deckChanged", "failed unreadable", "failed timedOut",
        ])
    }

    @Test func theDesktopPathDoesNotSendRead() {
        #expect(DeckNotesSelector.sendsBrowserRead(presentationAppRunning: true, personAsked: true) == false)
        #expect(DeckNotesSelector.sendsBrowserRead(presentationAppRunning: false, personAsked: true) == true)
        #expect(DeckNotesSelector.sendsBrowserRead(presentationAppRunning: false, personAsked: false) == false)
        #expect(DeckNotesSelector.sendsBrowserRead(presentationAppRunning: true, personAsked: false) == false)
    }

    @Test func copyMatchesTheFailureTable() {
        #expect(DeckNotesFailure.extensionOff.title == "The browser extension is off")
        #expect(DeckNotesFailure.extensionOff.line == "Turn on the Zeus extension in the browser, then press Read.")
        #expect(DeckNotesFailure.noDeck.title == "No slide deck in the browser")
        #expect(DeckNotesFailure.noDeck.line == "Open the deck in the browser, then press Read.")
        #expect(DeckNotesFailure.privateWindow.title == "Private window")
        #expect(DeckNotesFailure.privateWindow.line == "Zeus does not read a private window.")
        #expect(DeckNotesFailure.notesNotOnPage.title == "Notes are not on this page")
        #expect(DeckNotesFailure.notesNotOnPage.line == "Open the speaker notes in the browser, then press Read.")
        #expect(DeckNotesFailure.deckChanged.title == "The deck changed")
        #expect(DeckNotesFailure.deckChanged.line == "Press Read to load the slide in front.")
        #expect(DeckNotesFailure.unreadable.title == "Could not read the speaker notes")
        #expect(DeckNotesFailure.unreadable.line == "Press Read to try again.")
        #expect(DeckNotesFailure.timedOut.title == "The browser did not answer")
        #expect(DeckNotesFailure.timedOut.line == "Press Read to try again.")
        #expect(DeckNotesCopy.loading == "Reading speaker notes")
        #expect(DeckNotesCopy.kicker == "Speaker notes")
        #expect(DeckNotesCopy.truncated == "Truncated")
        #expect(DeckNotesCopy.emptyTitle(slide: 4) == "No notes on slide 4")
        #expect(DeckNotesCopy.emptyDetail == "Read again when you move on.")
        #expect(DeckNotesCopy.position(slide: 4, count: 18) == "4 / 18")
        #expect(DeckNotesCopy.voiceOver(slide: 4, count: 18) == "Speaker notes, slide 4 of 18")

        var reader = DeckNotesReader()
        _ = reader.send(.read)
        #expect(DeckNotesPage.make(reader.state).loadingLine == "Reading speaker notes")
        var truncated = DeckNotesReader()
        show(&truncated, notes: "short", truncated: true)
        #expect(DeckNotesPage.make(truncated.state).caption == "Truncated")

        let notes = "# Leave this line\nSecond"
        #expect(DeckNotesPage.displayedNotes(notes) == notes)
        let markIsACueInTheScript = PrompterScript(notes).blocks.contains { $0.isCue }
        #expect(markIsACueInTheScript)
        #expect(DeckNotesScriptGuard.floatingScript(existing: "Already here", notes: Self.sentence) == "Already here")
    }

    @Test func reduceMotionReplacesTheSlideInPlace() {
        let reduced = DeckNotesMotion.presentation(reduceMotion: true)
        #expect(reduced.replacesInPlace)
        #expect(reduced.rolls == false)
        #expect(reduced.crossfades == false)
        #expect(reduced.buttonScales == false)
        let moving = DeckNotesMotion.presentation(reduceMotion: false)
        #expect(moving.replacesInPlace)
        #expect(moving.rolls == false)
        #expect(moving.crossfades == false)
    }

    // MARK: Capture

    @Test func aShareOrRecordingHidesTheWholeBar() {
        #expect(DeckNotesCapturePolicy.notesSurface == .existingBar)
        #expect(DeckNotesCapturePolicy.opensAnotherWindow == false)
        #expect(DeckNotesCapturePolicy.canHideOneViewInsideTheBar == false)
        for shown in [true, false] {
            let share = DeckNotesCapturePolicy.barSharing(
                notesVisible: true, screenShareDetected: true, recordingDetected: false, showInScreenSharing: shown
            )
            let recording = DeckNotesCapturePolicy.barSharing(
                notesVisible: true, screenShareDetected: false, recordingDetected: true, showInScreenSharing: shown
            )
            let both = DeckNotesCapturePolicy.barSharing(
                notesVisible: true, screenShareDetected: true, recordingDetected: true, showInScreenSharing: shown
            )
            #expect(share == .none)
            #expect(recording == .none)
            #expect(both == .none)
        }
        #expect(DeckNotesCapturePolicy.barSharing(
            notesVisible: true, screenShareDetected: false, recordingDetected: false, showInScreenSharing: true
        ) == .none)
        #expect(DeckNotesCapturePolicy.sharingAfterRefresh(notesVisible: true, requestedVisibleInShare: true) == .none)
        #expect(DeckNotesCapturePolicy.sharingAfterRefresh(notesVisible: false, requestedVisibleInShare: true) == .unchanged)
        #expect(DeckNotesCapturePolicy.barSharing(
            notesVisible: false, screenShareDetected: true, recordingDetected: true, showInScreenSharing: true
        ) == .unchanged)
        #expect(String(describing: DeckNotesCapturePolicy.BarSharing.none) == "none")
    }

    // MARK: Helpers

    private func json(title: String, slide: Int, count: Int, notes: String, notesInDocument: Bool) throws -> Data {
        try object([
            "title": title, "slide": slide, "count": count, "notes": notes, "notesInDocument": notesInDocument,
        ])
    }

    private func object(_ fields: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: fields)
    }

    private func sampleFields(slide: Int = 4, notes: String = DeckNotesReaderTests.sentence, truncated: Bool = false) -> DeckNotesFields {
        DeckNotesFields(title: Self.deckTitle, slide: slide, count: 18, notes: notes, notesInDocument: true, truncated: truncated)
    }

    private func show(_ reader: inout DeckNotesReader, notes: String, slide: Int = 4, count: Int = 18, truncated: Bool = false) {
        _ = reader.send(.read)
        _ = reader.send(.matched(Self.target))
        _ = reader.send(.payload(.document(id: Self.documentID, fields: DeckNotesFields(
            title: Self.deckTitle, slide: slide, count: count, notes: notes, notesInDocument: true, truncated: truncated
        ))))
    }

    private func index(slide: Int, count: Int, url: String = DeckNotesReaderTests.deck, isPrivate: Bool? = false) -> DeckNotesIndex {
        DeckNotesIndex(slide: slide, count: count, url: url, isPrivate: isPrivate, documentID: Self.documentID)
    }

    private func failed(_ failure: DeckNotesFailure) -> DeckNotesReader {
        var reader = DeckNotesReader()
        _ = reader.send(.read)
        switch failure {
        case .extensionOff:
            _ = reader.send(.bridgeDown(.socketGone))
        case .noDeck:
            _ = reader.send(.noMatch)
        case .privateWindow:
            _ = reader.send(.activePrivate)
        case .notesNotOnPage:
            _ = reader.send(.matched(Self.target))
            _ = reader.send(.payload(.document(id: Self.documentID, fields: DeckNotesFields(
                title: "T", slide: 1, count: 1, notes: "body", notesInDocument: false, truncated: false
            ))))
        case .deckChanged:
            _ = reader.send(.matched(Self.target))
            _ = reader.send(.payload(.stale(id: Self.documentID)))
        case .unreadable:
            _ = reader.send(.matched(Self.target))
            _ = reader.send(.payload(.document(id: Self.documentID, fields: nil)))
        case .timedOut:
            _ = reader.send(.matched(Self.target))
            _ = reader.send(.bridgeDown(.noReply))
        }
        return reader
    }
}
