import Testing
@testable import ZeusCore

@Suite("Top bar position")
struct TopBarPositionTests {
    @Test func noDropUntilTheOwnerMovesTheSlider() {
        #expect(TopBarPosition.resolved(chosen: nil) == 0)
        #expect(TopBarPosition.applied(resolved: TopBarPosition.resolved(chosen: nil), panelOpen: false) == 0)
    }

    @Test func aChosenValueWinsAndIsClamped() {
        #expect(TopBarPosition.resolved(chosen: 0) == 0)
        #expect(TopBarPosition.resolved(chosen: 16) == 16)
        #expect(TopBarPosition.resolved(chosen: 99) == 24)
        #expect(TopBarPosition.resolved(chosen: -5) == 0)
        #expect(TopBarPosition.resolved(chosen: 7) == 8)
        #expect(TopBarPosition.resolved(chosen: .infinity) == 0)
        #expect(TopBarPosition.resolved(chosen: .nan) == 0)
    }

    @Test func theOpenPanelNeverDrops() {
        #expect(TopBarPosition.applied(resolved: 12, panelOpen: true) == 0)
        #expect(TopBarPosition.applied(resolved: 12, panelOpen: false) == 12)
        #expect(TopBarPosition.applied(resolved: 60, panelOpen: false) == 24)
    }
}

@Suite("Screen edge outline")
struct ScreenEdgeOutlineTests {
    @Test func hugsThePhysicalScreenEdge() {
        let outline = ScreenEdgeOutline(width: 1512, height: 982)
        #expect(outline.centerX == 756)
        #expect(outline.top == ScreenEdgeOutline.defaultInset)
        #expect(outline.right == 1512 - ScreenEdgeOutline.defaultInset)
        #expect(outline.bottom == 982 - ScreenEdgeOutline.defaultInset)
        #expect(outline.radius == ScreenEdgeOutline.defaultRadius)
    }

    @Test func theCornerFitsTinyAndBadSizes() {
        let tiny = ScreenEdgeOutline(width: 10, height: 10)
        #expect(tiny.radius <= tiny.right - tiny.centerX)
        #expect(tiny.radius <= (tiny.bottom - tiny.top) / 2)
        let bad = ScreenEdgeOutline(width: .nan, height: -4)
        #expect(bad.radius == 0)
        #expect(bad.right >= bad.centerX)
        #expect(bad.bottom >= bad.top)
    }
}
