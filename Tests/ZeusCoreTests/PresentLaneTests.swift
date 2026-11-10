import CoreGraphics
import Foundation
import Testing
import ZeusCore

@Suite("L7 screen awareness")
struct ScreenAwarenessTests {
    @Test func detectsScreenQuestions() {
        #expect(ScreenAwareness.isScreenQuestion("Hey, what's on my screen?"))
        #expect(ScreenAwareness.isScreenQuestion("what am I looking at"))
        #expect(!ScreenAwareness.isScreenQuestion("open calculator"))
    }

    @Test func textFirstWhenAxIsEnough() {
        let ax = String(repeating: "Notes window with groceries list. ", count: 20)
        let plan = ScreenAwareness.plan(transcript: "what's on my screen", axSummary: ax, tab: nil)
        #expect(plan.needsCapture)
        #expect(!plan.preferPixels)
        #expect(plan.axTokenEstimate > 10)
        #expect(plan.promptPrefix.contains("axTokens="))
    }

    @Test func prefersPixelsForExplainThis() {
        let plan = ScreenAwareness.plan(transcript: "explain this", axSummary: "short", tab: nil)
        #expect(plan.preferPixels)
    }

    /// Page-text turns must not get screen-awareness prefix (VoiceTurnController merge guard).
    @Test func pageTextTurnSkipsScreenAwarenessPrefix() {
        let ax = String(repeating: "Notes window with groceries list. ", count: 20)
        let plan = ScreenAwareness.plan(transcript: "summarize this page", axSummary: ax, tab: nil)
        let pageText = true
        var system = "core"
        if pageText {
            system += "\n\nAnswer from the page text you were given. Do not use a screenshot."
        } else if !plan.promptPrefix.isEmpty {
            system += "\n\n" + plan.promptPrefix
        }
        #expect(!system.contains("axTokens="))
        #expect(system.contains("page text"))
    }

    /// B2 and lane E both extend the LLM system prompt; merges must keep screen awareness and memory.
    @Test func screenAwarenessPrefixCombinesWithMemoryBlock() {
        let ax = String(repeating: "Notes window with groceries list. ", count: 20)
        let plan = ScreenAwareness.plan(transcript: "what's on my screen", axSummary: ax, tab: nil)
        let store = UserMemoryStore(rules: [.init(text: "Prefer metric units")])
        let memory = store.promptBlock(for: "what's on my screen")
        var system = "core"
        if !plan.promptPrefix.isEmpty { system += "\n\n" + plan.promptPrefix }
        if !memory.isEmpty { system += "\n\n" + memory }
        #expect(system.contains("axTokens="))
        #expect(system.localizedCaseInsensitiveContains("metric"))
        _ = store
    }
}

@Suite("L4 guided present")
struct GuidedPresentTests {
    @Test func clickMustLandInsideTolerance() {
        let shot = ScreenShot(jpegData: Data(), label: "screen 1", pixelWidth: 1280, pixelHeight: 720,
                              displayFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let target = GuidedPresent.ResolvedTarget(
            screenPoint: CGPoint(x: 500, y: 400), label: "Save", waitForClick: true,
            hitRect: CGRect(x: 476, y: 376, width: 48, height: 48))
        #expect(GuidedPresent.clickHits(CGPoint(x: 500, y: 400), target: target))
        #expect(!GuidedPresent.clickHits(CGPoint(x: 600, y: 400), target: target))
        _ = shot
    }

    @Test func walkthroughWaitFlagParses() {
        let json = #"{"type":"mac.walkthrough","title":"T","steps":[{"say":"Tap Share","target":"Share","wait":true,"x":10,"y":20}]}"#
        guard case .action(let action)? = ZeusTagParser.parse("[ACTION:\(json)]").tags.first else {
            Issue.record("no action"); return
        }
        guard let tour = Walkthrough.parse(action.payload) else {
            Issue.record("no tour"); return
        }
        #expect(tour.steps[0].waitForClick)
        #expect(tour.steps[0].targetLabel == "Share")
    }

    @Test func presentCardParses() {
        let json = #"{"type":"present.card","kind":"steps","title":"Export","lines":["Open File","Pick format"]}"#
        guard case .action(let action)? = ZeusTagParser.parse("[ACTION:\(json)]").tags.first else {
            Issue.record("no action"); return
        }
        guard let card = PresentCard.parse(action.payload) else {
            Issue.record("no card"); return
        }
        #expect(card.kind == PresentCard.Kind.steps && card.title == "Export")
        #expect(card.lines.count == 2)
    }
}

@Suite("L6 present regression")
struct L6PresentTests {
    @Test func ringToleranceAt1080And4K() {
        #expect(PresentTolerance.ringPoints(scale: 1, pixelWidth: 1920) == 24)
        #expect(PresentTolerance.ringPoints(scale: 2, pixelWidth: 2560) == 24)
        #expect(PresentTolerance.ringPoints(scale: 1, pixelWidth: 3840) == 48)
    }

    @Test func mapperMapsScreenshotPixels() {
        let shot = ScreenShot(jpegData: Data(), label: "s", pixelWidth: 1280, pixelHeight: 720,
                              displayFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let point = PresentPointMapping.screenPoint(x: 640, y: 360, screen: 1, in: [shot])
        #expect(point != nil)
    }

    @Test func physicalPointerOffByDefault() {
        #expect(!PhysicalPointerSettings.enabled(storedValue: nil))
        #expect(!PhysicalPointerSettings.enabled(storedValue: false))
        #expect(PhysicalPointerSettings.enabled(storedValue: true))
    }
}
