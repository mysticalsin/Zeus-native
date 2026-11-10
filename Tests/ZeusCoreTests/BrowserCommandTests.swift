import Foundation
import Testing
@testable import ZeusCore

@Suite struct BrowserCommandTests {
    /// Parses one `[ACTION:{…}]` tag into a browser command.
    private func command(_ tag: String) -> BrowserCommand? {
        guard case .action(let action)? = ZeusTagParser.parse(tag + " ok").tags.first else { return nil }
        return BrowserCommand(action)
    }

    @Test func clickIndexParses() {
        #expect(command(#"[ACTION:{"type":"browser.click_index","index":12,"state":"k3x9ab"}]"#)
            == .clickIndex(index: 12, state: "k3x9ab"))
        #expect(command(#"[ACTION:{"type":"browser.click_index","index":"4"}]"#) == .clickIndex(index: 4, state: nil))
        #expect(command(#"[ACTION:{"type":"browser.click_index","index":0}]"#) == nil)
        #expect(command(#"[ACTION:{"type":"browser.click_index","index":2.5}]"#) == nil)
        #expect(command(#"[ACTION:{"type":"browser.click_index"}]"#) == nil)
    }

    @Test func typeIndexParses() {
        #expect(command(#"[ACTION:{"type":"browser.type_index","index":4,"text":"zeus ]","submit":true,"state":"s1"}]"#)
            == .typeIndex(index: 4, text: "zeus ]", submit: true, state: "s1"))
        #expect(command(#"[ACTION:{"type":"browser.type_index","index":4,"text":"hi"}]"#)
            == .typeIndex(index: 4, text: "hi", submit: false, state: nil))
        #expect(command(#"[ACTION:{"type":"browser.type_index","index":4}]"#) == nil)
    }

    @Test func selectParses() {
        #expect(command(#"[ACTION:{"type":"browser.select","index":7,"option":"Large","state":"s1"}]"#)
            == .selectOption(index: 7, option: "Large", state: "s1"))
        #expect(command(#"[ACTION:{"type":"browser.select","index":7,"option":""}]"#) == nil)
    }

    @Test func scrollParses() {
        #expect(command(#"[ACTION:{"type":"browser.scroll","direction":"up","pages":2}]"#) == .scroll(.up(pages: 2), state: nil))
        #expect(command(#"[ACTION:{"type":"browser.scroll"}]"#) == .scroll(.down(pages: 1), state: nil))
        #expect(command(#"[ACTION:{"type":"browser.scroll","direction":"down","pages":99}]"#) == .scroll(.down(pages: 10), state: nil))
        #expect(command(#"[ACTION:{"type":"browser.scroll","index":9,"state":"s1"}]"#) == .scroll(.toElement(index: 9), state: "s1"))
        #expect(command(#"[ACTION:{"type":"browser.scroll","direction":"sideways"}]"#) == nil)
    }

    @Test func historyAndTabsParse() {
        #expect(command(#"[ACTION:{"type":"browser.back"}]"#) == .back)
        #expect(command(#"[ACTION:{"type":"browser.forward"}]"#) == .forward)
        #expect(command(#"[ACTION:{"type":"browser.switch_tab","title":"Gmail"}]"#) == .switchTab(.title("Gmail")))
        #expect(command(#"[ACTION:{"type":"browser.switch_tab","tabId":381}]"#) == .switchTab(.id(381)))
        #expect(command(#"[ACTION:{"type":"browser.switch_tab"}]"#) == nil)
        #expect(command(#"[ACTION:{"type":"browser.close_tab"}]"#) == .closeTab(nil))
        #expect(command(#"[ACTION:{"type":"browser.close_tab","title":"Docs"}]"#) == .closeTab(.title("Docs")))
        #expect(command(#"[ACTION:{"type":"browser.close_tab","title":"  "}]"#) == nil)
    }

    @Test func extractParsesWithClampedLimit() {
        #expect(command(#"[ACTION:{"type":"browser.extract"}]"#) == .extract(limit: PageText.defaultExtractLimit))
        #expect(command(#"[ACTION:{"type":"browser.extract","limit":3000}]"#) == .extract(limit: 3000))
        #expect(command(#"[ACTION:{"type":"browser.extract","limit":5}]"#) == .extract(limit: 200))
        #expect(command(#"[ACTION:{"type":"browser.extract","limit":1000000}]"#) == .extract(limit: 20_000))
    }

    static let everyCommand: [BrowserCommand] = [
        .clickIndex(index: 3, state: "a1b2c3"),
        .clickIndex(index: 1, state: nil),
        .typeIndex(index: 4, text: "say \"hi\" [now]", submit: true, state: "a1b2c3"),
        .selectOption(index: 7, option: "Large", state: nil),
        .scroll(.up(pages: 1.5), state: nil),
        .scroll(.down(pages: 1), state: nil),
        .scroll(.toElement(index: 20), state: "a1b2c3"),
        .back,
        .forward,
        .switchTab(.id(42)),
        .switchTab(.title("Inbox")),
        .closeTab(nil),
        .closeTab(.title("Docs")),
        .extract(limit: 4_000),
    ]

    @Test(arguments: everyCommand)
    func serializedTagParsesBack(_ original: BrowserCommand) {
        let tag = original.action.tagText
        #expect(tag.hasPrefix("[ACTION:{") && tag.hasSuffix("}]"))
        let result = ZeusTagParser.parse(tag + " On it.")
        #expect(result.spokenText == "On it.")
        guard case .action(let action)? = result.tags.first else {
            Issue.record("no action in \(tag)")
            return
        }
        #expect(action.kind == original.action.kind)
        #expect(BrowserCommand(action) == original)
        #expect(ZeusTag.action(action).tagText == tag)
    }

    @Test func everyNewKindHasACommand() {
        let indexed: [ZeusAction.Kind] = [
            .browserClickIndex, .browserTypeIndex, .browserSelect, .browserScroll, .browserBack,
            .browserForward, .browserSwitchTab, .browserCloseTab, .browserExtract,
        ]
        #expect(Set(Self.everyCommand.map(\.action.kind)) == Set(indexed))
        #expect(BrowserCommand(ZeusAction(kind: .browserClick, payload: ["text": .string("Go")])) == nil)
    }

    @Test func serializationIsStable() {
        #expect(BrowserCommand.back.action.tagText == #"[ACTION:{"type":"browser.back"}]"#)
        #expect(BrowserCommand.clickIndex(index: 12, state: "k3").action.tagText
            == #"[ACTION:{"index":12,"state":"k3","type":"browser.click_index"}]"#)
        #expect(BrowserCommand.switchTab(.title("a/b")).action.tagText
            == #"[ACTION:{"title":"a/b","type":"browser.switch_tab"}]"#)
    }

    @Test func pointAndHighlightSerializeAndParseBack() {
        let tags: [ZeusTag] = [
            .point(nil),
            .point(PointTarget(x: 640, y: 320, label: "export button", screen: 2)),
            .point(PointTarget(x: 1, y: 2)),
            .highlight(HighlightTarget(x: 10, y: 20, width: 300, height: 40, label: "toolbar")),
        ]
        for tag in tags {
            #expect(ZeusTagParser.parse(tag.tagText + " here").tags == [tag])
        }
    }

    @Test func bridgeRequestsAndConsent() {
        let click = BrowserCommand.clickIndex(index: 3, state: "s1")
        #expect(click.bridgeType == "page.click_index")
        #expect(click.bridgeParams == ["index": .number(3), "state": .string("s1")])
        #expect(BrowserCommand.scroll(.down(pages: 1), state: nil).bridgeParams
            == ["direction": .string("down"), "pages": .number(1)])
        #expect(BrowserCommand.closeTab(.id(9)).bridgeParams == ["tabId": .number(9)])

        // Changing a page asks per site; scrolling, switching tabs and reading don't change one.
        #expect(Self.everyCommand.filter(\.changesPage).map(\.bridgeType).sorted() == [
            "page.click_index", "page.click_index", "page.select", "page.type_index",
            "tab.back", "tab.close", "tab.close", "tab.forward",
        ])
        #expect(click.summary(label: "Sign in") == "Click “Sign in”")
        #expect(click.summary(label: nil) == "Click item 3")
        #expect(BrowserCommand.typeIndex(index: 2, text: "hi", submit: true, state: nil).summary(label: "Search")
            == "Type “hi” into “Search” and submit")
    }
}

@Suite struct BrowserBridgeErrorTests {
    @Test func staleIndexMapsToAFreshLookMessage() throws {
        let json = Data(#"{"id":"7","ok":false,"error":{"code":"stale_elements","message":"Element 4 is from an older view of this page (the page navigated)."}}"#.utf8)
        let response = try JSONDecoder().decode(BridgeResponse.self, from: json)
        let error = try #require(response.error)
        #expect(error.code == BridgeError.staleElements)
        #expect(error.spokenMessage.contains("page changed since I looked"))
        #expect(error.spokenMessage.contains("didn't touch anything"))
    }

    @Test func otherErrorsKeepTheExtensionsMessage() {
        #expect(BridgeError(code: "sensitive_field", message: "Please type it yourself.").spokenMessage == "Please type it yourself.")
        #expect(BridgeError(code: "not_found").spokenMessage == "not_found")
        #expect(BridgeError(code: BridgeError.noHistory).spokenMessage == "There's no page to go to in that direction.")
    }
}

@Suite struct PageExtractTests {
    @Test func shortTextIsUntouched() {
        #expect(PageText.truncate("Hello world", to: 50) == "Hello world")
        #expect(PageText.truncate("exactly", to: 7) == "exactly")
    }

    @Test func longTextIsCutAtAWordBreak() {
        let text = String(repeating: "alpha beta gamma ", count: 100)
        let cut = PageText.truncate(text, to: 100)
        #expect(cut.count <= 100)
        #expect(cut.count >= 80)
        #expect(cut.hasSuffix("…"))
        let words = cut.dropLast().split(separator: " ")
        #expect(words.allSatisfy { ["alpha", "beta", "gamma"].contains(String($0)) })
    }

    @Test func textWithoutBreaksIsCutHard() {
        let cut = PageText.truncate(String(repeating: "x", count: 500), to: 200)
        #expect(cut == String(repeating: "x", count: 199) + "…")
    }

    @Test func tinyLimits() {
        #expect(PageText.truncate("abc", to: 0) == "")
        #expect(PageText.truncate("abc", to: 1) == "…")
    }

    @Test func extractedTextAndElementsReachTheTab() throws {
        let json = Data(#"{"url":"https://example.com","title":"Example","elementsState":"s1","elements":[{"index":1,"role":"link","text":"Pricing","href":"/pricing","inViewport":true},{"index":2,"role":"select","text":"Size","inViewport":false,"options":["S","M"]}]}"#.utf8)
        let tab = try JSONDecoder().decode(TabContext.self, from: json)
        #expect(tab.elements?.count == 2)
        #expect(tab.elements?[0].promptLine == #"[1] link "Pricing" -> /pricing"#)
        #expect(tab.elements?[1].promptLine == #"[2] select "Size" options: S | M (off screen)"#)
        #expect(tab.with(extract: "Main text").extract == "Main text")
        #expect(tab.with(extract: "Main text").elements == tab.elements)
    }
}
