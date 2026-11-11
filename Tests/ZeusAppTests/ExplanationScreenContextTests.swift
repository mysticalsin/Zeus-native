import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Synthetic capture/metadata/permission adapters only. No screenshots, OS prompts, external
/// applications or user preferences are accessed. The overlay test owns its drawing-only panel.
@MainActor @Suite("Explanation selected snapshot and passive overlay", .serialized)
struct ExplanationScreenContextTests {
    @MainActor private final class Fixture {
        var allowed = true
        var now = 100.0
        var metadata = ExplanationScreenIdentity(displayID: 7,
            frame: CGRect(x: -1440, y: 200, width: 1440, height: 900), backingScale: 2,
            nativePixels: CGSize(width: 2880, height: 1800), foregroundPID: 123, windows: [])
        var image = ExplanationScreenServices.Image(jpeg: Data([1, 2, 3]), width: 1440, height: 900)
        var calls: [UInt32] = []
        var metadataReads = 0
        var observable = true
        var metadataFails = false
        var blocked = false
        var pending: CheckedContinuation<ExplanationScreenServices.Image, any Error>?
        var changed: (@MainActor @Sendable () -> Void)?
        var tick: (@MainActor @Sendable () -> Void)?
        var stopped = 0

        var services: ExplanationScreenServices {
            .init(hasPermission: { self.allowed },
                  identity: { _ in
                      self.metadataReads += 1
                      if self.metadataFails { throw ExplanationScreenContextFailure.unavailable }
                      return self.metadata
                  },
                  capture: { identity in
                      self.calls.append(identity.displayID)
                      if self.blocked { return try await withCheckedThrowingContinuation { self.pending = $0 } }
                      return self.image
                  }, monotonicNow: { self.now },
                  observeChanges: { callback in
                      guard self.observable else { return nil }
                      self.changed = callback
                      return ExplanationScreenObservation { self.changed = nil; self.stopped += 1 }
                  },
                  observeTime: { callback in
                      self.tick = callback
                      return ExplanationScreenObservation { self.tick = nil; self.stopped += 1 }
                  })
        }
        func release() { let value = pending; pending = nil; value?.resume(returning: image) }
        func waitForCapture() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while pending == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
            try #require(pending != nil)
        }
    }

    @Test func constructionAndDeniedCaptureNeverReadOrCaptureTheDisplay() async throws {
        let fixture = Fixture()
        fixture.allowed = false
        let context = ExplanationScreenContext(services: fixture.services)
        #expect(fixture.calls.isEmpty && fixture.metadataReads == 0)
        await #expect(throws: ExplanationScreenContextFailure.permissionRequired) {
            try await context.captureSelectedDisplay(7)
        }
        #expect(fixture.calls.isEmpty && fixture.metadataReads == 0)
        #expect(context.snapshot == nil && context.annotationContext == nil && !context.isCapturing)
    }

    @Test func selectedOnlyCaptureKeepsNativePixelsScaleAndNegativeDisplayOriginDistinct() async throws {
        let fixture = Fixture()
        let selected = ExplanationScreenContext(services: fixture.services)
        let shot = try await selected.captureSelectedDisplay(7)
        #expect(fixture.calls == [7])
        #expect(shot.geometry.fullImageSize == .init(width: 2880, height: 1800))
        #expect(shot.geometry.imageSize == .init(width: 1440, height: 900))
        #expect(shot.geometry.display.backingScale == 2)
        let live = try #require(selected.annotationContext)
        let point = ExplanationVector3(x: 360, y: 225)
        let global = try #require(shot.geometry.globalPoint(fromImage: point, current: live.currentDisplay))
        #expect(global == .init(x: -1080, y: 875))
        #expect(shot.geometry.imagePoint(fromGlobal: global, current: live.currentDisplay) == point)
        selected.clear()
        #expect(selected.snapshot == nil && fixture.changed == nil && fixture.tick == nil)
    }

    @Test func cancellationSuppressesLateCaptureAndKeepsTheSingleOSAdmissionUntilReturn() async throws {
        let fixture = Fixture()
        fixture.blocked = true
        let context = ExplanationScreenContext(services: fixture.services)
        let pending = Task { @MainActor in try await context.captureSelectedDisplay(7) }
        defer { fixture.release(); context.clear() }
        try await fixture.waitForCapture()
        context.cancel()
        #expect(context.isCapturing && context.annotationContext == nil)
        await #expect(throws: ExplanationScreenContextFailure.busy) { try await context.captureSelectedDisplay(7) }
        fixture.release()
        await #expect(throws: ExplanationScreenContextFailure.cancelled) { try await pending.value }
        #expect(fixture.calls == [7] && context.snapshot == nil && !context.isCapturing)
        #expect(context.invalidation == .cancelled && fixture.changed == nil)
    }

    @Test func changedDuringCaptureCannotPublishEvenIfMetadataReturnsToItsOriginalValue() async throws {
        let fixture = Fixture()
        fixture.blocked = true
        let context = ExplanationScreenContext(services: fixture.services)
        let pending = Task { @MainActor in try await context.captureSelectedDisplay(7) }
        defer { fixture.release(); context.clear() }
        try await fixture.waitForCapture()
        fixture.changed?()
        fixture.release()
        await #expect(throws: ExplanationScreenContextFailure.cancelled) { try await pending.value }
        #expect(context.snapshot == nil && context.annotationContext == nil)
    }

    @Test func unavailableObservationKeepsOnlyTheFrozenSnapshot() async throws {
        let fixture = Fixture()
        fixture.observable = false
        let context = ExplanationScreenContext(services: fixture.services)
        _ = try await context.captureSelectedDisplay(7)
        #expect(context.snapshot != nil && context.annotationContext == nil)
        #expect(context.invalidation == .verificationUnavailable && fixture.tick == nil)
    }

    @Test func slowCaptureCannotRestartTheAnnotationExpiryClock() async throws {
        let fixture = Fixture()
        fixture.blocked = true
        let context = ExplanationScreenContext(services: fixture.services)
        let pending = Task { @MainActor in try await context.captureSelectedDisplay(7) }
        defer { fixture.release(); context.clear() }
        try await fixture.waitForCapture()
        fixture.now += ExplanationScreenContext.annotationLifetime
        fixture.release()
        let snapshot = try await pending.value
        #expect(context.snapshot != nil && context.annotationContext == nil && context.invalidation == .expired)
        #expect(snapshot.frozenCanvasContext.isCurrent(captureID: snapshot.geometry.captureID))
        #expect(fixture.calls == [7] && fixture.changed == nil && fixture.tick == nil)
    }

    @Test func aMissingSelectedDisplayNeverFallsBackToAnotherCapture() async throws {
        let fixture = Fixture()
        let context = ExplanationScreenContext(services: fixture.services)
        await #expect(throws: ExplanationScreenContextFailure.unavailable) { try await context.captureSelectedDisplay(8) }
        #expect(fixture.calls.isEmpty && context.snapshot == nil && !context.isCapturing)
    }

    @Test func expiryAndUnknownMetadataStopObservationButDoNotEraseTheFrozenReference() async throws {
        for reason in ["expiry", "backwards", "permission", "metadata", "scroll"] {
            let fixture = Fixture()
            let selected = ExplanationScreenContext(services: fixture.services)
            _ = try await selected.captureSelectedDisplay(7)
            switch reason {
            case "expiry": fixture.now += ExplanationScreenContext.annotationLifetime
            case "backwards": fixture.now -= 1
            case "permission": fixture.allowed = false; fixture.now += 0.25
            case "metadata": fixture.metadataFails = true; fixture.now += 0.25
            default: fixture.changed?()
            }
            selected.recheckLease()
            #expect(selected.annotationContext == nil && selected.snapshot != nil, Comment(rawValue: reason))
            #expect(fixture.changed == nil && fixture.tick == nil && fixture.stopped == 2)
        }
    }

    @Test func oversizedImageNeverBecomesAContext() async throws {
        let fixture = Fixture()
        fixture.image = .init(jpeg: Data([1]), width: ExplanationScreenContext.maximumImageEdge + 1, height: 100)
        let context = ExplanationScreenContext(services: fixture.services)
        await #expect(throws: ExplanationScreenContextFailure.imageTooLarge) { try await context.captureSelectedDisplay(7) }
        #expect(context.snapshot == nil && context.annotationContext == nil && fixture.changed == nil)
    }

    @Test func ownerReleaseInvalidatesSubscribersAndStopsBothPassiveObservers() async throws {
        let fixture = Fixture()
        var owner: ExplanationScreenContext? = ExplanationScreenContext(services: fixture.services)
        weak var released = owner
        var reasons: [ExplanationScreenContext.Invalidation] = []
        _ = try await owner?.captureSelectedDisplay(7)
        let observation = owner?.observeInvalidation { reasons.append($0) }
        owner = nil
        #expect(released == nil && reasons == [.cancelled])
        #expect(fixture.changed == nil && fixture.tick == nil && fixture.stopped == 2)
        observation?.cancel()
        #expect(reasons == [.cancelled])
    }

    @Test func retiredObserverCannotInvalidateReplacementAndRenderTicksDoNotPollTheOS() async throws {
        let fixture = Fixture()
        let selected = ExplanationScreenContext(services: fixture.services)
        _ = try await selected.captureSelectedDisplay(7)
        let retired = try #require(fixture.changed)
        let replacement = try await selected.captureSelectedDisplay(7)
        let reads = fixture.metadataReads
        retired()
        for _ in 0..<240 { selected.recheckLease() }
        #expect(selected.annotationContext?.geometry.captureID == replacement.geometry.captureID)
        #expect(fixture.metadataReads == reads)
        fixture.now += 0.25
        selected.recheckLease()
        #expect(fixture.metadataReads == reads + 1)
        selected.clear()
    }

    @Test func croppedNonuniformPixelsProjectToPanelPointsAndInvertThroughGlobalAppKit() throws {
        let display = try ExplanationDisplayContext(displayID: 7,
            frame: .init(x: -1600, y: -400, width: 1600, height: 1000), backingScale: 2)
        let geometry = try ExplanationCaptureGeometry(display: display,
            fullImageSize: .init(width: 3200, height: 2000),
            crop: .init(x: 800, y: 200, width: 1600, height: 1000),
            imageSize: .init(width: 800, height: 250))
        let context = ExplanationCaptureContext(geometry: geometry, currentDisplay: display)
        let projection = try #require(ExplanationOverlay.panelTransform(context))
        let local = CGPoint(x: 100, y: 50).applying(projection.affine)
        #expect(local == CGPoint(x: 500, y: 200))
        #expect(projection.clip == CGRect(x: 400, y: 100, width: 800, height: 500))
        let global = try #require(geometry.globalPoint(fromImage: .init(x: 100, y: 50), current: display))
        #expect(global == .init(x: display.frame.x + local.x, y: display.frame.y + display.frame.height - local.y))
        #expect(geometry.imagePoint(fromGlobal: global, current: display) == .init(x: 100, y: 50))
        let replaced = try ExplanationDisplayContext(displayID: 7, frame: display.frame, backingScale: 2)
        #expect(ExplanationOverlay.panelTransform(.init(geometry: geometry, currentDisplay: replaced)) == nil)
    }

    @Test func ownedOverlayIsClickThroughReusesItsPanelAndDisappearsWhenContextExpires() async throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        let selected = ExplanationScreenContext(services: fixture.services)
        let shot = try await selected.captureSelectedDisplay(7)
        let mark = ExplanationObject(id: "target", space: .capture, captureID: shot.geometry.captureID,
            geometry: .init(kind: .ring, radius: 24), transform: .init(position: .init(x: 200, y: 180)),
            accessibleDescription: "Synthetic target")
        var scene = ExplanationScene(sessionID: UUID(), sceneID: UUID(), captureID: shot.geometry.captureID,
            objects: [mark.id: mark])
        let overlay = ExplanationOverlay()
        defer { overlay.hide(); selected.clear() }
        #expect(overlay.present(scene: scene, context: selected))
        let window = try #require(overlay.ownedWindows.first)
        #expect(window.ignoresMouseEvents && !window.canBecomeKey && !window.canBecomeMain)
        #expect(window.styleMask.contains(.nonactivatingPanel) && window.sharingType == .none)
        #expect(!window.isKeyWindow && overlay.displayIDs == [7])
        scene.revision += 1
        #expect(overlay.present(scene: scene, context: selected))
        #expect(overlay.ownedWindows.first === window)
        fixture.now += ExplanationScreenContext.annotationLifetime
        selected.recheckLease()
        #expect(overlay.ownedWindows.isEmpty && !window.isVisible && window.contentView == nil)
        #expect(selected.snapshot != nil)
    }

    // MARK: Desktop explanation card (owned panels, injected screen, no real content or capture)

    private static let cardScreen = ExplanationRect(x: 0, y: 0, width: 1440, height: 875)
    private static let cardTarget = ExplanationRect(x: 700, y: 400, width: 100, height: 40)

    private func makeDesktopCard() -> ExplanationDesktopCard {
        let card = ExplanationDesktopCard()
        card.screenProvider = { _, _ in (Self.cardScreen, []) }
        return card
    }

    private func cardDiagram(width: Double = 200, height: Double = 100) -> ExplanationScene {
        let object = ExplanationObject(id: "box", space: .canvas,
                                       geometry: .init(kind: .roundedRectangle, size: .init(x: width, y: height)),
                                       transform: .init(position: .init(x: 500, y: 300)), accessibleDescription: "A box")
        return ExplanationScene(sessionID: UUID(), sceneID: UUID(), objects: ["box": object])
    }

    private func cardInput(_ token: UUID, scene: ExplanationScene? = nil,
                           caption: String = "This is the box.") -> ExplanationDesktopCard.Input {
        ExplanationDesktopCard.Input(token: token, scene: scene ?? cardDiagram(), caption: caption, beatIDs: ["box"],
                                     anchors: PointingCardAnchors(anchor: Self.cardTarget, protected: [Self.cardTarget]),
                                     displayID: nil, pointer: nil)
    }

    @Test func desktopCardPanelsAreNonActivatingNeverKeyOrMainAndOnlyTheCloseControlTakesMouse() {
        let card = makeDesktopCard()
        let token = UUID()
        card.begin(token: token)
        card.update(cardInput(token))
        defer { card.end() }
        #expect(card.isVisible)
        let windows = card.ownedWindows
        #expect(windows.count >= 2)
        for window in windows {
            #expect(!window.canBecomeKey && !window.canBecomeMain)
            #expect(!window.isKeyWindow && !window.isMainWindow)
            #expect(window.styleMask.contains(.nonactivatingPanel))
        }
        let interactive = windows.filter { !$0.ignoresMouseEvents }
        #expect(interactive.count == 1)
        #expect(interactive.first?.frame.width == 28)
    }

    @Test func desktopCardIsPlacedBesideTheTargetAndNeverOverIt() throws {
        let card = makeDesktopCard()
        let token = UUID()
        card.begin(token: token)
        card.update(cardInput(token))
        defer { card.end() }
        let layout = try #require(card.lastLayout)
        let frame = try #require(layout.frame)
        #expect(layout.rung != .speechOnly)
        #expect(!ExplanationCardPlacement.intersects(frame, Self.cardTarget))
        #expect(frame.x >= Self.cardScreen.x && frame.x + frame.width <= Self.cardScreen.x + Self.cardScreen.width)
        #expect(layout.connector != nil)
    }

    @Test func desktopCardShowsTheExactSpokenBeatText() {
        let card = makeDesktopCard()
        let token = UUID()
        card.begin(token: token)
        card.update(cardInput(token, caption: "Click Share, then pick a person."))
        defer { card.end() }
        #expect(card.caption == "Click Share, then pick a person.")
    }

    @Test func desktopCardIgnoresACallbackFromAReplacedOrCancelledTurn() {
        let card = makeDesktopCard()
        let first = UUID(), second = UUID()
        card.begin(token: first)
        card.begin(token: second)
        card.update(cardInput(first))
        #expect(!card.isVisible)
        card.update(cardInput(second))
        #expect(card.isVisible)
        card.end()
        card.update(cardInput(second))
        #expect(!card.isVisible && card.ownedWindows.isEmpty)
    }

    @Test func desktopCardCloseControlDismissesItForThatTurnOnly() throws {
        let card = makeDesktopCard()
        let dismissals = Counter()
        card.onDismissed = { dismissals.value += 1 }
        let token = UUID()
        card.begin(token: token)
        card.update(cardInput(token))
        defer { card.end() }
        let closePanel = try #require(card.ownedWindows.first { !$0.ignoresMouseEvents })
        let button = try #require(closePanel.contentView as? NSButton)
        button.performClick(nil)
        #expect(!card.isVisible && dismissals.value == 1)
        card.update(cardInput(token))
        #expect(!card.isVisible)
        let next = UUID()
        card.begin(token: next)
        card.update(cardInput(next))
        #expect(card.isVisible)
    }

    @Test func desktopCardGoesSpeechOnlyWhenNothingReadableFits() {
        let card = makeDesktopCard()
        let token = UUID()
        card.begin(token: token)
        card.update(cardInput(token, scene: cardDiagram(width: 3000, height: 2000)))
        defer { card.end() }
        #expect(card.lastLayout?.rung == .speechOnly)
        #expect(!card.isVisible)
    }

    @Test func desktopCardIgnoresScenesThatHaveOnlyScreenMarks() {
        let card = makeDesktopCard()
        let token = UUID(), capture = UUID()
        let ring = ExplanationObject(id: "ring", space: .capture, captureID: capture,
                                     geometry: .init(kind: .ring, radius: 20), accessibleDescription: "Ring")
        var scene = ExplanationScene(sessionID: UUID(), sceneID: UUID(), objects: ["ring": ring])
        scene.captureID = capture
        card.begin(token: token)
        card.update(cardInput(token, scene: scene))
        defer { card.end() }
        #expect(!card.isVisible && card.ownedWindows.isEmpty)
    }

    @MainActor private final class Counter { var value = 0 }
}
