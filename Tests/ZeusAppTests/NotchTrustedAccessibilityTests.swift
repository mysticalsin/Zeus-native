import AppKit
import ApplicationServices
import Foundation
import SwiftUI
import Testing
import ZeusCore
@testable import Zeus

/// What an outside accessibility client (VoiceOver, Switch Control, a QA driver) can do to the real `NotchView`:
/// AXPress on a tab must switch the page, and AXPress on the closed notch body must ask to open the panel.
/// `.accessibilityElement(children: .ignore)` used to replace each tab Button with an element that had no default
/// action, so the press did nothing. SwiftUI exposes no accessibility children inside its own process unless this
/// process is a trusted assistive client, so CI never selects this suite (it is in `TRUSTED_SUITES`). Run it from
/// a trusted terminal in the bundled test host with filter `^ZeusAppTests\.NotchTrustedAccessibilityTests/`, launched the
/// way `qa/closed-loop/trusted_ax.py` launches it. That runner and its receipt only cover the Scribe trusted suite today,
/// so there is no recorded receipt for this one yet. It fails, never skips, when the process is not trusted.
/// Own PID and own marked window only: no other app is read and no global event is posted.
@MainActor @Suite("Notch trusted accessibility actions", .inNativeHost, .serialized)
struct NotchTrustedAccessibilityTests {
    private static let marker = "zeus.synthetic.notch.window."

    private enum Outcome {
        case pressed(actions: [String])
        case missing(String)
        case rejected(Int32, actions: [String])
    }

    /// One synchronous attempt on the main actor: re-resolve the element from the application, read its action names,
    /// then press it. Elements are never kept across attempts.
    private static func press(_ id: String, windowMarker: String) -> Outcome {
        let pid = ProcessInfo.processInfo.processIdentifier
        let typeID = AXUIElementGetTypeID()
        func read(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            AXUIElementSetMessagingTimeout(element, 0.5)
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        func children(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
            (read(element, name) as? [AnyObject] ?? []).prefix(80).compactMap { CFGetTypeID($0) == typeID ? ($0 as! AXUIElement) : nil }
        }
        let application = AXUIElementCreateApplication(pid)
        var owner: pid_t = 0
        guard AXUIElementGetPid(application, &owner) == .success, owner == pid else { return .missing("not this process") }
        let windows = children(application, kAXWindowsAttribute) + children(application, kAXChildrenAttribute)
        guard let window = windows.first(where: { read($0, kAXIdentifierAttribute) as? String == windowMarker }) else {
            return .missing("no window with the marker among \(windows.count)")
        }
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var index = 0
        var seen: [String] = []
        while index < queue.count, index < 800 {
            let (element, depth) = queue[index]
            index += 1
            if let identifier = read(element, kAXIdentifierAttribute) as? String {
                if seen.count < 40 { seen.append(identifier) }
                if identifier == id {
                    var names: CFArray?
                    AXUIElementCopyActionNames(element, &names)
                    let actions = names as? [String] ?? []
                    AXUIElementSetMessagingTimeout(element, 1.0)
                    let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
                    return error == .success ? .pressed(actions: actions) : .rejected(error.rawValue, actions: actions)
                }
            }
            if depth < 16 { queue += children(element, kAXChildrenAttribute).map { ($0, depth + 1) } }
        }
        return .missing("no \(id) in \(index) nodes; identifiers: \(seen.joined(separator: ","))")
    }

    private func pressWhenReady(_ id: String, in window: NSWindow) async throws -> [String] {
        guard AXIsProcessTrusted() else {
            throw Failure(reason: "this process is not trusted for accessibility (AXIsProcessTrusted is false); run it from a trusted terminal")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var last = "no attempt ran"
        while ContinuousClock.now < deadline {
            switch Self.press(id, windowMarker: window.accessibilityIdentifier()) {
            case .pressed(let actions): return actions
            case .rejected(let code, let actions): throw Failure(reason: "AXPress on \(id) rejected (AXError \(code)); actions \(actions)")
            case .missing(let reason): last = reason
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw Failure(reason: last)
    }

    private struct Failure: Error, CustomStringConvertible { let reason: String; var description: String { reason } }

    private func host(_ model: NotchModel, _ topBar: TopBarModel, openPanel: @escaping () -> Void) -> NSWindow {
        let root = NotchView(model: model, topBar: topBar, footprintOverride: .hardware(CGSize(width: 220, height: 38)),
                             topOffsetOverride: 0, openPanel: openPanel)
            .frame(width: 960, height: 400)
        let window = NSWindow(contentRect: NSRect(x: 40, y: 100, width: 960, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setAccessibilityIdentifier(Self.marker + UUID().uuidString)
        window.contentView = NSHostingView(rootView: root)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func topBar() -> TopBarModel {
        TopBarModel(defaults: UserDefaults(suiteName: NSTemporaryDirectory() + "notch-ax-\(UUID().uuidString)")!)
    }

    @Test(arguments: [TopBarTab.shelf, .scribe, .chat])
    func pressingATabThroughAccessibilitySwitchesThePage(tab: TopBarTab) async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let model = NotchModel()
            model.presentation = .panel
            let bar = topBar()
            #expect(bar.selectedTab == .home)
            let window = host(model, bar) {}
            defer { OwnedWindowFixtureApplication.close(window) }
            let actions = try await pressWhenReady("notch.tab.\(tab.rawValue)", in: window)
            #expect(actions.contains(kAXPressAction as String), "notch.tab.\(tab.rawValue) lists no AXPress: \(actions)")
            #expect(bar.selectedTab == tab, "AXPress on notch.tab.\(tab.rawValue) left \(bar.selectedTab) selected")
        }
    }

    @Test func pressingTheClosedNotchBodyThroughAccessibilityAsksToOpenThePanel() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let model = NotchModel()
            model.presentation = .closed
            var opened = 0
            let window = host(model, topBar()) { opened += 1 }
            defer { OwnedWindowFixtureApplication.close(window) }
            let actions = try await pressWhenReady("notch.body", in: window)
            #expect(actions.contains(kAXPressAction as String), "notch.body lists no AXPress: \(actions)")
            #expect(opened == 1, "AXPress on the closed notch body did not ask to open the panel")
        }
    }
}
