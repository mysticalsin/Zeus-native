import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Own-process panels only: nothing is captured, shown to the user for long, or sent anywhere. With no display
/// attached (a headless runner) the overlays have no panel and the window checks hold vacuously, which is why
/// each test also asserts the policy that does not need a screen.
@MainActor
@Suite("Tiling overlay windows", .serialized)
struct TilingOverlayTests {
    private static let display = TileDisplay(
        id: 1, appKitFrame: TileRect(x: 0, y: 0, width: 1440, height: 900),
        appKitVisibleFrame: TileRect(x: 0, y: 0, width: 1440, height: 876),
        engineFrame: TileRect(x: 0, y: 0, width: 1440, height: 900))
    private static let target = TilingRingTarget(display: display, frame: TileRect(x: 8, y: 32, width: 708, height: 860))
    private static let rows = TileKeyList.rows(keymap: TileKeymap.defaults(base: .controlOption))

    private var expectedPanels: Int { NSScreen.screens.isEmpty ? 0 : 1 }

    // MARK: Focus ring

    @Test func theRingPanelNeverBecomesKeyOrMainAndIgnoresTheMouse() {
        let ring = TilingFocusBorder.shared
        ring.show(Self.target)
        defer { ring.hide() }
        for window in ring.ownedWindows {
            #expect(!window.canBecomeKey && !window.canBecomeMain)
            #expect(window.ignoresMouseEvents)
            #expect(window.styleMask.contains(.nonactivatingPanel) && window.styleMask.contains(.borderless))
            #expect(window.sharingType == .none)
            #expect(!window.isKeyWindow && !window.isMainWindow)
            #expect(!window.isOpaque && window.backgroundColor == .clear && !window.hasShadow)
            #expect(!window.isReleasedWhenClosed)
        }
        #expect(ring.ownedWindows.count == expectedPanels)
    }

    @Test func theRingJoinsEverySpaceAndSitsBelowTheNotchWindow() {
        let ring = TilingFocusBorder.shared
        ring.show(Self.target)
        defer { ring.hide() }
        for window in ring.ownedWindows {
            let behavior = window.collectionBehavior
            #expect(behavior.contains(.canJoinAllSpaces) && behavior.contains(.stationary))
            #expect(behavior.contains(.fullScreenAuxiliary) && behavior.contains(.ignoresCycle))
            #expect(window.level == .floating)
            #expect(window.level.rawValue < NSWindow.Level.statusBar.rawValue, "it never draws over the notch window")
        }
        #expect(TilingFocusBorder.level == .floating)
    }

    @Test func theRingSitsJustOutsideTheWindowItMarksInAppKitCoordinates() {
        let ring = TilingFocusBorder.shared
        ring.show(Self.target)
        defer { ring.hide() }
        let expected = Self.display.toAppKit(Self.target.frame)
        for window in ring.ownedWindows {
            let inner = window.frame.insetBy(dx: TilingFocusBorder.outset, dy: TilingFocusBorder.outset)
            #expect(inner == CGRect(x: expected.x, y: expected.y, width: expected.width, height: expected.height))
        }
        let outset = TilingFocusBorder.outset
        #expect(TilingFocusBorder.panelFrame(for: Self.target)
                == CGRect(x: expected.x - outset, y: expected.y - outset, width: expected.width + 2 * outset, height: expected.height + 2 * outset))
    }

    @Test func showingAgainMovesThePanelWithoutMakingAnother() {
        let ring = TilingFocusBorder.shared
        ring.show(Self.target)
        defer { ring.hide() }
        ring.show(TilingRingTarget(display: Self.display, frame: TileRect(x: 724, y: 32, width: 708, height: 860)))
        #expect(ring.ownedWindows.count == expectedPanels)
    }

    @Test func hidingRemovesThePanel() {
        let ring = TilingFocusBorder.shared
        ring.show(Self.target)
        ring.hide()
        #expect(ring.ownedWindows.isEmpty, "nothing idles on screen")
        ring.hide()
        #expect(ring.ownedWindows.isEmpty)
    }

    @Test func underASnapshotTheRingDrawsNothing() {
        let before = TopBarStyle.isSnapshot
        TopBarStyle.isSnapshot = true
        defer { TopBarStyle.isSnapshot = before }
        let ring = TilingFocusBorder.shared
        ring.show(Self.target)
        defer { ring.hide() }
        #expect(ring.ownedWindows.isEmpty)
    }

    @Test func theRingFollowsTheScreenSharePolicyAndTheCaptureBoost() {
        let ring = TilingFocusBorder.shared
        ring.applyScreenSharePolicy(visibleInShare: false)
        ring.show(Self.target)
        defer { ring.applyScreenSharePolicy(visibleInShare: false); ring.hide() }
        #expect(ring.ownedWindows.allSatisfy { $0.sharingType == .none })
        ring.applyScreenSharePolicy(visibleInShare: true)
        #expect(ring.ownedWindows.allSatisfy { $0.sharingType == .readOnly })
        ring.applyScreenSharePolicy(visibleInShare: false)
        #expect(ring.ownedWindows.allSatisfy { $0.sharingType == .none })
        ring.boostCaptureVisibility(for: 0.05)
        #expect(ring.ownedWindows.allSatisfy { $0.sharingType == .readOnly })
    }

    @Test func aPanelCreatedAfterTheSharePolicyWasSetStartsWithThatPolicy() {
        let ring = TilingFocusBorder.shared
        ring.applyScreenSharePolicy(visibleInShare: true)
        ring.show(Self.target)
        defer { ring.applyScreenSharePolicy(visibleInShare: false); ring.hide() }
        #expect(ring.ownedWindows.allSatisfy { $0.sharingType == .readOnly })
    }

    // MARK: Key sheet

    @Test func theKeySheetPanelNeverBecomesKeyOrMainAndIgnoresTheMouse() {
        let sheet = TilingKeySheet.shared
        sheet.show(rows: Self.rows, on: Self.display)
        defer { sheet.hide() }
        for window in sheet.ownedWindows {
            #expect(!window.canBecomeKey && !window.canBecomeMain)
            #expect(window.ignoresMouseEvents)
            #expect(window.styleMask.contains(.nonactivatingPanel))
            #expect(window.sharingType == .none)
            #expect(window.level == .statusBar)
            #expect(window.collectionBehavior.contains(.canJoinAllSpaces) && window.collectionBehavior.contains(.fullScreenAuxiliary))
            #expect(!window.isReleasedWhenClosed && !window.isOpaque)
        }
        #expect(sheet.ownedWindows.count == expectedPanels)
    }

    @Test func theKeySheetIsCentredOnTheDisplayItNames() {
        let sheet = TilingKeySheet.shared
        sheet.show(rows: Self.rows, on: Self.display)
        defer { sheet.hide() }
        for window in sheet.ownedWindows {
            let appKit = Self.display.appKitFrame
            #expect(abs(window.frame.midX - (appKit.x + appKit.width / 2)) < 1)
            #expect(abs(window.frame.midY - (appKit.y + appKit.height / 2)) < 1)
        }
    }

    @Test func hidingTheKeySheetRemovesItAndAnEmptyListShowsNothing() {
        let sheet = TilingKeySheet.shared
        sheet.show(rows: Self.rows, on: Self.display)
        sheet.hide()
        #expect(sheet.ownedWindows.isEmpty)
        sheet.show(rows: [], on: Self.display)
        #expect(sheet.ownedWindows.isEmpty, "with no key bound there is nothing to list")
    }

    @Test func underASnapshotTheKeySheetDrawsNothing() {
        let before = TopBarStyle.isSnapshot
        TopBarStyle.isSnapshot = true
        defer { TopBarStyle.isSnapshot = before }
        let sheet = TilingKeySheet.shared
        sheet.show(rows: Self.rows, on: Self.display)
        defer { sheet.hide() }
        #expect(sheet.ownedWindows.isEmpty)
    }

    @Test func theKeySheetFollowsTheScreenSharePolicyAndTheCaptureBoost() {
        let sheet = TilingKeySheet.shared
        sheet.applyScreenSharePolicy(visibleInShare: false)
        sheet.show(rows: Self.rows, on: Self.display)
        defer { sheet.applyScreenSharePolicy(visibleInShare: false); sheet.hide() }
        #expect(sheet.ownedWindows.allSatisfy { $0.sharingType == .none })
        sheet.applyScreenSharePolicy(visibleInShare: true)
        #expect(sheet.ownedWindows.allSatisfy { $0.sharingType == .readOnly })
        sheet.applyScreenSharePolicy(visibleInShare: false)
        sheet.boostCaptureVisibility(for: 0.05)
        #expect(sheet.ownedWindows.allSatisfy { $0.sharingType == .readOnly })
    }
}
