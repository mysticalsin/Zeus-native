import AppKit
import QuartzCore
import Testing
import ZeusCore
@testable import Zeus

/// The buddy's window fades have explicit timing from the token table, and its display link follows its own screen.
@Suite("Buddy motion")
@MainActor
struct BuddyMotionTests {
    @Test func theWindowFadeInEasesOutAndTheFadeOutEasesIn() {
        let show = BuddyController.fadeTiming(showing: true)
        #expect(show.duration == MotionTokens.windowFadeInDuration)
        #expect(show.curve == .easeOut)
        let hide = BuddyController.fadeTiming(showing: false)
        #expect(hide.duration == MotionTokens.windowFadeOutDuration)
        #expect(hide.curve == .easeIn)
    }

    @Test func theDisplayLinkFollowsTheBuddyWindowsScreenNotJustTheMainOne() {
        #expect(BuddyController.linkScreen(window: 2, main: 1, all: [1, 2]) == 2)
        #expect(BuddyController.linkScreen(window: nil, main: 1, all: [1, 2]) == 1)
        #expect(BuddyController.linkScreen(window: nil, main: nil, all: [3, 2]) == 3)
        #expect(BuddyController.linkScreen(window: Int?.none, main: nil, all: []) == nil)
    }

    @Test func theLinkScreenIsTheOneWhereTheBuddyIsShown() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800), right = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        #expect(BuddyController.windowIndex(containing: CGPoint(x: 1500, y: 400), in: [left, right]) == 1)
        #expect(BuddyController.windowIndex(containing: CGPoint(x: 10, y: 10), in: [left, right]) == 0)
        #expect(BuddyController.windowIndex(containing: CGPoint(x: 5000, y: 10), in: [left, right]) == nil)
    }

    @Test func theLinkIsRecreatedWhenTheScreensChange() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Zeus/Overlay/BuddyController.swift"), encoding: .utf8)
        let screens = try #require(source.range(of: "@objc private func screensChanged()"))
        let rebuild = try #require(source.range(of: "private func rebuildWindows()"))
        let body = String(source[screens.upperBound..<rebuild.lowerBound])
        #expect(body.contains("startDisplayLink()"), "screensChanged must rebind the link")
        #expect(source.contains("displayLink?.invalidate()"))
    }

    @Test func theFadeUsesTheTimingFunctionAndTheLinkUsesTheWindowScreen() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Zeus/Overlay/BuddyController.swift"), encoding: .utf8)
        #expect(source.contains("$0.timingFunction = CAMediaTimingFunction(name: timing.curve)"))
        #expect(source.contains("$0.duration = timing.duration"))
        #expect(source.contains("Self.linkScreen(window: shownWindowScreen()"))
        #expect(!source.contains("(NSScreen.main ?? NSScreen.screens[0]).displayLink"))
    }
}
