import AppKit
import Observation
import ScreenCaptureKit
import ZeusCore

/// One explicitly selected display snapshot. Pixels stay in memory; this type never uploads,
/// persists, or treats image content as instructions. Saved geometry alone grants no live lease.
struct ExplanationScreenSnapshot: Sendable {
    let geometry: ExplanationCaptureGeometry
    let jpegData: Data
    let capturedAt: Date

    /// Valid only when drawing over these immutable pixels inside Zeus. Desktop overlays
    /// must use the manager's short-lived annotationContext instead of this image identity.
    var frozenCanvasContext: ExplanationCaptureContext {
        ExplanationCaptureContext(geometry: geometry, currentDisplay: geometry.display)
    }

    var screenShot: ScreenShot {
        let frame = geometry.display.frame
        return ScreenShot(jpegData: jpegData, label: "Explicitly selected display snapshot",
            pixelWidth: Int(geometry.imageSize.width), pixelHeight: Int(geometry.imageSize.height),
            displayFrame: CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height))
    }
}

enum ExplanationScreenContextFailure: Error, Equatable {
    case permissionRequired, unavailable, busy, cancelled, stale, imageTooLarge
}

/// Public OS metadata, not a fingerprint of page pixels. Arbitrary content changes (including
/// programmatic or keyboard-driven scrolling) cannot be proved absent by this observation.
struct ExplanationScreenIdentity: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let id: UInt32
        let owner: Int32
        let bounds: CGRect
    }
    let displayID: UInt32
    let frame: CGRect
    let backingScale: Double
    let nativePixels: CGSize
    let foregroundPID: Int32
    let windows: [Window]
}

@MainActor
final class ExplanationScreenObservation {
    private var cancellation: (() -> Void)?
    init(_ cancellation: @escaping () -> Void) { self.cancellation = cancellation }
    func cancel() { let action = cancellation; cancellation = nil; action?() }
    isolated deinit { cancellation?() }
}

/// Dependencies are inert until an explicit capture request. Tests supply synthetic pixels,
/// permission status, metadata, time and observers; no test needs live capture or OS consent.
@MainActor
struct ExplanationScreenServices {
    struct Image: Sendable {
        let jpeg: Data
        let width: Int
        let height: Int
    }
    var hasPermission: () -> Bool
    var identity: (UInt32) throws -> ExplanationScreenIdentity
    var capture: @MainActor (ExplanationScreenIdentity) async throws -> Image
    var monotonicNow: () -> TimeInterval
    var observeChanges: (@escaping @MainActor @Sendable () -> Void) -> ExplanationScreenObservation?
    var observeTime: (@escaping @MainActor @Sendable () -> Void) -> ExplanationScreenObservation
}

/// Optional, short-lived desktop annotation context. A lease verifies bounded metadata and
/// observed changes, NOT arbitrary content freshness. The frozen snapshot remains available
/// independently when the desktop lease expires or cannot be observed safely.
@MainActor @Observable
final class ExplanationScreenContext {
    static let maximumImageEdge = 2048
    static let maximumImageBytes = 8 * 1024 * 1024
    static let annotationLifetime: TimeInterval = 5

    /// How long an annotation lease lasts. Chat keeps `.standard` (5 s, never renewed). A desktop
    /// pointing turn can run 10 to 60 s, so it renews while the observed identity is unchanged, up
    /// to a hard cap. Any observed change still invalidates at once.
    enum LeasePolicy: Equatable {
        case standard
        case renewing(max: TimeInterval)
    }

    enum Invalidation: String {
        case changed, expired, permissionLost, verificationUnavailable, cancelled, cleared
    }
    private(set) var snapshot: ExplanationScreenSnapshot?
    private(set) var annotationContext: ExplanationCaptureContext?
    private(set) var invalidation: Invalidation?
    private(set) var isCapturing = false
    @ObservationIgnored var onInvalidation: ((Invalidation) -> Void)?
    @ObservationIgnored private let services: ExplanationScreenServices
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var identity: ExplanationScreenIdentity?
    @ObservationIgnored private var deadline: TimeInterval?
    @ObservationIgnored private var leaseCap: TimeInterval?
    @ObservationIgnored private var lastMetadataCheck: TimeInterval?
    @ObservationIgnored private var changes: ExplanationScreenObservation?
    @ObservationIgnored private var clock: ExplanationScreenObservation?
    @ObservationIgnored private var invalidationObservers: [UUID: (Invalidation) -> Void] = [:]

    init(services: ExplanationScreenServices = .live) { self.services = services }

    isolated deinit {
        changes?.cancel(); clock?.cancel()
        // The overlay holds only a weak observation; dropping this owner must hide its panels
        // immediately rather than leaving a formerly valid annotation visible without a lease.
        onInvalidation?(.cancelled)
        for action in Array(invalidationObservers.values) { action(.cancelled) }
    }

    /// Only the app's explicit selected-display control calls this. No automatic permission
    /// prompt, default-display fallback, all-display capture, or background recapture exists.
    @discardableResult
    func captureSelectedDisplay(_ displayID: UInt32, lease: LeasePolicy = .standard) async throws -> ExplanationScreenSnapshot {
        guard !isCapturing else { throw ExplanationScreenContextFailure.busy }
        invalidate(.changed)
        guard displayID != 0 else { throw ExplanationScreenContextFailure.unavailable }
        guard services.hasPermission() else { throw ExplanationScreenContextFailure.permissionRequired }
        let token = UUID()
        generation = token
        isCapturing = true
        defer { isCapturing = false }
        let before = try services.identity(displayID)
        guard before.displayID == displayID else { throw ExplanationScreenContextFailure.unavailable }
        let display = try ExplanationDisplayContext(contextID: UUID(), displayID: displayID,
            frame: .init(x: before.frame.minX, y: before.frame.minY,
                         width: before.frame.width, height: before.frame.height), backingScale: before.backingScale)
        let full = ExplanationSize2(width: before.nativePixels.width, height: before.nativePixels.height)
        guard full.width.isFinite, full.height.isFinite,
              (1...131_072).contains(full.width), (1...131_072).contains(full.height) else {
            throw ExplanationScreenContextFailure.unavailable
        }
        // Observe before the async capture, so a change-and-return during capture is still stale.
        changes = services.observeChanges { [weak self] in
            guard let self, self.generation == token else { return }
            self.invalidate(.changed)
        }
        let canObserve = changes != nil
        let started = services.monotonicNow()
        do {
            guard generation == token, started.isFinite else { throw ExplanationScreenContextFailure.stale }
            let image = try await services.capture(before)
            guard !Task.isCancelled, generation == token else { throw ExplanationScreenContextFailure.cancelled }
            guard services.hasPermission() else { throw ExplanationScreenContextFailure.permissionRequired }
            guard try services.identity(displayID) == before else { throw ExplanationScreenContextFailure.stale }
            guard image.width > 0, image.height > 0,
                  image.width <= Self.maximumImageEdge, image.height <= Self.maximumImageEdge,
                  !image.jpeg.isEmpty, image.jpeg.count <= Self.maximumImageBytes else {
                throw ExplanationScreenContextFailure.imageTooLarge
            }
            let geometry = try ExplanationCaptureGeometry(display: display, fullImageSize: full,
                crop: .init(x: 0, y: 0, width: full.width, height: full.height),
                imageSize: .init(width: Double(image.width), height: Double(image.height)))
            let value = ExplanationScreenSnapshot(geometry: geometry, jpegData: image.jpeg, capturedAt: Date())
            snapshot = value
            guard canObserve else { invalidate(.verificationUnavailable); return value }
            let now = services.monotonicNow()
            guard now.isFinite, now >= started else { invalidate(.verificationUnavailable); return value }
            guard now < started + Self.annotationLifetime else { invalidate(.expired); return value }
            identity = before
            deadline = started + Self.annotationLifetime
            if case .renewing(let maximum) = lease, maximum.isFinite, maximum > Self.annotationLifetime {
                leaseCap = started + maximum
            } else { leaseCap = nil }
            lastMetadataCheck = now
            annotationContext = ExplanationCaptureContext(geometry: geometry, currentDisplay: display)
            invalidation = nil
            clock = services.observeTime { [weak self] in
                guard let self, self.generation == token else { return }
                self.recheckLease()
            }
            return value
        } catch {
            if generation == token { invalidate(Task.isCancelled ? .cancelled : .verificationUnavailable) }
            else { changes?.cancel(); changes = nil; clock?.cancel(); clock = nil }
            throw error
        }
    }

    /// Cancellation suppresses completion but retains the one in-flight capture admission until
    /// ScreenCaptureKit returns; repeated requests cannot accumulate uncancellable OS captures.
    func cancel() { invalidate(.cancelled) }
    func clear() { snapshot = nil; invalidate(.cleared) }

    func observeInvalidation(_ action: @escaping (Invalidation) -> Void) -> ExplanationScreenObservation {
        let id = UUID()
        invalidationObservers[id] = action
        return ExplanationScreenObservation { [weak self] in self?.invalidationObservers[id] = nil }
    }

    func recheckLease() {
        guard let identity, let deadline, annotationContext != nil else { return }
        let now = services.monotonicNow()
        guard now.isFinite, now < deadline, now >= deadline - Self.annotationLifetime else {
            invalidate(.expired); return
        }
        if let lastMetadataCheck {
            guard now >= lastMetadataCheck else { invalidate(.expired); return }
            // Rendering can update at the audio clock's cadence; OS metadata probes cannot.
            guard now - lastMetadataCheck >= 0.25 else { return }
        }
        lastMetadataCheck = now
        guard services.hasPermission() else { invalidate(.permissionLost); return }
        do {
            guard try services.identity(identity.displayID) == identity else { invalidate(.changed); return }
            // Unchanged metadata renews a pointing lease, never past its hard cap.
            if let leaseCap { self.deadline = min(now + Self.annotationLifetime, leaseCap) }
        } catch { invalidate(.verificationUnavailable) }
    }

    private func invalidate(_ reason: Invalidation) {
        generation = UUID()
        annotationContext = nil
        identity = nil
        deadline = nil
        leaseCap = nil
        lastMetadataCheck = nil
        changes?.cancel(); changes = nil
        clock?.cancel(); clock = nil
        invalidation = reason
        onInvalidation?(reason)
        for action in Array(invalidationObservers.values) { action(reason) }
    }
}

extension ExplanationScreenServices {
    static var live: Self {
        Self(hasPermission: { CGPreflightScreenCaptureAccess() },
             identity: liveIdentity, capture: liveCapture,
             monotonicNow: { ProcessInfo.processInfo.systemUptime },
             observeChanges: observeLiveChanges,
             observeTime: { update in
                 let timer = Timer(timeInterval: 0.25, repeats: true) { _ in MainActor.assumeIsolated { update() } }
                 timer.tolerance = 0.1
                 RunLoop.main.add(timer, forMode: .common)
                 return ExplanationScreenObservation { timer.invalidate() }
             })
    }

    private static func liveIdentity(_ displayID: UInt32) throws -> ExplanationScreenIdentity {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }),
              let mode = CGDisplayCopyDisplayMode(displayID),
              let foreground = NSWorkspace.shared.frontmostApplication,
              let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]], rows.count <= 512 else {
            throw ExplanationScreenContextFailure.unavailable
        }
        let bounds = CGDisplayBounds(displayID)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var windows: [ExplanationScreenIdentity.Window] = []
        for row in rows {
            guard let pid = row[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = row[kCGWindowLayer as String] as? NSNumber else {
                throw ExplanationScreenContextFailure.unavailable
            }
            if pid.int32Value == ownPID || layer.intValue != 0 { continue }
            guard let number = row[kCGWindowNumber as String] as? NSNumber,
                  let rawBounds = row[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: rawBounds as CFDictionary),
                  [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
                  frame.width > 0, frame.height > 0 else { throw ExplanationScreenContextFailure.unavailable }
            if frame.intersects(bounds) {
                windows.append(.init(id: number.uint32Value, owner: pid.int32Value, bounds: frame))
            }
        }
        return ExplanationScreenIdentity(displayID: displayID, frame: screen.frame,
            backingScale: screen.backingScaleFactor,
            nativePixels: CGSize(width: mode.pixelWidth, height: mode.pixelHeight),
            foregroundPID: foreground.processIdentifier, windows: windows)
    }

    private static func liveCapture(_ identity: ExplanationScreenIdentity) async throws -> Image {
        guard CGPreflightScreenCaptureAccess() else { throw ExplanationScreenContextFailure.permissionRequired }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == identity.displayID }) else {
            throw ExplanationScreenContextFailure.unavailable
        }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let configuration = SCStreamConfiguration()
        let width = Double(identity.nativePixels.width), height = Double(identity.nativePixels.height)
        let factor = min(1, Double(ExplanationScreenContext.maximumImageEdge) / max(width, height))
        configuration.width = max(1, Int(width * factor))
        configuration.height = max(1, Int(height * factor))
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw ExplanationScreenContextFailure.unavailable
        }
        return Image(jpeg: jpeg, width: image.width, height: image.height)
    }

    private static func observeLiveChanges(_ changed: @escaping @MainActor @Sendable () -> Void) -> ExplanationScreenObservation? {
        // Mouse-only passive observation requests no AX/Input Monitoring permission and never
        // suppresses or reposts input. Keyboard/programmatic changes remain an explicit limit.
        guard let mouse = NSEvent.addGlobalMonitorForEvents(
            matching: [.scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                       .leftMouseDragged, .rightMouseDragged, .otherMouseDragged],
            handler: { _ in MainActor.assumeIsolated { changed() } }) else { return nil }
        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceTokens = [NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification].map { name in
                workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { changed() }
                }
            }
        let screens = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { _ in MainActor.assumeIsolated { changed() } }
        return ExplanationScreenObservation {
            NSEvent.removeMonitor(mouse)
            workspaceTokens.forEach { workspace.removeObserver($0) }
            NotificationCenter.default.removeObserver(screens)
        }
    }
}
