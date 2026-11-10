import AppKit
import Foundation
import Testing
import SwiftUI
@testable import Zeus

private func recordOwnedWindowProcessExit() {
    let trace = Thread.callStackSymbols.prefix(32).joined(separator: "\n")
    FileHandle.standardError.write(Data("Owned-window fixture: process exit callback\n\(trace)\n".utf8))
}

@MainActor
enum OwnedWindowFixtureApplication {
    private(set) static var launchFinished = false
    private static var exitDiagnosticInstalled = false

    static func prepare() throws -> NSApplication.ActivationPolicy {
        let application = NSApplication.shared
        if !exitDiagnosticInstalled {
            atexit(recordOwnedWindowProcessExit)
            exitDiagnosticInstalled = true
        }
        record("prepare begin; launched=\(launchFinished), policy=\(application.activationPolicy().rawValue), active=\(application.isActive)")
        guard application.delegate == nil else {
            throw OwnedWindowEventDriver.Failure.unavailable("fixture application already has a delegate")
        }
        let original = application.activationPolicy()
        if original != .regular {
            guard application.setActivationPolicy(.regular) else {
                throw OwnedWindowEventDriver.Failure.unavailable("regular fixture activation policy was refused; original=\(original.rawValue), current=\(application.activationPolicy().rawValue)")
            }
        }
        guard application.activationPolicy() == .regular else {
            throw OwnedWindowEventDriver.Failure.unavailable("fixture did not retain regular activation policy")
        }
        if !launchFinished {
            if !application.isRunning {
                record("finishLaunching begin")
                application.finishLaunching()
                record("finishLaunching returned")
            }
            launchFinished = true
        }
        application.activate()
        record("prepare returned; active=\(application.isActive)")
        return original
    }

    static func restore(_ policy: NSApplication.ActivationPolicy) {
        record("restore policy begin; target=\(policy.rawValue)")
        let restored = NSApplication.shared.activationPolicy() == policy || NSApplication.shared.setActivationPolicy(policy)
        record("restore policy returned; accepted=\(restored), effective=\(NSApplication.shared.activationPolicy().rawValue)")
    }

    static func close(_ window: NSWindow) {
        record("close begin; window=\(window.windowNumber), releasedWhenClosed=\(window.isReleasedWhenClosed)")
        window.contentView = nil
        window.close()
        record("close returned")
    }

    static func record(_ message: String) {
        // Flush these bounded fixture-only lifecycle markers even if AppKit exits the host early.
        FileHandle.standardError.write(Data("Owned-window fixture: \(message)\n".utf8))
    }
}

/// Serializes only these own-process UI fixtures. No global input or system accessibility is used.
@MainActor
enum OwnedWindowJourneyLease {
    private static var held = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    static func perform(_ operation: @MainActor () async throws -> Void) async throws {
        if held { await withCheckedContinuation { waiters.append($0) } }
        else { held = true }
        defer {
            if waiters.isEmpty { held = false }
            else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        try await operation()
    }
}

@MainActor @Suite("Owned native window event driver", .serialized)
struct OwnedWindowEventDriverTests {
    private final class Target: NSObject {
        var calls = 0
        @objc func pressed(_ sender: Any?) { calls += 1 }
    }

    private final class NonTrackingView: NSView {
        private(set) var downs = 0
        private(set) var releases: [NSEvent] = []
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { downs += 1 }
        override func mouseUp(with event: NSEvent) { releases.append(event) }
    }

    private func host(_ content: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 40, y: 100, width: 320, height: 120),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Synthetic native event fixture"
        window.isReleasedWhenClosed = false
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func button(_ target: Target, registry: OwnedWindowControlRegistry, id: String) -> NSButton {
        let button = NSButton(title: "Synthetic action", target: target, action: #selector(Target.pressed(_:)))
        button.frame = NSRect(x: 20, y: 30, width: 180, height: 34)
        let probe = OwnedWindowControlProbeView(registry: registry, id: id, enabled: true)
        probe.frame = button.bounds
        probe.autoresizingMask = [.width, .height]
        button.addSubview(probe)
        return button
    }

    @Test func nativeButtonUsesFreshGeometryAndDisabledControlCannotFire() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let registry = OwnedWindowControlRegistry(), target = Target()
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
            let action = button(target, registry: registry, id: "fixture.action")
            content.addSubview(action)
            let window = host(content)
            defer { OwnedWindowFixtureApplication.close(window) }
            let driver = OwnedWindowEventDriver(registry: registry)
            driver.register(window)
            try await driver.click("fixture.action", in: window)
            #expect(target.calls == 1)
            action.setFrameOrigin(NSPoint(x: 60, y: 50))
            window.setFrameOrigin(NSPoint(x: 90, y: 180))
            try await driver.click("fixture.action", in: window)
            #expect(target.calls == 2)
            action.alphaValue = 0
            do {
                try await driver.click("fixture.action", in: window)
                Issue.record("A transparent native control was dispatched")
            } catch OwnedWindowEventDriver.Failure.unavailable { }
            #expect(target.calls == 2)
            action.alphaValue = 1
            action.isEnabled = false
            do {
                try await driver.click("fixture.action", in: window)
                Issue.record("A disabled native control was dispatched")
            } catch OwnedWindowEventDriver.Failure.unavailable { }
            #expect(target.calls == 2)
        }
    }

    @Test func hostedSwiftUIButtonReceivesRealWindowEvents() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let registry = OwnedWindowControlRegistry(), target = Target()
            let root = Button("Synthetic SwiftUI action") { target.calls += 1 }
                .buttonStyle(.borderedProminent)
                .ownedJourneyControl("fixture.swiftui")
                .frame(width: 320, height: 120)
                .environment(\.ownedWindowControlRegistry, registry)
            let window = host(NSHostingView(rootView: root))
            defer { OwnedWindowFixtureApplication.close(window) }
            let driver = OwnedWindowEventDriver(registry: registry)
            driver.register(window)
            try await driver.click("fixture.swiftui", in: window)
            #expect(target.calls == 1)
        }
    }

    @Test func nonTrackingResponderReceivesItsCanonicalQueuedRelease() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let registry = OwnedWindowControlRegistry()
            let content = NonTrackingView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
            let probe = OwnedWindowControlProbeView(registry: registry, id: "fixture.nontracking", enabled: true)
            probe.frame = NSRect(x: 20, y: 30, width: 180, height: 34)
            content.addSubview(probe)
            let window = host(content)
            defer { OwnedWindowFixtureApplication.close(window) }
            let driver = OwnedWindowEventDriver(registry: registry)
            driver.register(window)
            // This responder does not track mouseDown. The driver must deliver the queued
            // release even when AppKit canonicalizes its event number and timestamp.
            try await driver.click("fixture.nontracking", in: window)
            #expect(content.downs == 1)
            #expect(content.releases.count == 1)
            let release = try #require(content.releases.first)
            #expect(release.window === window)
            #expect(release.locationInWindow == NSPoint(x: 110, y: 47))
        }
    }

    @Test func consumedReleaseLeavesAnUnrelatedQueuedMouseUpUntouched() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let registry = OwnedWindowControlRegistry(), target = Target()
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
            content.addSubview(button(target, registry: registry, id: "fixture.queue-owner"))
            let window = host(content)
            defer { OwnedWindowFixtureApplication.close(window) }
            let driver = OwnedWindowEventDriver(registry: registry)
            driver.register(window)
            // Let the normal AppKit loop settle layout before inserting the
            // foreign event. It may legitimately consume queued input while an
            // async readiness wait yields; this test isolates synchronous dispatch.
            try await driver.click("fixture.queue-owner", in: window)
            #expect(target.calls == 1)
            let probes = registry.probes(for: "fixture.queue-owner", in: window)
            try #require(probes.count == 1)
            let probe = try #require(probes.first)
            let frame = probe.convert(probe.bounds, to: nil)
            // This event belongs to this regression fixture, not to the driver's gesture.
            // It has no target action; only this test may remove it during cleanup.
            let foreign = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 110, y: 47),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 2_000_000, clickCount: 1, pressure: 0))
            let queuedForeign = try OwnedWindowEventDriver.postAndCaptureRelease(foreign, in: window)
            defer {
                if let pending = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: .distantPast,
                    inMode: .eventTracking, dequeue: false), OwnedWindowEventDriver.sameEvent(pending, queuedForeign) {
                    _ = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: .distantPast,
                        inMode: .eventTracking, dequeue: true)
                }
            }
            try driver.dispatch("fixture.queue-owner", probe: probe, frame: frame, in: window)
            #expect(target.calls == 2)
            let stillQueued = try #require(NSApplication.shared.nextEvent(matching: .leftMouseUp, until: .distantPast,
                inMode: .eventTracking, dequeue: false))
            #expect(OwnedWindowEventDriver.sameEvent(stillQueued, queuedForeign), "The driver must leave the unrelated release at the queue head")
            if OwnedWindowEventDriver.sameEvent(stillQueued, queuedForeign) {
                _ = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: .distantPast,
                    inMode: .eventTracking, dequeue: true)
                let remainder = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: .distantPast,
                    inMode: .eventTracking, dequeue: false)
                #expect(remainder == nil, "The completed click must not leave its synthetic release for a later fixture")
            }
        }
    }

    @Test func duplicateRemovedAndUnownedControlsCannotDispatch() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let registry = OwnedWindowControlRegistry(), target = Target()
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
            let first = button(target, registry: registry, id: "fixture.duplicate")
            let second = button(target, registry: registry, id: "fixture.duplicate")
            content.addSubview(first)
            content.addSubview(second)
            let window = host(content)
            defer { OwnedWindowFixtureApplication.close(window) }
            let driver = OwnedWindowEventDriver(registry: registry)
            do {
                try await driver.click("fixture.duplicate", in: window)
                Issue.record("An unregistered native window received input")
            } catch OwnedWindowEventDriver.Failure.unownedWindow { }
            let rawProbe = try #require(first.subviews.compactMap { $0 as? OwnedWindowControlProbeView }.first)
            do {
                try driver.dispatch("fixture.duplicate", probe: rawProbe,
                    frame: rawProbe.convert(rawProbe.bounds, to: nil), in: window)
                Issue.record("Synchronous dispatch sent input to an unregistered window")
            } catch OwnedWindowEventDriver.Failure.unownedWindow { }
            #expect(target.calls == 0)
            driver.register(window)
            do {
                try await driver.click("fixture.duplicate", in: window)
                Issue.record("Duplicate controls received input")
            } catch OwnedWindowEventDriver.Failure.ambiguous { }
            first.removeFromSuperview()
            second.removeFromSuperview()
            do {
                try await driver.click("fixture.duplicate", in: window)
                Issue.record("A removed control received input")
            } catch OwnedWindowEventDriver.Failure.unavailable { }
            #expect(target.calls == 0)
        }
    }
}

/// Resolves current production geometry, then sends normal AppKit events to the owned window.
/// This is explicitly pointer/responder evidence. It cannot satisfy the separate AX assertions.
@MainActor
final class OwnedWindowEventDriver {
    enum Failure: Error, CustomStringConvertible {
        case unownedWindow, unavailable(String), ambiguous(String), staleGeometry(String), eventQueue
        var description: String {
            switch self {
            case .unownedWindow: "The fixture did not register this exact native window"
            case .unavailable(let id): "No ready layout-derived control: \(id)"
            case .ambiguous(let id): "Multiple layout-derived controls: \(id)"
            case .staleGeometry(let id): "Control geometry or ownership changed before dispatch: \(id)"
            case .eventQueue: "An unexpected event occupied the fixture's local release slot"
            }
        }
    }

    private let registry: OwnedWindowControlRegistry
    private var windows: [ObjectIdentifier: WeakWindow] = [:]
    private var nextEventNumber = 1_000_000
    private final class WeakWindow {
        weak var value: NSWindow?
        init(_ value: NSWindow) { self.value = value }
    }

    init(registry: OwnedWindowControlRegistry) { self.registry = registry }
    func register(_ window: NSWindow) { windows[ObjectIdentifier(window)] = WeakWindow(window) }

    func click(_ id: String, in window: NSWindow) async throws {
        guard windows[ObjectIdentifier(window)]?.value === window else { throw Failure.unownedWindow }
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        var previous: (ObjectIdentifier, NSRect)?
        var samples = 0
        var diagnostic = "No layout sample completed"
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            samples += 1
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let probes = registry.probes(for: id, in: window)
            if probes.count > 1 { throw Failure.ambiguous(id) }
            diagnostic = "samples=\(samples), probes=\(probes.count), visible=\(window.isVisible), "
                + "key=\(window.isKeyWindow), active=\(NSApplication.shared.isActive), "
                + "windowAlpha=\(window.alphaValue), miniaturized=\(window.isMiniaturized)"
            if let probe = probes.first { diagnostic += "; " + describe(probe, in: window) }
            if let probe = probes.first, let frame = readyFrame(probe, in: window) {
                let identity = ObjectIdentifier(probe)
                if let previous, previous.0 == identity, previous.1 == frame {
                    try dispatch(id, probe: probe, frame: frame, in: window)
                    return
                }
                previous = (identity, frame)
            } else { previous = nil }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.unavailable("\(id); \(diagnostic)")
    }

    private func describe(_ probe: OwnedWindowControlProbeView, in window: NSWindow) -> String {
        var ancestors: [String] = []
        var parent: NSView? = probe
        while let view = parent, ancestors.count < 24 {
            let enabled = (view as? NSControl).map { ",enabled=\($0.isEnabled)" } ?? ""
            ancestors.append("\(String(reflecting: type(of: view)))(alpha=\(view.alphaValue),hidden=\(view.isHidden)\(enabled))")
            if view === window.contentView { break }
            parent = view.superview
        }
        return "probeEnabled=\(probe.controlEnabled), frame=\(probe.convert(probe.bounds, to: nil)), "
            + "visibleRect=\(probe.convert(probe.visibleRect, to: nil)), "
            + "root=\(String(describing: window.contentView.map { $0.convert($0.bounds, to: nil) })), "
            + "ancestors=\(ancestors.joined(separator: " > "))"
    }

    private func readyFrame(_ probe: OwnedWindowControlProbeView, in window: NSWindow) -> NSRect? {
        guard let root = window.contentView, window.isVisible,
              window.alphaValue.isFinite, window.alphaValue > 0.01,
              !window.isMiniaturized, probe.window === window, probe.isDescendant(of: root),
              !probe.isHiddenOrHasHiddenAncestor, probe.controlEnabled else { return nil }
        // Native opacity/enabled state includes every owned ancestor. SwiftUI compositing opacity
        // is a separate visual proof obligation; this probe must not claim to inspect it.
        var parent: NSView? = probe
        while let view = parent {
            guard view.alphaValue.isFinite, view.alphaValue > 0.01 else { return nil }
            if let control = view as? NSControl, !control.isEnabled { return nil }
            if view === root { break }
            parent = view.superview
        }
        let frame = probe.convert(probe.bounds, to: nil)
        let visible = probe.convert(probe.visibleRect, to: nil)
        let rootFrame = root.convert(root.bounds, to: nil)
        guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }),
              !frame.isEmpty, visible.contains(frame), rootFrame.contains(frame) else { return nil }
        return frame
    }

    fileprivate func dispatch(_ id: String, probe: OwnedWindowControlProbeView, frame: NSRect, in window: NSWindow) throws {
        guard windows[ObjectIdentifier(window)]?.value === window else { throw Failure.unownedWindow }
        let probes = registry.probes(for: id, in: window)
        guard probes.count == 1, probes.first === probe,
              readyFrame(probe, in: window) == frame else { throw Failure.staleGeometry(id) }
        let point = NSPoint(x: frame.midX, y: frame.midY)
        let number = nextEventNumber
        nextEventNumber += 2
        let timestamp = ProcessInfo.processInfo.systemUptime
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: timestamp, windowNumber: window.windowNumber,
            context: nil, eventNumber: number, clickCount: 1, pressure: 1))
        let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: timestamp + 0.001, windowNumber: window.windowNumber,
            context: nil, eventNumber: number + 1, clickCount: 1, pressure: 0))
        guard up.windowNumber == window.windowNumber else { throw Failure.staleGeometry(id) }
        OwnedWindowFixtureApplication.record("dispatch \(id) begin; requested=\(number)/\(number + 1); down=\(Self.describe(down)); up=\(Self.describe(up))")
        // An AppKit mouseDown can track synchronously. Its same-window release must already be
        // queued. postEvent stays inside this test process; it never posts system/HID input.
        let queuedUp = try Self.postAndCaptureRelease(up, in: window)
        OwnedWindowFixtureApplication.record("dispatch \(id) queued release=\(Self.describe(queuedUp))")
        window.sendEvent(down)
        OwnedWindowFixtureApplication.record("dispatch \(id) down returned")
        // Tracking controls may have consumed our release already. An unrelated queue head does
        // not belong to this gesture: inspect without dequeuing or delivering it. Non-tracking
        // SwiftUI responders leave our exact release queued, which we deliver to the same window.
        if let pending = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: .distantPast,
                                                        inMode: .eventTracking, dequeue: false) {
            OwnedWindowFixtureApplication.record("dispatch \(id) release peek=\(Self.describe(pending)); owned=\(Self.sameEvent(pending, queuedUp))")
            if Self.sameEvent(pending, queuedUp) {
                let release = try #require(NSApplication.shared.nextEvent(matching: .leftMouseUp, until: .distantPast,
                    inMode: .eventTracking, dequeue: true))
                guard Self.sameEvent(release, queuedUp) else {
                    NSApplication.shared.postEvent(release, atStart: true)
                    throw Failure.eventQueue
                }
                // A real action can replace/remove its SwiftUI button during mouseDown. Complete
                // the begun gesture on its retained window; do not redirect through a new probe.
                guard windows[ObjectIdentifier(window)]?.value === window,
                      window.windowNumber == up.windowNumber else { throw Failure.staleGeometry(id) }
                window.sendEvent(release)
            }
        }
        print("Owned-window event: \(id), window=\(window.windowNumber), frame=\(frame), point=\(point), events=\(number)/\(number + 1)")
    }

    /// AppKit may canonicalize eventNumber and timestamp when inserting an event. Capture the
    /// immutable queued representation immediately after our front insertion, with no await or
    /// event dispatch between them. A later unrelated head must never become our identity.
    static func postAndCaptureRelease(_ release: NSEvent, in window: NSWindow) throws -> NSEvent {
        guard release.type == .leftMouseUp, release.window === window,
              release.windowNumber == window.windowNumber else { throw Failure.eventQueue }
        NSApplication.shared.postEvent(release, atStart: true)
        guard let queued = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: .distantPast,
            inMode: .eventTracking, dequeue: false),
              queued.type == release.type, queued.window === window,
              queued.windowNumber == window.windowNumber,
              queued.locationInWindow == release.locationInWindow,
              queued.modifierFlags == release.modifierFlags,
              queued.buttonNumber == release.buttonNumber,
              queued.clickCount == release.clickCount else { throw Failure.eventQueue }
        return queued
    }

    static func sameEvent(_ candidate: NSEvent, _ expected: NSEvent) -> Bool {
        candidate.type == expected.type && candidate.windowNumber == expected.windowNumber
            && candidate.eventNumber == expected.eventNumber && candidate.timestamp == expected.timestamp
            && candidate.locationInWindow == expected.locationInWindow
            && candidate.modifierFlags == expected.modifierFlags
            && candidate.buttonNumber == expected.buttonNumber && candidate.clickCount == expected.clickCount
    }

    private static func describe(_ event: NSEvent) -> String {
        "type=\(event.type.rawValue),number=\(event.eventNumber),window=\(event.windowNumber),timestamp=\(event.timestamp),point=\(event.locationInWindow)"
    }
}
