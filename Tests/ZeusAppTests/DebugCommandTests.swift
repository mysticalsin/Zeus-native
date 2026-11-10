import Foundation
import Testing
import AppKit
@testable import Zeus

/// Pure logic behind "zeus debug drives the running app; single instance" (PLAN-QA7 item 1).
/// None of these launch, quit or control a real app: they test the decision functions only.
@Suite("Debug forward and single instance")
struct DebugForwardTests {
    @Test func debugForwardDetectsTheArgvShape() {
        #expect(DebugForward.isRequested(argv: ["debug", "open-settings", "voice"]))
        #expect(DebugForward.isRequested(argv: ["debug"]))
        #expect(!DebugForward.isRequested(argv: []))
        #expect(!DebugForward.isRequested(argv: ["--snapshots", "/tmp/s"]))
        #expect(!DebugForward.isRequested(argv: ["ask", "debug this for me"]))
    }

    @Test func instanceGuardStaysPutWithNoOtherInstance() {
        #expect(!InstanceGuard.shouldExit(argv: [], others: []))
        #expect(!InstanceGuard.shouldExit(argv: ["--snapshots", "/tmp/s"], others: []))
    }

    @Test func instanceGuardExitsForAnOrdinaryRelaunch() {
        #expect(InstanceGuard.shouldExit(argv: [], others: [4242]))
        #expect(InstanceGuard.shouldExit(argv: ["debug", "tab", "agents"], others: [4242]))
    }

    @Test func instanceGuardStaysForExemptFlags() {
        for flag in ["--snapshots", "--settings-only", "--onboarding-only", "--voice-selftest"] {
            #expect(!InstanceGuard.shouldExit(argv: [flag, "/tmp/out"], others: [4242]), "\(flag)")
        }
    }
}

@Suite("Debug screenshot capture selection")
struct DebugScreenshotTests {
    @Test func filterMatchesByName() {
        #expect(DebugScreenshot.matches(name: "settings", filter: nil))
        #expect(DebugScreenshot.matches(name: "settings", filter: "all"))
        #expect(DebugScreenshot.matches(name: "settings", filter: "settings"))
        #expect(DebugScreenshot.matches(name: "settings", filter: "Settings"))
        #expect(!DebugScreenshot.matches(name: "settings", filter: "onboarding"))
        #expect(DebugScreenshot.matches(name: "notch", filter: "notch"))
    }

    @Test func argumentParsingSplitsPathAndWindowFlag() {
        let (path, filter) = DebugScreenshot.parseArgument("/tmp/qa7/s --window settings")
        #expect(path == "/tmp/qa7/s")
        #expect(filter == "settings")
        let (onlyPath, noFilter) = DebugScreenshot.parseArgument("/tmp/qa7/s")
        #expect(onlyPath == "/tmp/qa7/s")
        #expect(noFilter == nil)
        let (nilPath, allFilter) = DebugScreenshot.parseArgument("--window all")
        #expect(nilPath == nil)
        #expect(allFilter == "all")
        let (emptyPath, emptyFilter) = DebugScreenshot.parseArgument(nil)
        #expect(emptyPath == nil)
        #expect(emptyFilter == nil)
    }

    @MainActor
    @Test func captureWritesOnlyMatchingNamedWindows() {
        let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                                      styleMask: [.borderless], backing: .buffered, defer: true)
        settingsWindow.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        let onboardingWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                                        styleMask: [.borderless], backing: .buffered, defer: true)
        onboardingWindow.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        let base = NSTemporaryDirectory() + "zeus-debug-screenshot-test-\(UUID().uuidString)"
        defer {
            for name in ["settings", "onboarding"] { try? FileManager.default.removeItem(atPath: "\(base)-\(name).png") }
        }
        let paths = DebugScreenshot.capture(windows: [("settings", settingsWindow), ("onboarding", onboardingWindow)],
                                            base: base, filter: "settings")
        #expect(paths.count == 1)
        #expect(paths.first?.hasSuffix("-settings.png") == true)
    }

    @MainActor
    @Test func QA20CaptureWritesTheGivenPngPath() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 30),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
        let path = NSTemporaryDirectory() + "zeus-exact-\(UUID().uuidString).png"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let paths = DebugScreenshot.capture(windows: [("settings", window)], base: path, filter: "settings")
        #expect(paths == [path])
        #expect(paths.first?.hasSuffix(".png-settings.png") != true)
    }

    @Suite("Folder access status")
struct FolderAccessStatusTests {
    // QA7 round 11 (report-11.md): "App stays responsive through onboarding, tabs, animations,
    // Settings" FAIL, a 10+ minute hang, `zeus status` exit 3. `sample` on the hung pid showed the
    // main thread stuck for the entire hang inside `open()`, reached via
    // AirDropPermissionRow.body -> FolderAccess.status(for:) -> contentsOfDirectory(atPath:).
    // Root cause: `status(for:)` probed the real (TCC-protected) folder unconditionally, even
    // from a passive SwiftUI `body` read -- the *first* probe for a never-decided folder blocks
    // the thread in `open()` until the user answers a one-time system consent dialog nothing here
    // ever taps. These exercise the pure decision function only (never the real target folders):
    // merely viewing a Settings page must never be able to trigger that probe.
    @Test func notAskedIsAlwaysNotDeterminedRegardlessOfWhatProbingWouldHaveFound() {
        #expect(FolderAccess.status(asked: false, exists: true, listable: true) == .notDetermined)
        #expect(FolderAccess.status(asked: false, exists: false, listable: false) == .notDetermined)
        #expect(FolderAccess.status(asked: false, exists: true, listable: false) == .notDetermined)
    }

    @Test func askedReflectsWhatTheProbeFound() {
        #expect(FolderAccess.status(asked: true, exists: false, listable: false) == .denied)
        #expect(FolderAccess.status(asked: true, exists: true, listable: false) == .denied)
        #expect(FolderAccess.status(asked: true, exists: true, listable: true) == .granted)
    }
}

// QA7 round 11 (report-11.md): `zeus debug screenshot` returned a path but the PNG was solid
    // white for every real window, because every real content view is layer-backed (hosts
    // SwiftUI via `NSHostingView`) and `cacheDisplay` only rasterizes `draw(_:)`-based views.
    // `captureWritesOnlyMatchingNamedWindows` above uses a plain (non-layer-backed) `NSView`, so
    // it couldn't have caught this. This one makes the content view layer-backed with a known,
    // non-white fill and asserts the written PNG actually contains that colour.
    @MainActor
    @Test func captureRastersizesLayerBackedContentNotJustBlankWhite() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemRed.cgColor
        window.contentView = view
        let base = NSTemporaryDirectory() + "zeus-debug-screenshot-layer-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: "\(base)-layered.png") }
        let paths = DebugScreenshot.capture(windows: [("layered", window)], base: base, filter: nil)
        #expect(paths.count == 1)
        guard let path = paths.first,
              let data = FileManager.default.contents(atPath: path),
              let image = NSBitmapImageRep(data: data) else {
            Issue.record("expected a readable PNG at the captured path")
            return
        }
        guard let pixel = image.colorAt(x: image.pixelsWide / 2, y: image.pixelsHigh / 2) else {
            Issue.record("expected a readable centre pixel")
            return
        }
        // Blank/white would read ~(1,1,1); the real red fill reads with a dominant red channel.
        #expect(pixel.redComponent > 0.6)
        #expect(pixel.greenComponent < 0.4)
    }

    // QA7 round 11 follow-up: the fix above made real content appear, but upside-down -- found
    // re-verifying live, not by this suite (a centred fill can't tell flipped from not). Every
    // real window this hook captures hosts its content in an NSHostingView specifically (it's
    // flipped: isFlipped and its layer's isGeometryFlipped are both true) -- that's the property
    // that matters, and the one a plain NSView (isFlipped false) can't stand in for: an
    // un-flipped view's own layer geometry is *already* bottom-left-origin same as Core Graphics,
    // so a test using one would validate the opposite of what production needs.
    //
    // Two earlier versions of this test failed for reasons unrelated to the flip fix itself,
    // both only caught by actually running `swift test` (not by a standalone `swift` script,
    // which behaved differently both times):
    //   1. A real NSHostingView with SwiftUI content (to match production exactly) reads back
    //      solid black here -- SwiftUI only populates a hosting view's layer through its own
    //      display-link render pass, which needs the window to actually be on screen, and that
    //      never fires for a window built and never shown inside this test host.
    //   2. A flipped NSView with a plain CALayer marker added via addSublayer() *also* reads
    //      back solid black here, even though the identical code reads back correctly in a
    //      standalone `swift` script -- addSublayer()'d content apparently never gets composited
    //      by CALayer.render(in:) in this host without a real window-server/display-link
    //      connection, regardless of layout passes pumped first.
    // What does work here (same mechanism as `captureRastersizesLayerBackedContentNotJustBlankWhite`
    // above, which only ever sets a layer's own backgroundColor, no sublayers): giving the view
    // a CAGradientLayer as its own backing layer via makeBackingLayer(), so AppKit wires up
    // isGeometryFlipped on it exactly as it would for the default layer, and never asks it to
    // composite a sublayer.
    @MainActor
    @Test func captureKeepsTheTopLeftCornerOnTop() {
        final class FlippedGradientView: NSView {
            override var isFlipped: Bool { true }
            override func makeBackingLayer() -> CALayer {
                let gradient = CAGradientLayer()
                gradient.colors = [NSColor.systemRed.cgColor, NSColor.black.cgColor]
                // In flipped coordinates (isGeometryFlipped follows isFlipped), y = 0 is the TOP
                // -- same convention production's real content views (NSHostingView) use.
                gradient.startPoint = CGPoint(x: 0.5, y: 0)
                gradient.endPoint = CGPoint(x: 0.5, y: 1)
                return gradient
            }
        }
        let size: CGFloat = 40
        let view = FlippedGradientView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = view
        let base = NSTemporaryDirectory() + "zeus-debug-screenshot-flip-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: "\(base)-flip.png") }
        let paths = DebugScreenshot.capture(windows: [("flip", window)], base: base, filter: nil)
        guard let path = paths.first,
              let data = FileManager.default.contents(atPath: path),
              let image = NSBitmapImageRep(data: data) else {
            Issue.record("expected a readable PNG at the captured path")
            return
        }
        // Software-rendering a CAGradientLayer through `render(in:)` (as opposed to the normal
        // GPU compositor) measurably never reaches the stop colors' own full component values --
        // empirically confirmed by scanning every row of a real capture: a clean, perfectly
        // monotonic gradient from ~0.57 down to ~0.004, not the ~0.96-to-0 the stop colors alone
        // would suggest. So this checks the relative direction (red end reads meaningfully higher
        // near the top than near the bottom -- if the flip were backwards this would invert), not
        // an absolute "is this pure red" threshold.
        let topLeft = image.colorAt(x: 5, y: 2)?.redComponent ?? -1
        let bottomLeft = image.colorAt(x: 5, y: image.pixelsHigh - 3)?.redComponent ?? -1
        #expect(topLeft > 0.4, "the red end of the gradient is pinned at flipped y=0, which should read back noticeably redder near the TOP of the PNG")
        #expect(bottomLeft < 0.15, "the black end of the gradient is at the view's bottom, which should read back nearly black")
        #expect(topLeft - bottomLeft > 0.3, "the top-to-bottom direction must not be inverted")
    }
}
