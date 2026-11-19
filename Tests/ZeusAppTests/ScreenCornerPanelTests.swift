import AppKit
import Testing
import ZeusCore
@testable import Zeus

/// The corner panels must never take a click or focus, must show on every Space and over full-screen apps,
/// stay out of the window cycle, and follow the screen-sharing policy.
@MainActor @Suite("Screen corner panels")
struct ScreenCornerPanelTests {
    @Test func theFlagSetIsClickThroughNonActivatingAndOnEverySpace() {
        let flags = ScreenCornerPanelFlags.standard
        #expect(flags.ignoresMouseEvents)
        #expect(flags.styleMask.contains(.nonactivatingPanel))
        #expect(flags.styleMask.contains(.borderless))
        #expect(flags.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(flags.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(flags.collectionBehavior.contains(.ignoresCycle))
        #expect(flags.collectionBehavior.contains(.stationary))
        #expect(flags.level == .statusBar)
        #expect(!flags.isOpaque && !flags.hasShadow && !flags.hidesOnDeactivate)
    }

    @Test func aBuiltPanelCarriesTheFlagsAndTheCapturePolicy() {
        _ = NSApplication.shared
        let hidden = ScreenCornerOverlay.makePanel(visibleInShare: false)
        #expect(hidden.ignoresMouseEvents)
        #expect(hidden.styleMask.contains(.nonactivatingPanel))
        #expect(hidden.collectionBehavior == ScreenCornerPanelFlags.standard.collectionBehavior)
        #expect(hidden.level == .statusBar)
        #expect(!hidden.isOpaque && !hidden.hasShadow && !hidden.hidesOnDeactivate && !hidden.isReleasedWhenClosed)
        #expect(hidden.backgroundColor == .clear)
        #expect(hidden.sharingType == ZeusWindowSharing.sharingType(visibleInShare: false, surface: .zeusStandard))
        #expect(hidden.sharingType == .none)

        let shown = ScreenCornerOverlay.makePanel(visibleInShare: true)
        #expect(shown.sharingType == ZeusWindowSharing.sharingType(visibleInShare: true, surface: .zeusStandard))
        #expect(shown.sharingType == .readOnly)
    }
}
