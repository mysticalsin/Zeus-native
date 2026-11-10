import Foundation
import Testing
@testable import ZeusCore

/// Keynote and PowerPoint are not installed here: everything runs on fixtures and a mocked runner.
@Suite("Presenter notes")
struct PresenterNotesTests {
    struct FakeRunner: AppleScriptRunner {
        let output: String
        func run(_ source: String) throws -> String { output }
    }

    let US = "\u{1F}", RS = "\u{1E}"

    @Test func keynoteOutputParses() throws {
        let output = "Launch deck\(RS)2\(RS)1\(US)Welcome\(US)Hi everyone, thanks for coming.\(RS)2\(US)Roadmap\(US)Three things this quarter.\nFirst, speed.\(RS)3\(US)\(US)"
        let deck = try KeynoteNotesProvider(runner: FakeRunner(output: output)).load()
        #expect(deck.name == "Launch deck" && deck.current == 2 && deck.app == .keynote)
        #expect(deck.slides.map(\.number) == [1, 2, 3])
        #expect(deck.slides[1].notes == "Three things this quarter.\nFirst, speed.")
        #expect(deck.slides[2].notes.isEmpty)
        #expect(throws: PresenterNotesError.noPresentation("Keynote")) { try KeynoteNotesProvider.parse("") }
    }

    @Test func scriptHasACuePerSlide() throws {
        let deck = PresenterDeck(app: .keynote, name: "d", slides: [
            SlideNotes(number: 1, title: "Welcome", notes: "Hi everyone."),
            SlideNotes(number: 2, title: "", notes: ""),
            SlideNotes(number: 3, title: "Close\nnow", notes: "Thanks."),
        ])
        #expect(deck.script == "# 1 · Welcome\nHi everyone.\n\n# 2\n\n# 3 · Close now\nThanks.")
        #expect(PrompterScript(deck.script).cues.count == 3)
    }

    @Test func wordsMapToSlides() {
        let deck = PresenterDeck(app: .keynote, name: "d", slides: [
            SlideNotes(number: 1, notes: "Hi everyone thanks"),   // words 0-2
            SlideNotes(number: 2, notes: ""),                      // none
            SlideNotes(number: 3, notes: "Three things now"),      // words 3-5
        ])
        #expect(deck.slide(forWord: 0) == 1)
        #expect(deck.slide(forWord: 2) == 1)
        #expect(deck.slide(forWord: 3) == 3)
        #expect(deck.slide(forWord: 99) == 3)
        #expect(deck.firstWord(ofSlide: 3) == 3)
        #expect(deck.firstWord(ofSlide: 9) == nil)
        // The follower over the deck's script counts the same words.
        #expect(ScriptFollower(script: PrompterScript(deck.script)).words.count == 6)
    }

    let notesXML = """
    <p:notes xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree>
    <p:sp><p:nvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr></p:sp>
    <p:sp><p:nvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:txBody>
    <a:p><a:r><a:t>Open with the </a:t></a:r><a:r><a:t>customer story.</a:t></a:r></a:p>
    <a:p><a:r><a:t>Pause for questions.</a:t></a:r></a:p>
    <a:p></a:p>
    </p:txBody></p:sp>
    <p:sp><p:nvSpPr><p:nvPr><p:ph type="sldNum" idx="5"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>4</a:t></a:r></a:p></p:txBody></p:sp>
    </p:spTree></p:cSld></p:notes>
    """

    @Test func pptxNotesXMLParses() {
        #expect(PPTXNotes.notesText(fromXML: Data(notesXML.utf8)) == "Open with the customer story.\nPause for questions.")
        let rels = #"<Relationships><Relationship Id="rId2" Target="../slides/slide7.xml"/></Relationships>"#
        #expect(PPTXNotes.slideNumber(fromRelationships: Data(rels.utf8)) == 7)
        #expect(PPTXNotes.slideNumber(fromRelationships: Data("<x/>".utf8)) == nil)
    }

    @Test func powerPointDeckFromAPPTX() throws {
        let files: [String: String] = [
            "ppt/slides/slide1.xml": "", "ppt/slides/slide2.xml": "", "ppt/slides/slide3.xml": "",
            "ppt/notesSlides/notesSlide1.xml": notesXML,
            "ppt/notesSlides/_rels/notesSlide1.xml.rels": #"<R Target="../slides/slide2.xml"/>"#,
        ]
        let provider = PowerPointNotesProvider(
            runner: FakeRunner(output: "/Users/x/Talk.pptx\u{1E}2"),
            listEntries: { _ in Array(files.keys) },
            readEntry: { _, entry in files[entry].map { Data($0.utf8) } })
        let deck = try provider.load()
        #expect(deck.name == "Talk" && deck.app == .powerPoint && deck.current == 2)
        #expect(deck.slides.map(\.number) == [1, 2, 3])
        #expect(deck.slides[1].notes.hasPrefix("Open with the customer story."))
        #expect(deck.slides[0].notes.isEmpty)
        let none = PowerPointNotesProvider(runner: FakeRunner(output: ""), listEntries: { _ in [] }, readEntry: { _, _ in nil })
        #expect(throws: PresenterNotesError.noPresentation("PowerPoint")) { try none.load() }
        #expect(throws: (any Error).self) {
            try PowerPointNotesProvider.deck(fromPPTX: "/x/notes.txt", listEntries: { _ in [] }, readEntry: { _, _ in nil })
        }
    }
}
