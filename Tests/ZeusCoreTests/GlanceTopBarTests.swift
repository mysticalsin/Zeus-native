import CoreGraphics
import Testing
@testable import ZeusCore

/// Numbers from teardown/glance-live/TOPBAR-SPEC.md.
@Suite("Glance top bar")
struct GlanceTopBarTests {
    @Test func windowIsFullWidthBy470AtLayer25() {
        let frame = GlanceTopBar.windowFrame(screen: CGRect(x: 0, y: 0, width: 1728, height: 1117))
        #expect(frame == CGRect(x: 0, y: 647, width: 1728, height: 470))  // top flush, y 0 in screen terms
        #expect(GlanceTopBar.windowLayer == 25)
        #expect(GlanceTopBar.closedSize == CGSize(width: 185, height: 32))
        #expect(Double(GlanceTopBar.closedBottomRadius) == 6)
        // The tallest page (with no approval) fits inside the window.
        #expect(GlanceTopBar.bodyHeight(home: false) <= GlanceTopBar.windowHeight)
    }

    @Test func openHomeIs870By210WithEars() {
        let size = GlanceTopBar.panelSize(home: true)
        #expect(Double(size.width) == 925)          // 870 body + two 27.5 ears
        #expect(Double(size.height) == 210)
        #expect(Double(GlanceTopBar.bodyHeight(home: false)) == 332)
    }

    @Test func fourEqualCards() {
        let cards = GlanceTopBar.cardFrames()
        #expect(cards.count == 4)
        #expect(abs(Double(cards[0].width) - 200.625) < 0.01)  // spec 201 within 1 pt
        #expect(Double(cards[0].minX) == 18)
        #expect(abs(Double(cards[3].maxX) - 852) < 0.01)        // 18 from the right edge
        #expect(Double(cards[0].minY) == 82 && Double(cards[0].height) == 114)
        #expect(abs(Double(cards[1].minX - cards[0].maxX) - 10.5) < 0.01)
    }

    @Test func tabCapsuleMatchesTheLivePair() {
        // Measured live (parity/N4): 411 wide with Home selected, Clipboard "39" (+15.5) and Shelf "7" (+9),
        // at 14 pt between tabs. Zeus uses 12 pt so thirteen tabs fit: 2 pt less for each of the 6 gaps.
        #expect(abs(Double(GlanceTopBar.capsuleWidth(tabs: 7, countsExtra: 24.5)) - (411 - 6 * 2)) <= 1)
        #expect(GlanceTopBar.capsuleWidth(tabs: 0) == 0)
        // Top 38, 34 tall (centre 55), and the cards still start at 82.
        #expect(Double(GlanceTopBar.tabRowTop) == 38 && Double(GlanceTopBar.tabRowTop + GlanceTopBar.tabRowHeight / 2) == 55)
        #expect(Double(GlanceTopBar.cardTop) == 82)
    }

    @Test func rowKeepsThirteenAndTheSelectedTab() {
        let tabs = Array(1...14)
        #expect(GlanceTopBar.maxTabs == 13)
        #expect(GlanceTabRow.visible(tabs, selected: 3) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
        #expect(GlanceTabRow.visible(tabs, selected: 14) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14])
        #expect(GlanceTabRow.visible(tabs, selected: 11, max: 7) == [1, 2, 3, 4, 5, 6, 11])
        #expect(GlanceTabRow.visible([1, 2, 3], selected: 2) == [1, 2, 3])
    }

    /// Thirteen tabs fit beside the more circle even with the widest selected label and three big counts.
    @Test func thirteenTabsFitTheRow() {
        #expect(Double(GlanceTopBar.rowRoom) == 803)
        let widest = TopBarLayout.defaultRow.map { GlanceTopBar.selectedPillWidth(title: $0.title, countWidth: 26) }.max() ?? 0
        let counts: CGFloat = 3 * 26 // "99+" beside Alerts, Clipboard and Shelf
        let worst = GlanceTopBar.capsuleWidth(tabs: 13, countsExtra: counts + widest - GlanceTopBar.selectedPill.width)
        #expect(worst < GlanceTopBar.rowRoom)
        // 13 plain slots: 2 x 5.5 + 82 + 12 x 47 (13 pt icon, 11 pt padding either side, 12 pt apart).
        #expect(Double(GlanceTopBar.capsuleWidth(tabs: 13)) == 657)
        #expect(GlanceTopBar.selectedPillWidth(title: "Home") == GlanceTopBar.selectedPill.width)
    }

    @Test func glanceSevenComeFirst() {
        // The default row starts with Home and Agents, then the other six of the seven in their order.
        #expect(Array(TopBarLayout.standard.tabs.prefix(8)) == [TopBarTab.home, .agents] + Array(TopBarLayout.glanceSeven.dropFirst()))
        let saved = TopBarLayout(tabs: [.home, .today, .agents, .music, .clipboard, .usage, .chat])
        #expect(saved.glanceOrdered().tabs == [.home, .chat, .clipboard, .today, .agents, .music, .usage])
        // Nothing turned on that was off.
        #expect(!saved.glanceOrdered().contains(.dictation))
    }

    @Test func hoverZoneIsTheHardwareNotch() {
        let zone = GlanceTopBar.hoverZone(screen: CGRect(x: 0, y: 0, width: 1728, height: 1117), notch: CGSize(width: 185, height: 32))
        #expect(Double(zone.width) == 185)
        #expect(Double(zone.midX) == 864)
        #expect(Double(zone.maxY) == 1117 && Double(zone.height) == 31)
    }

    @Test func hoverMatchesGlancesProbedPoints() {
        // Probed live (top-left points): opens at x 772 / 956 and y 30; not at x 768 / 960 or y 31.
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let notch = CGSize(width: 185, height: 32)
        func opens(_ x: CGFloat, _ top: CGFloat) -> Bool {
            GlanceTopBar.inHoverZone(CGPoint(x: x, y: 1117 - top), screen: screen, notch: notch)
        }
        #expect(opens(864, 0) && opens(864, 7) && opens(772, 7) && opens(956, 7) && opens(864, 30))
        #expect(!opens(768, 7) && !opens(960, 7) && !opens(864, 31) && !opens(744, 7))
    }

    @Test func openPanelTakesTheMouseOnlyOverItsShape() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let size = GlanceTopBar.panelSize(home: true)   // 925 x 210 with the ears
        func on(_ x: CGFloat, _ top: CGFloat) -> Bool {
            GlanceTopBar.openShapeContains(CGPoint(x: x, y: 1117 - top), screen: screen, size: size)
        }
        #expect(on(864, 100) && on(430, 100) && on(1298, 100))   // body, both sides
        #expect(!on(425, 100) && !on(1303, 100))                  // just outside the body
        #expect(on(415, 1) && !on(415, 20))                       // the ear flares only near the top
        #expect(!on(864, 211) && !on(430, 209))                   // below, and the rounded corner
        #expect(on(451, 205))                                     // inside the corner curve
    }

    @Test func openFollowsGlancesMeasuredCurve() {
        let spring = GlanceTopBar.openSpring
        let body = 870.0, closed = Double(GlanceTopBar.closedSize.width)
        var squares = 0.0
        for sample in GlanceTopBar.measuredOpen {
            let t = sample.ms / 1000 + GlanceTopBar.measuredOpenOffset
            let model = body - (body - closed) * GlanceTopBar.springRemaining(at: t, response: spring.response, damping: spring.damping)
            squares += (model - sample.width) * (model - sample.width)
        }
        let rms = (squares / Double(GlanceTopBar.measuredOpen.count)).squareRoot()
        #expect(rms < 15, "rms \(rms) pt from Glance")
        // Like Glance, at most a few points past the 870 pt body (not visible as a bounce).
        let lowest = (0...600).map { GlanceTopBar.springRemaining(at: Double($0) / 600, response: spring.response, damping: spring.damping) }.min()!
        #expect(-lowest * (body - closed) < 3)
    }

    @Test func closeIsFourFramesAfterHalfASecond() {
        // Glance (parity/N8): down to a strip about 6 frames at 60 fps after it starts, about 0.53 s
        // after the pointer leaves.
        #expect(abs(GlanceTopBar.closeDuration * 60 - 6) <= 1)
        #expect(abs(GlanceTopBar.closeDelay - 0.53) <= 0.05)
        // The open height leads the width: further along at every early moment.
        for ms in stride(from: 17.0, through: 100, by: 17) {
            let height = GlanceTopBar.springRemaining(at: ms / 1000, response: GlanceTopBar.openHeightSpring.response, damping: GlanceTopBar.openHeightSpring.damping)
            let width = GlanceTopBar.springRemaining(at: ms / 1000, response: GlanceTopBar.openSpring.response, damping: GlanceTopBar.openSpring.damping)
            #expect(height < width)
        }
    }

    @Test func bloomRimIs8To10AndGoneBy400Ms() {
        #expect(GlanceTopBar.bloomRim >= 8 && GlanceTopBar.bloomRim <= 10)
        #expect(GlanceTopBar.bloomDuration <= 0.4)
    }
}
