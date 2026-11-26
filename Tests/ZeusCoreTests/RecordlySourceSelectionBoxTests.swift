import Foundation
import Testing
@testable import ZeusCore

/// Source selection as plain numbers. The caller supplies the catalog. The type does not list
/// devices, check a permission, capture, or read a clock.
@Suite("Recordly source selection box")
struct RecordlySourceSelectionBoxTests {
    private let unknown = "Screen Recording permission is unknown. Check System Settings before starting capture."
    private let denied = "Screen Recording is off. Enable Zeus in System Settings → Privacy & Security → Screen Recording."
    private let specificDisplay = "Choose a specific display before starting capture."
    private let lostDisplay = "The selected display is no longer available. Choose another display explicitly."
    private let ambiguousDisplay = "The display catalog contains an ambiguous identity. Refresh the display choices."
    private let specificWindow = "Choose a window with a valid identity before starting capture."
    private let unboundWindow = "The window choice is not bound to a known window identity. Choose a window explicitly."
    private let ambiguousWindow = "The window catalog contains an ambiguous identity. Refresh the window choices."
    private let lostWindow = "The selected window is no longer available. Choose another window explicitly."
    private let specificHost = "Choose a specific host display for the region before starting capture."
    private let positiveRegion = "Select a region with finite coordinates and positive width and height."
    private let finiteBounds = "Select a region with finite bounds."
    private let unprovenanced = "Region coordinates have no verified coordinate-space source yet. Reselect after the region picker is available."

    @Test func aGrantedExactDisplayIsReady() {
        let outcome = resolve(.display(id: 17), displayIDs: [17])
        #expect(outcome == .ready(.display(id: 17)))
    }

    @Test func aMissingDisplayIsLostAndIsNotReplacedByAnother() {
        let outcome = resolve(.display(id: 29), displayIDs: [17, 31])
        #expect(outcome == .lostSource(reason: lostDisplay))
    }

    @Test func aZeroOrAmbiguousDisplayIsInvalid() {
        #expect(resolve(.display(id: 0), displayIDs: [17]) == .invalidIntent(reason: specificDisplay))
        #expect(resolve(.display(id: 17), displayIDs: [17, 17]) == .invalidIntent(reason: ambiguousDisplay))
    }

    @Test func unknownAndDeniedPermissionFailClosedBeforeTheCatalog() {
        #expect(resolve(.display(id: 17), displayIDs: [17], permission: .unknown) == .denied(reason: unknown))
        #expect(resolve(.display(id: 17), displayIDs: [17], permission: .denied) == .denied(reason: denied))
    }

    @Test func aRegionWithoutACoordinateSourceFailsClosed() {
        let inside = resolve(.region(displayID: 17, x: 12.5, y: 20, width: 400, height: 300), displayIDs: [17])
        let outside = resolve(.region(displayID: 17, x: 1900, y: 900, width: 100, height: 100), displayIDs: [17])
        let missingHost = resolve(.region(displayID: 17, x: 10, y: 10, width: 20, height: 20), displayIDs: [29])
        #expect(inside == .invalidIntent(reason: unprovenanced))
        #expect(outside == .invalidIntent(reason: unprovenanced))
        #expect(missingHost == .invalidIntent(reason: unprovenanced))
    }

    @Test func invalidRegionGeometryIsRejectedBeforeTheCoordinateSource() {
        #expect(resolve(.region(displayID: 0, x: 10, y: 10, width: 20, height: 20), displayIDs: [17]) == .invalidIntent(reason: specificHost))
        #expect(resolve(.region(displayID: 17, x: 0, y: 0, width: 0, height: 10), displayIDs: [17]) == .invalidIntent(reason: positiveRegion))
        #expect(resolve(.region(displayID: 17, x: 0, y: 0, width: 10, height: -1), displayIDs: [17]) == .invalidIntent(reason: positiveRegion))
        #expect(resolve(.region(displayID: 17, x: .nan, y: 0, width: 10, height: 10), displayIDs: [17]) == .invalidIntent(reason: positiveRegion))
        #expect(resolve(.region(displayID: 17, x: 0, y: .infinity, width: 10, height: 10), displayIDs: [17]) == .invalidIntent(reason: positiveRegion))
        let overflow = Double.greatestFiniteMagnitude
        #expect(resolve(.region(displayID: 17, x: overflow, y: 0, width: overflow, height: 10), displayIDs: [17]) == .invalidIntent(reason: finiteBounds))
        #expect(resolve(.region(displayID: 17, x: 0, y: overflow, width: 10, height: overflow), displayIDs: [17]) == .invalidIntent(reason: finiteBounds))
    }

    @Test func anExactWindowIsReadyAndAReusedOrAbsentIdentityIsLost() {
        let binding = RecordlySourceSelectionBox.Window(number: 9, identityToken: "window-token-A", isPresent: true)
        #expect(resolve(.window(number: 9, identityToken: "window-token-A"), windows: [binding]) == .ready(.window(number: 9, identityToken: "window-token-A")))
        #expect(resolve(.window(number: 9, identityToken: "window-token-old"), windows: [binding]) == .lostSource(reason: lostWindow))
        let absent = RecordlySourceSelectionBox.Window(number: 9, identityToken: "window-token-A", isPresent: false)
        #expect(resolve(.window(number: 9, identityToken: "window-token-A"), windows: [absent]) == .lostSource(reason: lostWindow))
    }

    @Test func anUnboundZeroNegativeOrBlankWindowIsInvalid() {
        #expect(resolve(.window(number: 8, identityToken: "token")) == .invalidIntent(reason: unboundWindow))
        let zero = RecordlySourceSelectionBox.Window(number: 0, identityToken: "token", isPresent: true)
        #expect(resolve(.window(number: 0, identityToken: "token"), windows: [zero]) == .invalidIntent(reason: specificWindow))
        let negative = RecordlySourceSelectionBox.Window(number: -1, identityToken: "token", isPresent: true)
        #expect(resolve(.window(number: -1, identityToken: "token"), windows: [negative]) == .invalidIntent(reason: specificWindow))
        let blank = RecordlySourceSelectionBox.Window(number: 5, identityToken: "   ", isPresent: true)
        #expect(resolve(.window(number: 5, identityToken: "   "), windows: [blank]) == .invalidIntent(reason: specificWindow))
    }

    @Test func aDuplicateWindowNumberIsAmbiguous() {
        let windows = [
            RecordlySourceSelectionBox.Window(number: 5, identityToken: "token", isPresent: true),
            RecordlySourceSelectionBox.Window(number: 5, identityToken: "token", isPresent: true),
        ]
        #expect(resolve(.window(number: 5, identityToken: "token"), windows: windows) == .invalidIntent(reason: ambiguousWindow))
    }

    @Test func aWindowBindsOnlyWhenOwnedOnScreenAndLargerThanForty() {
        #expect(RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: 12, x: 2, y: 3, width: 80, height: 60, isOnScreen: true))
        #expect(RecordlySourceSelectionBox.identityToken(number: 5, ownerProcessID: 12) == "5:12")
        #expect(RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: 12, x: -300, y: 40, width: 90, height: 70, isOnScreen: true))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: 12, x: 0, y: 0, width: 40, height: 60, isOnScreen: true))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: 12, x: 0, y: 0, width: 80, height: 40, isOnScreen: true))
        #expect(RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: 12, x: 0, y: 0, width: 40.1, height: 40.1, isOnScreen: true))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: 12, x: 0, y: 0, width: 80, height: 60, isOnScreen: false))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: nil, x: 0, y: 0, width: 100, height: 100, isOnScreen: true))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: 0, ownerProcessID: 12, x: 0, y: 0, width: 80, height: 60, isOnScreen: true))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: -1, ownerProcessID: 12, x: 0, y: 0, width: 80, height: 60, isOnScreen: true))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: 0, x: 0, y: 0, width: 80, height: 60, isOnScreen: true))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: -3, x: 0, y: 0, width: 80, height: 60, isOnScreen: true))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: 12, x: .nan, y: 0, width: 80, height: 60, isOnScreen: true))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: 12, x: 0, y: .infinity, width: 80, height: 60, isOnScreen: true))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: 12, x: 0, y: 0, width: .infinity, height: 60, isOnScreen: true))
        #expect(!RecordlySourceSelectionBox.acceptsWindow(
            number: 5, ownerProcessID: 12, x: 0, y: 0, width: 80, height: .nan, isOnScreen: true))
    }

    @Test func onlyAPositiveDisplayOrWindowIsAnExplicitIdentity() {
        #expect(RecordlySourceSelectionBox.hasValidExplicitIdentity(.display(id: 17)))
        #expect(!RecordlySourceSelectionBox.hasValidExplicitIdentity(.display(id: 0)))
        #expect(!RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 0, identityToken: "token")))
        #expect(!RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: -1, identityToken: "x")))
        #expect(!RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 4, identityToken: " \n ")))
        #expect(RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 4, identityToken: "token")))
        #expect(!RecordlySourceSelectionBox.hasValidExplicitIdentity(.region(displayID: 17, x: 0, y: 0, width: .infinity, height: 4)))
        #expect(!RecordlySourceSelectionBox.hasValidExplicitIdentity(.region(displayID: 17, x: 0, y: 0, width: 10, height: 4)))
    }

    private func resolve(
        _ intent: RecordlySourceSelectionBox.Intent,
        displayIDs: [UInt32] = [],
        windows: [RecordlySourceSelectionBox.Window] = [],
        permission: RecordlySourceSelectionBox.Permission = .granted
    ) -> RecordlySourceSelectionBox.Outcome {
        RecordlySourceSelectionBox.resolve(
            intent: intent,
            displayIDs: displayIDs,
            windows: windows,
            permission: permission)
    }
}
