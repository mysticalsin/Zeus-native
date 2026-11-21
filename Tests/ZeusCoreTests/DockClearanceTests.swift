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

    @Test func aHiddenDockReservesTheThreeEdgesTheFramesDoNotName() {
        let visible = DockClearanceRect(x: 0, y: 0, width: 1440, height: 860)
        #expect(DockClearance.reserved(frame: frame, visible: visible) == [
            DockClearanceRect(x: 0, y: 860, width: 1440, height: 40),
            DockClearanceRect(x: 0, y: 0, width: 96, height: 900),
            DockClearanceRect(x: 1344, y: 0, width: 96, height: 900),
            DockClearanceRect(x: 0, y: 0, width: 1440, height: 96),
        ])
    }
}
