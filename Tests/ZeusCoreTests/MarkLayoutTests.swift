import Foundation
import Testing
@testable import ZeusCore

@Suite struct MarkLayoutTests {
    private func screen(_ id: String, _ frame: CGRect) -> MarkScreen {
        MarkScreen(id: id, frame: frame)
    }

    @Test func marksRebuildOnScreenParameterChange() {
        var screens = [
            screen("main", CGRect(x: 0, y: 0, width: 200, height: 100)),
            screen("side", CGRect(x: 200, y: 0, width: 100, height: 80)),
        ]
        let layout = MarkLayout { screens }
        let marks = [
            MarkPin(number: 1, title: "Save", point: CGPoint(x: 20, y: 40)),
            MarkPin(number: 2, title: "Close", point: CGPoint(x: 220, y: 30)),
        ]
        let before = layout.place(marks)
        #expect(before.map(\.screenID) == ["main", "side"])

        screens = [
            screen("main", CGRect(x: 0, y: 0, width: 200, height: 100)),
            screen("extra", CGRect(x: 400, y: 0, width: 100, height: 90)),
        ]
        let after = layout.place(marks + [MarkPin(number: 3, title: "New", point: CGPoint(x: 420, y: 20))])
        #expect(after.map(\.screenID) == ["main", "extra"])
        #expect(!after.contains { $0.screenID == "side" })
        #expect(after.map(\.title) == ["Save", "New"])
    }

    @Test func aMarkOnARemovedDisplayIsDropped() {
        var screens = [screen("gone", CGRect(x: 0, y: 0, width: 100, height: 100))]
        let layout = MarkLayout { screens }
        let mark = MarkPin(number: 1, title: "Only", point: CGPoint(x: 10, y: 10))
        #expect(layout.place([mark]).count == 1)
        screens = []
        #expect(layout.place([mark]).isEmpty)
    }

    @Test func coordinatesFlipPerScreenNotPerKeyWindow() {
        let short = screen("short", CGRect(x: 0, y: 0, width: 100, height: 50))
        let tall = screen("tall", CGRect(x: 200, y: 0, width: 100, height: 180))
        let layout = MarkLayout { [short, tall] }
        let onShort = layout.place([MarkPin(number: 1, title: "Low", point: CGPoint(x: 10, y: 40))])[0]
        let onTall = layout.place([MarkPin(number: 2, title: "High", point: CGPoint(x: 210, y: 40))])[0]
        #expect(onShort.local == CGPoint(x: 10, y: 10))
        #expect(onTall.local == CGPoint(x: 10, y: 140))
        #expect(onShort.local.y != 180 - 40)
    }

    @Test func eachMarkExposesAnAccessibilityLabel() {
        let layout = MarkLayout { [screen("main", CGRect(x: 0, y: 0, width: 100, height: 100))] }
        let placed = layout.place([
            MarkPin(number: 1, title: "Save", point: CGPoint(x: 5, y: 5)),
            MarkPin(number: 2, title: "Close", point: CGPoint(x: 8, y: 8)),
        ])
        #expect(placed.map(\.accessibilityLabel) == ["Mark 1, Save", "Mark 2, Close"])
    }

    @Test func aDisplayLeftOfOrBelowThePrimaryIsKept() {
        let primary = screen("primary", CGRect(x: 0, y: 0, width: 100, height: 100))
        let left = screen("left", CGRect(x: -120, y: 0, width: 100, height: 100))
        let below = screen("below", CGRect(x: 0, y: -90, width: 100, height: 80))
        let layout = MarkLayout { [primary, left, below] }
        let placed = layout.place([
            MarkPin(number: 1, title: "Left", point: CGPoint(x: -30, y: 40)),
            MarkPin(number: 2, title: "Below", point: CGPoint(x: 10, y: -20)),
        ])
        #expect(placed.map(\.screenID) == ["left", "below"])
        #expect(placed.map(\.local) == [CGPoint(x: 90, y: 60), CGPoint(x: 10, y: 10)])
    }

    @Test func aPointOnTheSharedEdgeBelongsToTheMinimumEdge() {
        let left = screen("left", CGRect(x: 0, y: 0, width: 100, height: 100))
        let right = screen("right", CGRect(x: 100, y: 0, width: 100, height: 100))
        let layout = MarkLayout { [left, right] }
        let placed = layout.place([MarkPin(number: 1, title: "Edge", point: CGPoint(x: 100, y: 40))])
        #expect(placed.map(\.screenID) == ["right"])
        #expect(placed.map(\.local) == [CGPoint(x: 0, y: 60)])
    }

    @Test func aVerticallyStackedDisplayUsesItsOwnMinY() {
        let bottom = screen("bottom", CGRect(x: 0, y: 0, width: 200, height: 100))
        let top = screen("top", CGRect(x: 0, y: 100, width: 200, height: 80))
        let layout = MarkLayout { [bottom, top] }
        let placed = layout.place([
            MarkPin(number: 1, title: "Low", point: CGPoint(x: 30, y: 20)),
            MarkPin(number: 2, title: "High", point: CGPoint(x: 30, y: 140)),
        ])
        #expect(placed.map(\.screenID) == ["bottom", "top"])
        #expect(placed.map(\.local) == [CGPoint(x: 30, y: 80), CGPoint(x: 30, y: 40)])
    }

    @Test func overlappingScreensKeepTheFirstMatch() {
        let first = screen("first", CGRect(x: 0, y: 0, width: 100, height: 100))
        let last = screen("last", CGRect(x: 50, y: 0, width: 100, height: 100))
        let layout = MarkLayout { [first, last] }
        let placed = layout.place([MarkPin(number: 1, title: "Overlap", point: CGPoint(x: 60, y: 40))])
        #expect(placed.map(\.screenID) == ["first"])
        #expect(placed.map(\.local) == [CGPoint(x: 60, y: 60)])
    }

    @Test func mixedBackingScalesPlaceInPoints() {
        // 1x is 1440×900 points. The 2x display beside it is 756×491 points (1512×982 pixels).
        let oneX = screen("1x", CGRect(x: 0, y: 0, width: 1440, height: 900))
        let twoX = screen("2x", CGRect(x: 1440, y: 0, width: 756, height: 491))
        let layout = MarkLayout { [oneX, twoX] }
        let placed = layout.place([
            MarkPin(number: 1, title: "One", point: CGPoint(x: 20, y: 30)),
            MarkPin(number: 2, title: "Two", point: CGPoint(x: 1540, y: 40)),
        ])
        #expect(placed.map(\.screenID) == ["1x", "2x"])
        #expect(placed.map(\.local) == [CGPoint(x: 20, y: 870), CGPoint(x: 100, y: 451)])
    }

    @Test func aPointOnTheOuterEdgeIsPlaced() {
        let only = screen("only", CGRect(x: 0, y: 0, width: 100, height: 80))
        let layout = MarkLayout { [only] }
        let placed = layout.place([
            MarkPin(number: 1, title: "Right", point: CGPoint(x: 100, y: 20)),
            MarkPin(number: 2, title: "Top", point: CGPoint(x: 40, y: 80)),
        ])
        #expect(placed.map(\.local) == [CGPoint(x: 100, y: 60), CGPoint(x: 40, y: 0)])
    }

    @Test func aPointOnTheMinCornerAndTheMaxCornerIsPlaced() {
        let side = screen("side", CGRect(x: -120, y: -40, width: 100, height: 80))
        let layout = MarkLayout { [side] }
        let placed = layout.place([
            MarkPin(number: 1, title: "Min", point: CGPoint(x: -120, y: -40)),
            MarkPin(number: 2, title: "Max", point: CGPoint(x: -20, y: 40)),
        ])
        #expect(placed.map(\.screenID) == ["side", "side"])
        #expect(placed.map(\.local) == [CGPoint(x: 0, y: 80), CGPoint(x: 100, y: 0)])
    }
}
