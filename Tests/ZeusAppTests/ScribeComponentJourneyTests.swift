import AppKit
import ApplicationServices
import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// A failure-only diagnostic, never an action driver. AX handles are created, queried, and
/// released on one detached task; only bounded text crosses back to the AppKit actor.
private enum OwnedProcessAXDiagnostic {
    static let windowMarkerPrefix = "zeus.synthetic.scribe.window."

    private struct Failure: Error { let reason: String }
    private enum Phase: String {
        case dispatching, detachedEntered, detachedReturned, dispatchReturned
        case typeIDBegin, typeIDReturned, trustBegin, trustReturned, createApplicationBegin, createApplicationReturned
        case timeoutBegin, timeoutReturned, getPIDBegin, getPIDReturned
        case attributeBegin, attributeReturned, countBegin, countReturned, valuesBegin, valuesReturned
        case breadcrumbLimit
    }

    private static func record(_ phase: Phase) {
        // Fixed names only: no app payload, attribute values, paths or foreign-process details.
        FileHandle.standardError.write(Data("Own-PID AX phase: \(phase.rawValue)\n".utf8))
    }

    static func collect(pid: Int32, windowMarker: String) async -> [String] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        record(.dispatching)
        let result = await Task.detached(priority: .utility) {
            record(.detachedEntered)
            let rows = snapshot(pid: pid, windowMarker: windowMarker, deadline: deadline)
            record(.detachedReturned)
            return rows
        }.value
        record(.dispatchReturned)
        return result
    }

    private static func snapshot(pid: Int32, windowMarker: String,
                                 deadline: ContinuousClock.Instant) -> [String] {
        guard !Thread.isMainThread, pid == ProcessInfo.processInfo.processIdentifier,
              windowMarker.hasPrefix(windowMarkerPrefix) else {
            return ["own-PID AX diagnostic withheld: invalid execution thread, PID, or window marker"]
        }
        var rows: [String] = []
        var visited: [AXUIElement] = []
        var complete = false
        var incompleteBranch = false
        var breadcrumbs = 0
        func breadcrumb(_ phase: Phase) {
            // At most 64 snapshot markers, plus the four fixed dispatch markers above.
            guard breadcrumbs < 64 else { return }
            breadcrumbs += 1
            record(breadcrumbs == 64 ? .breadcrumbLimit : phase)
        }
        func field(_ value: String) -> String {
            String(value.prefix(160)).replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
        }
        func append(_ value: String) { if rows.count < 79 { rows.append(value) } }
        func remainingTimeout() throws -> Float {
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { throw Failure(reason: "2-second monotonic budget exhausted") }
            let parts = remaining.components
            let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
            return Float(min(0.1, seconds))
        }
        guard ContinuousClock.now < deadline else {
            return ["snapshot stopped: 2-second monotonic budget exhausted; original UI failure remains"]
        }
        breadcrumb(.typeIDBegin)
        let axTypeID = AXUIElementGetTypeID()
        breadcrumb(.typeIDReturned)
        func prepare(_ element: AXUIElement) throws {
            breadcrumb(.timeoutBegin)
            let timeout = try remainingTimeout()
            let error = AXUIElementSetMessagingTimeout(element, timeout)
            breadcrumb(.timeoutReturned)
            guard error == .success else { throw Failure(reason: "set timeout AXError=\(error.rawValue)") }
            _ = try remainingTimeout()
        }
        func requireOwnPID(_ element: AXUIElement) throws {
            try prepare(element)
            var observed: pid_t = 0
            breadcrumb(.getPIDBegin)
            let error = AXUIElementGetPid(element, &observed)
            breadcrumb(.getPIDReturned)
            guard error == .success else { throw Failure(reason: "get PID AXError=\(error.rawValue)") }
            _ = try remainingTimeout()
            guard observed == pid else { throw Failure(reason: "foreign PID; details withheld") }
        }
        func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
            try prepare(element)
            var value: CFTypeRef?
            breadcrumb(.attributeBegin)
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            breadcrumb(.attributeReturned)
            if error == .noValue || error == .attributeUnsupported {
                append("optional \(field(name)) AXError=\(error.rawValue)")
                _ = try remainingTimeout()
                return nil
            }
            guard error == .success else { throw Failure(reason: "read \(field(name)) AXError=\(error.rawValue)") }
            _ = try remainingTimeout()
            return value
        }
        func elements(_ element: AXUIElement, _ name: String, limit: Int) throws -> [AXUIElement] {
            try prepare(element)
            var count: CFIndex = 0
            breadcrumb(.countBegin)
            let countError = AXUIElementGetAttributeValueCount(element, name as CFString, &count)
            breadcrumb(.countReturned)
            if countError == .noValue || countError == .attributeUnsupported {
                append("array \(field(name)) AXError=\(countError.rawValue)")
                incompleteBranch = true
                _ = try remainingTimeout()
                return []
            }
            guard countError == .success else {
                throw Failure(reason: "count \(field(name)) AXError=\(countError.rawValue)")
            }
            _ = try remainingTimeout()
            guard count >= 0, count <= limit else { throw Failure(reason: "\(field(name)) count exceeds cap \(limit)") }
            guard count > 0 else { return [] }
            try prepare(element)
            var raw: CFArray?
            breadcrumb(.valuesBegin)
            let error = AXUIElementCopyAttributeValues(element, name as CFString, 0, count, &raw)
            breadcrumb(.valuesReturned)
            guard error == .success else { throw Failure(reason: "copy \(field(name)) AXError=\(error.rawValue)") }
            _ = try remainingTimeout()
            guard let values = raw as? [AnyObject], values.count == count else {
                throw Failure(reason: "\(field(name)) changed size or returned malformed array")
            }
            return try values.map { value in
                guard CFGetTypeID(value) == axTypeID else {
                    throw Failure(reason: "\(field(name)) returned a non-AX element")
                }
                return value as! AXUIElement // Type ID was checked before the CF bridge cast.
            }
        }
        do {
            _ = try remainingTimeout()
            breadcrumb(.trustBegin)
            let trusted = AXIsProcessTrusted()
            breadcrumb(.trustReturned)
            append("trusted=\(trusted), ownPID=true, timeoutMaxMs=100, budgetMs=2000")
            _ = try remainingTimeout()
            breadcrumb(.createApplicationBegin)
            let application = AXUIElementCreateApplication(pid)
            breadcrumb(.createApplicationReturned)
            try requireOwnPID(application)
            let windows = try elements(application, kAXWindowsAttribute, limit: 8)
            var matching: [AXUIElement] = []
            for window in windows {
                try requireOwnPID(window)
                if try attribute(window, kAXIdentifierAttribute) as? String == windowMarker {
                    matching.append(window)
                }
            }
            guard matching.count == 1, let ownedWindow = matching.first else {
                throw Failure(reason: "owned window marker matches=\(matching.count); tree withheld")
            }
            var pending: [(AXUIElement, Int)] = [(ownedWindow, 0)]
            var pendingIndex = 0
            while pendingIndex < pending.count {
                _ = try remainingTimeout()
                guard visited.count < 48, rows.count < 78 else { throw Failure(reason: "node or output cap reached") }
                let (element, depth) = pending[pendingIndex]
                pendingIndex += 1
                if visited.contains(where: { CFEqual($0, element) }) { continue }
                try requireOwnPID(element)
                if !CFEqual(element, ownedWindow) {
                    guard let owner = try attribute(element, kAXWindowAttribute),
                          CFGetTypeID(owner) == axTypeID, CFEqual(owner, ownedWindow) else {
                        append("branch withheld: owned-window membership unverified")
                        incompleteBranch = true
                        continue
                    }
                }
                visited.append(element)
                let role = try attribute(element, kAXRoleAttribute) as? String
                let identifier = try attribute(element, kAXIdentifierAttribute) as? String
                let enabled = try attribute(element, kAXEnabledAttribute) as? Bool
                append("node=\(visited.count), depth=\(depth), role=\(field(role ?? "unreported")), " +
                       "id=\(field(identifier ?? "unreported")), enabled=\(enabled.map { String($0) } ?? "unreported")")
                let children = try elements(element, kAXChildrenAttribute, limit: 32)
                if !children.isEmpty {
                    guard depth < 8, pending.count + children.count <= 48 else {
                        throw Failure(reason: "depth or queued-node cap reached")
                    }
                    pending.append(contentsOf: children.map { ($0, depth + 1) })
                }
            }
            complete = !incompleteBranch
        } catch let failure as Failure {
            append("snapshot stopped: \(field(failure.reason))")
        } catch {
            append("snapshot stopped: \(field(String(describing: error)))")
        }
        rows.append("diagnosticComplete=\(complete), visited=\(visited.count); original UI failure remains")
        return rows
    }
}

/// Real hosted production controls, inert capture/transcription, synthetic persistence only.
/// Separate drivers use own accessibility objects or own-window AppKit events; no global AX,
/// system input injection or screen capture. A failed lookup may inspect its marked window
/// through own-PID read-only AX; it never retries or falls back to pointer events afterward.
@MainActor
private struct ScribeComponentFixture {
    private final class Clock { var time: TimeInterval = 100 }

    private final class Capture: ScribeCaptureProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var sink: (@Sendable (ScribeCaptureEvent) -> Void)?
        private var id: ScribeSessionID?
        private var starts = 0
        private var stops = 0
        var startCount: Int { lock.withLock { starts } }
        var stopCount: Int { lock.withLock { stops } }

        func start(session: ScribeSessionID, frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
                   events: @escaping @Sendable (ScribeCaptureEvent) -> Void) {
            lock.withLock { starts += 1; id = session; sink = events }
            events(.captureAcknowledged(session))
        }

        func stop(session: ScribeSessionID) {
            let callback = lock.withLock { () -> (@Sendable (ScribeCaptureEvent) -> Void)? in
                guard id == session else { return nil }
                stops += 1
                return sink
            }
            callback?(.captureEnded(session))
        }
    }

    private struct Transcriber: ScribeTranscriber {
        let callbacks: ScribeTranscriberCallbacks
        func ingest(_ frame: ScribeAudioFrame) { }
        func finish(session: ScribeSessionID) {
            callbacks.onSegment(.init(id: "synthetic-journey", session: session, speaker: .participant("Fixture"),
                start: 0, end: 1, text: "We decided to test the native meeting controls.", isFinal: true))
            callbacks.onFinished(session)
        }
    }

    private final class Writes {
        var rejectFinal = true
        var attemptedFinal = 0
        var savedFinal = 0
        func write(_ record: ScribeMeetingRecord, to store: ScribeMeetingStore) throws {
            if record.generatedAt != nil {
                attemptedFinal += 1
                if rejectFinal { throw ScenarioFailure.injectedFinalWrite }
            }
            try store.save(record)
            if record.generatedAt != nil { savedFinal += 1 }
        }
    }

    private enum ScenarioFailure: Error, CustomStringConvertible {
        case injectedFinalWrite
        case missingControl(String, [String])
        case ambiguousControl(String)
        case unavailableControl(String, String)
        case rejectedPress(String)
        case traversalLimit
        case transitionTimeout(String)
        var description: String {
            switch self {
            case .injectedFinalWrite: return "Synthetic final-write failure"
            case .missingControl(let id, let tree): return "Missing fixture control \(id). Own tree: \(tree.joined(separator: "; "))"
            case .ambiguousControl(let id): return "Multiple fixture controls have \(id)"
            case .unavailableControl(let id, let reason): return "Fixture control is unavailable: \(id) (\(reason))"
            case .rejectedPress(let id): return "Fixture control rejected accessibilityPerformPress: \(id)"
            case .traversalLimit: return "Fixture accessibility tree exceeded its bound"
            case .transitionTimeout(let expected): return "Fixture did not reach \(expected)"
            }
        }
    }

    private let allowedControls: Set<String> = [
        "scribe.start", "scribe.stop", "scribe.notes.close",
        "scribe.endWindow.keep", "scribe.endWindow.endNow", "scribe.endWindow.retrySave", "scribe.endWindow.hide"
    ]

    private func preferences() throws -> (String, UserDefaults) {
        let suite = "scribe-component-\(UUID().uuidString)"
        return (suite, try #require(UserDefaults(suiteName: suite)))
    }

    /// A Swift Testing process does not enter NSApplication.run(). Complete the public AppKit setup
    /// without constructing ZeusMain/AppDelegate or any production services. Each host restores the
    /// original activation policy after its windows close; application launch is performed only once.
    private func prepareFixtureApplication() throws -> NSApplication.ActivationPolicy {
        try OwnedWindowFixtureApplication.prepare()
    }

    private func waitFor(_ name: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ScenarioFailure.transitionTimeout(name)
    }

    private func diagnosticField(_ value: String) -> String {
        String(value.prefix(160)).replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    /// These observations never become press candidates. AppKit can expose an NSControl's
    /// cell instead of its ignored view; compare the public semantic helpers without assigning
    /// roles, changing accessibility state, walking parent links, or requesting system AX access.
    private func appendSemanticDiagnostics(for source: NSView, in window: NSWindow,
                                           diagnostic: inout [String]) {
        guard source.window === window, diagnostic.count < 64 else { return }
        func append(_ label: String, _ value: Any?) {
            guard diagnostic.count < 80 else { return }
            guard let value else { diagnostic.append("semantic probe \(label): nil"); return }
            let object = value as AnyObject
            // Only inspect objects returned from this owned view's descendant APIs. For actual
            // views/cells, verify their concrete owner too; never follow a foreign window.
            if let view = object as? NSView, view.window !== window {
                diagnostic.append("semantic probe \(label): non-owned view; details withheld")
                return
            }
            if let cell = object as? NSCell, cell.controlView?.window !== window {
                diagnostic.append("semantic probe \(label): non-owned cell; details withheld")
                return
            }
            let typeName = diagnosticField(String(reflecting: type(of: object)))
            guard let element = object as? any NSAccessibilityProtocol else {
                diagnostic.append("semantic probe \(label): \(typeName); no NSAccessibilityProtocol conformance")
                return
            }
            let reportedWindow = element.accessibilityWindow()
            if let reportedWindow, (reportedWindow as AnyObject) !== window {
                diagnostic.append("semantic probe \(label): \(typeName); different window object; details withheld")
                return
            }
            let frame = element.accessibilityFrame()
            let finite = [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
            diagnostic.append("semantic probe \(label): \(typeName), sameAsSource=\(object === source), " +
                "element=\(element.isAccessibilityElement()), role=\(diagnosticField(element.accessibilityRole()?.rawValue ?? "nil")), " +
                "id=\(diagnosticField(element.accessibilityIdentifier() ?? "-")), " +
                "enabled=\(element.isAccessibilityEnabled()), " +
                "window=\(reportedWindow == nil ? "unreported" : "owned"), " +
                "finiteFrame=\(finite), emptyFrame=\(frame.isEmpty), intersectsWindow=\(frame.intersects(window.frame))")
        }
        append("raw view", source)
        if let control = source as? NSButton {
            append("raw button cell", control.cell)
            // A plain, single-cell NSButton has the one-to-one hierarchy required by this API.
            // Do not apply it to a SwiftUI hosting root, which can have multiple semantic children.
            if type(of: control) == NSButton.self, control.subviews.isEmpty,
               let cell = control.cell, type(of: cell) == NSButtonCell.self {
                append("unignored button descendant", NSAccessibility.unignoredDescendant(of: control))
            }
        }
        let unignored = NSAccessibility.unignoredChildrenForOnlyChild(from: source)
        if diagnostic.count < 80 {
            diagnostic.append("semantic probe unignored-only-child results=\(unignored.count), reportingFirst=\(min(unignored.count, 8))")
        }
        for (index, element) in unignored.prefix(8).enumerated() {
            append("unignored-only-child[\(index)]", element)
        }
    }

    /// Resolve a fresh tree for every action. There is no application-wide tree or controller fallback.
    private func controls(in window: NSWindow, diagnostic: inout [String]) throws -> [any NSAccessibilityProtocol] {
        guard let root = window.contentView else { return [] }
        root.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        diagnostic.removeAll(keepingCapacity: true)
        diagnostic.append("owned host: visible=\(window.isVisible), key=\(window.isKeyWindow), " +
                          "applicationActive=\(NSApplication.shared.isActive), " +
                          "launchFinished=\(OwnedWindowFixtureApplication.launchFinished)")
        appendSemanticDiagnostics(for: root, in: window, diagnostic: &diagnostic)
        var pending: [(Any, Int)] = [(root, 0)]
        var seen = Set<ObjectIdentifier>()
        var result: [any NSAccessibilityProtocol] = []
        while let (value, depth) = pending.popLast() {
            guard depth <= 32, seen.count < 1_024 else { throw ScenarioFailure.traversalLimit }
            let object = value as AnyObject
            guard seen.insert(ObjectIdentifier(object)).inserted else { continue }
            // Some hosting wrappers expose physical views alongside their semantic children.
            // Both remain descendants of this owned content root; never inspect parent/app links.
            if let view = object as? NSView {
                pending.append(contentsOf: view.subviews.map { ($0, depth + 1) })
                if view is NSButton {
                    appendSemanticDiagnostics(for: view, in: window, diagnostic: &diagnostic)
                }
            }
            let typeName = diagnosticField(String(reflecting: type(of: object)))
            guard let element = object as? any NSAccessibilityProtocol else {
                if diagnostic.count < 80 { diagnostic.append("\(typeName): does not conform to NSAccessibilityProtocol") }
                continue
            }
            result.append(element)
            let children = element.accessibilityChildren() ?? []
            let navigation = element.accessibilityChildrenInNavigationOrder() ?? []
            let contents = element.accessibilityContents() ?? []
            pending.append(contentsOf: children.map { ($0, depth + 1) })
            pending.append(contentsOf: navigation.map { ($0 as Any, depth + 1) })
            pending.append(contentsOf: contents.map { ($0, depth + 1) })
            if diagnostic.count < 80 {
                diagnostic.append("\(typeName):\(diagnosticField(element.accessibilityRole()?.rawValue ?? "?")):" +
                    "\(diagnosticField(element.accessibilityIdentifier() ?? "-")):\(diagnosticField(element.accessibilityLabel() ?? "-")) " +
                    "element=\(element.isAccessibilityElement()), " +
                    "children=\(children.count), navigation=\(navigation.count), contents=\(contents.count)")
            }
        }
        return result
    }

    private func pressDiagnostic(_ element: any NSAccessibilityProtocol, in window: NSWindow) -> String {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        let allowed = element.isAccessibilitySelectorAllowed(selector)
        let facts = "element=\(element.isAccessibilityElement()), " +
            "role=\(diagnosticField(element.accessibilityRole()?.rawValue ?? "nil")), " +
            "enabled=\(element.isAccessibilityEnabled()), selectorAllowed=\(allowed)"
        guard let cell = element as? NSButtonCell, let control = cell.controlView as? NSButton,
              control.window === window, control.cell === cell else {
            return facts + "; ownedButtonCell=false; control details withheld"
        }
        let target = control.target as? NSObject
        let action = control.action
        let targetResponds = action.map { target?.responds(to: $0) ?? false } ?? false
        let fixtureCount = (target as? ButtonTarget).map { String($0.presses) } ?? "unavailable"
        return facts + "; ownedButtonCell=true, controlEnabled=\(control.isEnabled), " +
            "targetPresent=\(target != nil), action=\(diagnosticField(action.map(NSStringFromSelector) ?? "nil")), " +
            "targetResponds=\(targetResponds), fixturePressCount=\(fixtureCount)"
    }

    private func press(_ id: String, in window: NSWindow, trace: inout [String]) async throws {
        guard allowedControls.contains(id) else { throw ScenarioFailure.unavailableControl(id, "not an allowed action") }
        guard window.isVisible else { throw ScenarioFailure.unavailableControl(id, "owning window is hidden") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        var diagnostic: [String] = []
        var lastUnavailableReason: String?
        while ContinuousClock.now < deadline {
            let tree = try controls(in: window, diagnostic: &diagnostic)
            let matches = tree.filter { $0.isAccessibilityElement() && $0.accessibilityIdentifier() == id }
            if matches.count > 1 { throw ScenarioFailure.ambiguousControl(id) }
            if let button = matches.first {
                let frame = button.accessibilityFrame()
                let finite = [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
                guard finite else { throw ScenarioFailure.unavailableControl(id, "nonfinite geometry") }
                // Model transitions precede SwiftUI's layout/animation and accessibility updates.
                // Keep the same deadline for missing and not-yet-ready controls, and always resolve
                // the current object again; never press an unavailable or stale proxy.
                if button.accessibilityRole() != .button {
                    lastUnavailableReason = "identified \(String(reflecting: type(of: button))) has role " +
                        "\(button.accessibilityRole()?.rawValue ?? "nil"), enabled=\(button.isAccessibilityEnabled())"
                } else if !window.isVisible {
                    lastUnavailableReason = "owning window stayed hidden"
                } else if !button.isAccessibilityEnabled() {
                    lastUnavailableReason = "button stayed disabled"
                } else if frame.isEmpty || !frame.intersects(window.frame) {
                    lastUnavailableReason = "button stayed empty or outside its window"
                } else if let view = button as? NSView, view.isHiddenOrHasHiddenAncestor {
                    lastUnavailableReason = "button stayed hidden"
                } else {
                    let before = pressDiagnostic(button, in: window)
                    guard button.accessibilityPerformPress() else {
                        OwnedWindowFixtureApplication.record("rejected semantic press: before=[\(before)]; " +
                            "after=[\(pressDiagnostic(button, in: window))]")
                        throw ScenarioFailure.rejectedPress(id)
                    }
                    trace.append("pressed \(id)")
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        if let lastUnavailableReason {
            // Preserve exact failure reasons (including negative-control assertions) while making
            // wrapper/cell evidence available when a raw object has an identifier but no button role.
            OwnedWindowFixtureApplication.record("accessibility diagnostics for \(id): \(diagnostic.joined(separator: "; "))")
            throw ScenarioFailure.unavailableControl(id, lastUnavailableReason)
        }
        let originalFailure = ScenarioFailure.missingControl(id, diagnostic)
        let marker = window.accessibilityIdentifier()
        if marker.hasPrefix(OwnedProcessAXDiagnostic.windowMarkerPrefix) {
            let snapshot = await OwnedProcessAXDiagnostic.collect(
                pid: ProcessInfo.processInfo.processIdentifier, windowMarker: marker)
            OwnedWindowFixtureApplication.record("failure-only own-PID AX: \(snapshot.joined(separator: "; "))")
        }
        throw originalFailure
    }

    private final class ButtonTarget: NSObject {
        private(set) var presses = 0
        @objc func performAction(_ sender: NSButton) { presses += 1 }
    }

    func waitsForOwnedButtonReadinessAndRejectsPermanentlyDisabledControl() async throws {
        let originalPolicy = try prepareFixtureApplication()
        defer { OwnedWindowFixtureApplication.restore(originalPolicy) }
        let target = ButtonTarget()
        let button = NSButton(title: "Synthetic readiness control", target: target,
                              action: #selector(ButtonTarget.performAction(_:)))
        // AppKit exposes the cell as this standard button's accessibility element. Annotate
        // that actual element, leaving its natural role and the ignored wrapper unchanged.
        let cell = try #require(button.cell as? NSButtonCell)
        cell.setAccessibilityIdentifier("scribe.start")
        button.frame = NSRect(x: 20, y: 20, width: 240, height: 32)
        button.isEnabled = false
        let window = NSWindow(contentRect: NSRect(x: 40, y: 100, width: 300, height: 90),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Synthetic accessibility readiness fixture"
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 90))
        window.contentView = content
        content.addSubview(button)
        defer { OwnedWindowFixtureApplication.close(window) }
        window.makeKeyAndOrderFront(nil)
        #expect(cell.controlView === button)
        #expect(cell.isAccessibilityElement())
        #expect(cell.accessibilityRole() == .button)
        var trace: [String] = []
        let before = target.presses
        try #require(before == 0)
        let enable = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(150))
            #expect(target.presses == 0)
            button.isEnabled = true
        }
        defer { enable.cancel() }
        var nativeAPIReturnedTrue = true
        do {
            try await press("scribe.start", in: window, trace: &trace)
        } catch ScenarioFailure.rejectedPress(let id) where id == "scribe.start" {
            // The recorded native NSButtonCell returned false after synchronously
            // invoking this exact fixture target once. Preserve that raw result;
            // only this synthetic readiness check can observe its retained target.
            // Never retry the action or relax the production journey's strict driver.
            try #require(target.presses == before + 1)
            try #require(trace.isEmpty)
            nativeAPIReturnedTrue = false
            OwnedWindowFixtureApplication.record("readiness fixture: native API returned false; owned target observed once; no retry")
        }
        try await enable.value
        #expect(target.presses == 1)
        #expect(trace == (nativeAPIReturnedTrue ? ["pressed scribe.start"] : []))
        let traceAfterPress = trace

        button.isEnabled = false
        do {
            try await press("scribe.start", in: window, trace: &trace)
            Issue.record("A permanently disabled owned control was pressed")
        } catch ScenarioFailure.unavailableControl(let id, let reason) {
            #expect(id == "scribe.start")
            #expect(reason == "button stayed disabled")
        }
        #expect(target.presses == 1)
        #expect(trace == traceAfterPress)
    }

    func persistentWrongAccessibilityRoleNeverReceivesAPress() async throws {
        let originalPolicy = try prepareFixtureApplication()
        defer { OwnedWindowFixtureApplication.restore(originalPolicy) }
        let target = ButtonTarget()
        let button = NSButton(title: "Synthetic mismatched role", target: target,
                              action: #selector(ButtonTarget.performAction(_:)))
        let cell = try #require(button.cell as? NSButtonCell)
        cell.setAccessibilityIdentifier("scribe.start")
        cell.setAccessibilityRole(.staticText)
        button.isEnabled = true
        button.frame = NSRect(x: 20, y: 20, width: 240, height: 32)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 90))
        content.addSubview(button)
        let window = NSWindow(contentRect: NSRect(x: 40, y: 100, width: 300, height: 90),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Synthetic wrong accessibility role fixture"
        window.isReleasedWhenClosed = false
        window.contentView = content
        defer { OwnedWindowFixtureApplication.close(window) }
        window.makeKeyAndOrderFront(nil)
        #expect(cell.controlView === button)
        #expect(cell.isAccessibilityElement())
        #expect(cell.accessibilityRole() == .staticText)
        var trace: [String] = []
        do {
            try await press("scribe.start", in: window, trace: &trace)
            Issue.record("A control with a persistent mismatched accessibility role was pressed")
        } catch ScenarioFailure.unavailableControl(let id, let reason) {
            #expect(id == "scribe.start")
            #expect(reason.contains("has role"))
        }
        #expect(target.presses == 0)
        #expect(trace.isEmpty)
    }

    func runJourney(useWindowEvents: Bool) async throws {
        let originalPolicy = try prepareFixtureApplication()
        defer { OwnedWindowFixtureApplication.restore(originalPolicy) }
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-component-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScribeMeetingStore(directory: root)
        let clock = Clock(), capture = Capture(), writes = Writes()
        let registry = useWindowEvents ? OwnedWindowControlRegistry() : nil
        let eventDriver = registry.map { OwnedWindowEventDriver(registry: $0) }
        let endWindow = ScribeEndWindow(journeyRegistry: registry)
        let controller = ScribeController(provider: capture, monotonicClock: { clock.time }, store: store,
            transcriberFactory: { _, callbacks in Transcriber(callbacks: callbacks) }, showsEndWindow: true,
            writeMeeting: { try writes.write($0, to: store) }, cancellationDefaults: defaults,
            endWindow: endWindow, transcriptionEngine: { .apple })
        let topBar = TopBarModel(defaults: defaults)
        let host = NSHostingView(rootView: ScribePage(topBar: topBar, scribe: controller)
            .environment(\.cardFinishOverride, .liquidGlass)
            .environment(\.ownedWindowControlRegistry, registry)
            .frame(width: 870, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 40, y: 100, width: 870, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Synthetic Scribe component fixture"
        window.setAccessibilityIdentifier(OwnedProcessAXDiagnostic.windowMarkerPrefix + UUID().uuidString)
        window.contentView = host
        window.isReleasedWhenClosed = false
        defer {
            // Teardown is not an asserted user action. Release the actual hosted controller/window cycle.
            OwnedWindowFixtureApplication.record("Scribe teardown begin")
            controller.cancel()
            endWindow.close()
            OwnedWindowFixtureApplication.record("Scribe controller/end-window teardown returned")
            OwnedWindowFixtureApplication.close(window)
        }
        window.makeKeyAndOrderFront(nil)
        var trace: [String] = []
        eventDriver?.register(window)
        func activate(_ id: String, in ownedWindow: NSWindow, trace: inout [String]) async throws {
            if let eventDriver {
                try await eventDriver.click(id, in: ownedWindow)
                trace.append("pressed \(id)")
            } else {
                try await press(id, in: ownedWindow, trace: &trace)
            }
        }

        try await activate("scribe.start", in: window, trace: &trace)
        try await waitFor("recording") { controller.isRecording }
        let id = try #require(controller.phase.sessionID)
        #expect(capture.startCount == 1)
        #expect(capture.stopCount == 0)

        try await activate("scribe.stop", in: window, trace: &trace)
        try await waitFor("visible end window") { endWindow.panel?.isVisible == true && controller.endingRemaining == 9 }
        let endPanel = try #require(endWindow.panel)
        eventDriver?.register(endPanel)
        try await activate("scribe.endWindow.keep", in: endPanel, trace: &trace)
        try await waitFor("recording after Keep") { controller.phase == .recording(id, since: clock.time) }
        #expect(!endPanel.isVisible)
        #expect(capture.stopCount == 0)

        try await activate("scribe.stop", in: window, trace: &trace)
        try await waitFor("second end window") { endPanel.isVisible && controller.endingRemaining == 9 }
        try await activate("scribe.endWindow.endNow", in: endPanel, trace: &trace)
        try await waitFor("recoverable final-save failure") { controller.completionSaveIssue != nil }
        #expect(controller.phase == .processing(id))
        #expect(capture.stopCount == 1)
        #expect(writes.attemptedFinal == 1)
        #expect(writes.savedFinal == 0)
        #expect(controller.completedNoticeID == nil)
        #expect(controller.topBarFeedback()?.phase == .failed)

        writes.rejectFinal = false // Change the injected storage dependency, not the UI/controller state.
        try await activate("scribe.endWindow.retrySave", in: endPanel, trace: &trace)
        try await waitFor("durably saved completion") { controller.phase == .complete(id) }
        #expect(writes.savedFinal == 1)
        #expect(controller.completedNoticeID == id)
        #expect(controller.topBarFeedback()?.phase == .completed)
        #expect(store.loadAll().records.first(where: { $0.id == id.rawValue })?.generatedAt != nil)

        try await activate("scribe.endWindow.hide", in: endPanel, trace: &trace)
        #expect(!endPanel.isVisible)
        #expect(controller.phase == .complete(id))
        // Respect either OS accessibility preference; do not press the notes controls while their
        // real production reveal still gives them zero opacity.
        try await waitFor("visible completed notes") {
            controller.revealElapsed(at: Date()) >= max(ScribeGlow.revealDuration(reduceMotion: false),
                                                       ScribeGlow.revealDuration(reduceMotion: true))
        }
        try await activate("scribe.notes.close", in: window, trace: &trace)
        try await waitFor("idle after Done") { controller.phase == .idle }
        #expect(controller.completedNoticeID == nil)
        #expect(controller.recaps.contains(where: { $0.id == id }))
        #expect(capture.stopCount == 1)
        #expect(trace == ["pressed scribe.start", "pressed scribe.stop", "pressed scribe.endWindow.keep",
                          "pressed scribe.stop", "pressed scribe.endWindow.endNow", "pressed scribe.endWindow.retrySave",
                          "pressed scribe.endWindow.hide", "pressed scribe.notes.close"])
        print("Synthetic Scribe component interaction completed via \(useWindowEvents ? "owned-window events" : "accessibility"): " + trace.joined(separator: " → "))
    }

    func modelPreferencesReadAndWriteOnlyTheInjectedSuite() throws {
        let (suite, defaults) = try preferences()
        let (otherSuite, other) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite); other.removePersistentDomain(forName: otherSuite) }
        defaults.set("Synthetic initial note", forKey: "topBar.note")
        defaults.set("Synthetic initial script", forKey: "prompter.script")
        other.set("Independent fixture", forKey: "topBar.note")
        let model = TopBarModel(defaults: defaults)
        #expect(model.note == "Synthetic initial note")
        #expect(model.script == "Synthetic initial script")
        model.note = "Synthetic edited note"
        model.script = "Synthetic edited script"
        model.cuesEnabled = false
        model.liveMusicWings = false
        model.weatherCity = "Fixture city"
        model.useCelsius = false
        model.selectedModeKey = "fixture-mode"
        model.prompterTextSize = 21
        model.roll.speed = 17
        model.roll.voiceFollow = false
        #expect(defaults.string(forKey: "topBar.note") == "Synthetic edited note")
        #expect(defaults.string(forKey: "prompter.script") == "Synthetic edited script")
        #expect(defaults.bool(forKey: "topBar.cues") == false)
        #expect(defaults.bool(forKey: "topBar.musicWings") == false)
        #expect(defaults.string(forKey: "topBar.weatherCity") == "Fixture city")
        #expect(defaults.string(forKey: "dictation.mode") == "fixture-mode")
        #expect(defaults.double(forKey: "prompter.size") == 21)
        #expect(defaults.double(forKey: "prompter.speed") == 17)
        #expect(defaults.bool(forKey: "prompter.voice") == false)
        #expect(other.string(forKey: "topBar.note") == "Independent fixture")
    }

    func temporaryMeetingStoreCannotClearAnotherCancellationJournal() throws {
        let (suite, defaults) = try preferences()
        let (otherSuite, other) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite); other.removePersistentDomain(forName: otherSuite) }
        let localID = UUID(), otherID = UUID()
        ScribeCancelTombstones.add(localID, in: defaults)
        ScribeCancelTombstones.add(otherID, in: other)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-journal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ScribeController(store: ScribeMeetingStore(directory: root), cancellationDefaults: defaults,
                                          transcriptionEngine: { .apple })
        #expect(controller.recaps.isEmpty)
        #expect(ScribeCancelTombstones.ids(in: defaults).isEmpty)
        #expect(ScribeCancelTombstones.ids(in: other) == [otherID])
    }
}


/// Actual production controls activated with locally targeted AppKit events and current layout.
@MainActor @Suite("Scribe native component event journey", .serialized)
struct ScribeComponentJourneyTests {
    @Test func layoutResolvedEventsDriveStartKeepStopFailedSaveRetryAndClose() async throws {
        try await OwnedWindowJourneyLease.perform { try await ScribeComponentFixture().runJourney(useWindowEvents: true) }
    }

    @Test func modelPreferencesReadAndWriteOnlyTheInjectedSuite() throws {
        try ScribeComponentFixture().modelPreferencesReadAndWriteOnlyTheInjectedSuite()
    }

    @Test func temporaryMeetingStoreCannotClearAnotherCancellationJournal() throws {
        try ScribeComponentFixture().temporaryMeetingStoreCannotClearAnotherCancellationJournal()
    }
}

/// Kept as separate required proof. Missing native AX roles/children still fails these assertions;
/// a successful pointer event must never be substituted for a missing accessibility result.
@MainActor @Suite("Scribe native accessibility journey", .serialized)
struct ScribeAccessibilityJourneyTests {
    @Test func waitsForOwnedButtonReadinessAndRejectsPermanentlyDisabledControl() async throws {
        try await OwnedWindowJourneyLease.perform {
            try await ScribeComponentFixture().waitsForOwnedButtonReadinessAndRejectsPermanentlyDisabledControl()
        }
    }

    @Test func realButtonsDriveStartKeepStopFailedSaveRetryAndClose() async throws {
        try await OwnedWindowJourneyLease.perform { try await ScribeComponentFixture().runJourney(useWindowEvents: false) }
    }

    @Test func persistentWrongAccessibilityRoleNeverReceivesAPress() async throws {
        try await OwnedWindowJourneyLease.perform {
            try await ScribeComponentFixture().persistentWrongAccessibilityRoleNeverReceivesAPress()
        }
    }
}
