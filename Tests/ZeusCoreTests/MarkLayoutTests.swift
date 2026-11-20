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
}
