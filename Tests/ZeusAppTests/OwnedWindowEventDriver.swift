import AppKit
import Foundation
import Testing
import SwiftUI
@testable import Zeus

@MainActor
enum OwnedWindowFixtureApplication {
    private(set) static var launchFinished = false

    static func prepare() throws -> NSApplication.ActivationPolicy {
        let application = NSApplication.shared
        record("prepare begin; launched=\(launchFinished), policy=\(application.activationPolicy().rawValue), active=\(application.isActive)")
        guard application.delegate == nil else {
            throw OwnedWindowEventDriver.Failure.unavailable("fixture application already has a delegate")
        }
        let original = application.activationPolicy()
        guard application.setActivationPolicy(.regular) else {
            throw OwnedWindowEventDriver.Failure.unavailable("regular fixture activation policy was refused")
        }
        if !launchFinished {
            record("finishLaunching begin")
            application.finishLaunching()
            launchFinished = true
            record("finishLaunching returned")
        }
        application.activate()
        record("prepare returned; active=\(application.isActive)")
        return original
    }

    static func restore(_ policy: NSApplication.ActivationPolicy) {
        record("restore policy begin; target=\(policy.rawValue)")
        let restored = NSApplication.shared.setActivationPolicy(policy)
        record("restore policy returned; accepted=\(restored)")
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

    private func dispatch(_ id: String, probe: OwnedWindowControlProbeView, frame: NSRect, in window: NSWindow) throws {
        guard registry.probes(for: id, in: window).count == 1,
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
        // An AppKit mouseDown can track synchronously. Its same-window release must already be
        // queued. postEvent stays inside this test process; it never posts system/HID input.
        NSApplication.shared.postEvent(up, atStart: true)
        window.sendEvent(down)
        // Non-tracking SwiftUI responders return before consuming up. Dequeue and deliver only
        // our exact release. An unrelated local event is restored untouched and fails the test.
        if let pending = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: Date(),
                                                        inMode: .eventTracking, dequeue: true) {
            guard pending.windowNumber == window.windowNumber, pending.eventNumber == number + 1 else {
                NSApplication.shared.postEvent(pending, atStart: true)
                throw Failure.eventQueue
            }
            guard probe.window === window else { throw Failure.staleGeometry(id) }
            window.sendEvent(pending)
        }
        print("Owned-window event: \(id), window=\(window.windowNumber), frame=\(frame), point=\(point), events=\(number)/\(number + 1)")
    }
}
