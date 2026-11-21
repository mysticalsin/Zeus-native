import Foundation
import Testing
@testable import ZeusCore

/// The desktop card used to read com.apple.dock for autohide and orientation.
/// NSScreen frames are the public source. A showing Dock is already outside the visible frame.
@Suite("Dock clearance")
struct DockClearanceTests {
    private let frame = DockClearanceRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func aShowingBottomDockAddsOnlyTheMenuBar() {
        let visible = DockClearanceRect(x: 0, y: 80, width: 1440, height: 780)
        #expect(DockClearance.reserved(frame: frame, visible: visible) == [
            DockClearanceRect(x: 0, y: 860, width: 1440, height: 40),
        ])
    }

    @Test func aShowingLeftOrRightDockAddsOnlyTheMenuBar() {
        let left = DockClearanceRect(x: 70, y: 0, width: 1370, height: 860)
        let right = DockClearanceRect(x: 0, y: 0, width: 1370, height: 860)
        #expect(DockClearance.reserved(frame: frame, visible: left).count == 1)
        #expect(DockClearance.reserved(frame: frame, visible: right).count == 1)
    }

    /// One point of difference is frame noise. Two points is a showing Dock.
    /// Changing the comparison from +1 to +2 still passes the large insets above.
    @Test func onePointOfFrameSlopIsNotADockAndTwoPointsIs() {
        let bottomNoise = DockClearanceRect(x: 0, y: 1, width: 1440, height: 859)
        let leftNoise = DockClearanceRect(x: 1, y: 0, width: 1439, height: 860)
        let rightNoise = DockClearanceRect(x: 0, y: 0, width: 1439, height: 860)
        #expect(DockClearance.reserved(frame: frame, visible: bottomNoise).count == 4)
        #expect(DockClearance.reserved(frame: frame, visible: leftNoise).count == 4)
        #expect(DockClearance.reserved(frame: frame, visible: rightNoise).count == 4)

        let menuBar = DockClearanceRect(x: 0, y: 860, width: 1440, height: 40)
        let bottom = DockClearanceRect(x: 0, y: 2, width: 1440, height: 858)
        let left = DockClearanceRect(x: 2, y: 0, width: 1438, height: 860)
        let right = DockClearanceRect(x: 0, y: 0, width: 1438, height: 860)
        #expect(DockClearance.reserved(frame: frame, visible: bottom) == [menuBar])
        #expect(DockClearance.reserved(frame: frame, visible: left) == [menuBar])
        #expect(DockClearance.reserved(frame: frame, visible: right) == [menuBar])
    }

    @Test func screenGeometryUsesTheVisibleFrameAndTheDockBands() throws {
        let frame = DockClearanceRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = DockClearanceRect(x: 0, y: 80, width: 1440, height: 780)
        let placed = DockClearance.geometry(frame: frame, visible: visible)
        #expect(placed.usable == ExplanationRect(x: 0, y: 80, width: 1440, height: 780))
        #expect(placed.reserved == [ExplanationRect(x: 0, y: 860, width: 1440, height: 40)])
        let source = try String(contentsOf: desktopCardSource, encoding: .utf8)
        let body = try #require(functionBody("screenGeometry", in: source))
        #expect(body.contains("DockClearance.geometry"))
    }

    @Test func aHiddenDockReservesTheThreeEdgesTheFramesDoNotName() {
        let visible = DockClearanceRect(x: 0, y: 0, width: 1440, height: 860)
        #expect(DockClearance.reserved(frame: frame, visible: visible) == [
            DockClearanceRect(x: 0, y: 860, width: 1440, height: 40),
            DockClearanceRect(x: 0, y: 0, width: 96, height: 900),
            DockClearanceRect(x: 1344, y: 0, width: 96, height: 900),
            DockClearanceRect(x: 0, y: 0, width: 1440, height: 96),
        ])
    }

    private var desktopCardSource: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zeus/Explanation/ExplanationDesktopCard.swift")
    }

    private func functionBody(_ name: String, in source: String) -> String? {
        guard let signature = source.range(of: "func \(name)") else { return nil }
        guard let open = source[signature.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[open...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
