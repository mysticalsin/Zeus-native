import Testing
@testable import ZeusCore

struct SeparateBrowserDrawTests {
    private func cards(_ plan: SeparateBrowserDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func anUncheckedInstallMayOpenAnySite() {
        let usual = SeparateBrowserDraw.plan(uv: "Not checked", package: "Not checked", browser: "Not checked", sites: "Any")
        #expect(cards(usual) == ["Separate", "uv: Not checked", "Package: Not checked", "Chromium: Not checked", "Sites: Any"])
        #expect(SeparateBrowserAsk.line(uv: "Not checked", package: "Not checked", browser: "Not checked", sites: "Any") == "uv is not checked, browser-use is not checked, Chromium is not checked, and the separate browser may open any site.")
        #expect(usual.boltCaption(at: 0) == "Separate")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Sites: Any")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(SeparateBrowserAsk.siteCount(" example.com, wikipedia.org ") == 2)
        #expect(SeparateBrowserAsk.siteCount("") == 0)
        #expect(SeparateBrowserAsk.line(uv: "Ready", package: "Missing", browser: "Ready", sites: "2") == "uv is ready, browser-use is missing, Chromium is ready, and the separate browser is limited to 2 sites.")
        #expect(cards(SeparateBrowserDraw.plan(uv: "Ready", package: "Ready", browser: "Ready", sites: "1")) == ["Separate", "uv: Ready", "Package: Ready", "Chromium: Ready", "Sites: 1"])
        #expect(cards(SeparateBrowserDraw.plan(uv: "Ready", package: "Ready", browser: "Ready", sites: "0")) == ["Separate", "Can't"])
        #expect(SeparateBrowserAsk.line(uv: "Ready", package: "Ready", browser: "Ready", sites: "example.com") == "I can't read the separate browser.")
    }

    @Test func theChromeChoiceStaysOffThisAsk() {
        #expect(SeparateBrowserAsk.matches("how is the separate browser set"))
        #expect(SeparateBrowserAsk.matches("Hey Zeus, is uv ready?"))
        #expect(SeparateBrowserAsk.matches("separate browser settings"))
        #expect(!SeparateBrowserAsk.matches("how is the browser agent set"))
        #expect(!SeparateBrowserAsk.matches("what always asks"))
        #expect(!SeparateBrowserAsk.matches("which apps does tiling leave out"))
        #expect(!SeparateBrowserAsk.matches("how is the admin rule set"))
    }
}
