import AppKit
import ApplicationServices
import Foundation
import ZeusCore

/// Names from the call window. Each source knows one call app: which running apps may hold the call, which of
/// their windows look like a call, and how the app's tree maps to participants (`MeetingTileExtractor`).
/// Everything here runs on the main actor, and only while `AXIsProcessTrusted()` is already true: Zeus never asks
/// for Accessibility from this code. The reads are bounded in nodes and time so a busy browser cannot stall the UI.
@MainActor
protocol MeetingSpeakerSource {
    var app: MeetingAppKind { get }
    /// Bundle identifiers of the apps that can hold this call.
    var bundleIdentifiers: [String] { get }
    /// True when a window with this title may be the call window (cheap check before any tree walk).
    func looksLikeCallWindow(title: String) -> Bool
    /// Chromium and Electron apps draw their window contents into an Accessibility tree only when asked.
    var needsWebAccessibility: Bool { get }
}

struct ZoomSpeakerSource: MeetingSpeakerSource {
    let app = MeetingAppKind.zoom
    let bundleIdentifiers = ["us.zoom.xos"]
    let needsWebAccessibility = false
    func looksLikeCallWindow(title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("meeting") || lower.contains("zoom") || lower.contains("r\u{00E9}union")
    }
}

struct TeamsSpeakerSource: MeetingSpeakerSource {
    let app = MeetingAppKind.teams
    let bundleIdentifiers = ["com.microsoft.teams2", "com.microsoft.teams"]
    let needsWebAccessibility = true
    func looksLikeCallWindow(title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("teams") || lower.contains("meeting") || lower.contains("call") || lower.contains("r\u{00E9}union")
            || lower.contains("appel")
    }
}

struct MeetSpeakerSource: MeetingSpeakerSource {
    let app = MeetingAppKind.meet
    /// Chrome, Safari, Arc and Edge.
    let bundleIdentifiers = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac"]
    let needsWebAccessibility = true
    func looksLikeCallWindow(title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("meet") && !lower.contains("meeting notes")
    }
}

struct SlackHuddleSpeakerSource: MeetingSpeakerSource {
    let app = MeetingAppKind.slack
    let bundleIdentifiers = ["com.tinyspeck.slackmacgap"]
    let needsWebAccessibility = true
    func looksLikeCallWindow(title: String) -> Bool { title.lowercased().contains("huddle") }
}

/// A bounded copy of a window's Accessibility tree as `MeetingAXNode`s.
@MainActor
enum MeetingAXSnapshotter {
    static let maxNodes = 900
    static let maxDepth = 30

    /// Nil when the tree could not be read at all.
    static func snapshot(window: AXUIElement, deadline: Date) -> MeetingAXNode? {
        var budget = maxNodes
        return node(window, depth: 0, budget: &budget, deadline: deadline)
    }

    private static func node(_ element: AXUIElement, depth: Int, budget: inout Int, deadline: Date) -> MeetingAXNode? {
        guard budget > 0, depth <= maxDepth, Date() < deadline else { return nil }
        budget -= 1
        var texts: [String] = []
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            if let text = string(element, name), !text.isEmpty, text.count <= 200 { texts.append(text) }
        }
        let classes = strings(element, "AXDOMClassList")
        var kids: [MeetingAXNode] = []
        for child in children(element) {
            guard let kid = node(child, depth: depth + 1, budget: &budget, deadline: deadline) else { break }
            kids.append(kid)
        }
        return MeetingAXNode(role: string(element, kAXRoleAttribute) ?? "", texts: texts, classes: classes, children: kids)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }

    static func strings(_ element: AXUIElement, _ name: String) -> [String] {
        (attribute(element, name) as? [Any])?.compactMap { $0 as? String } ?? []
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let raw = attribute(element, kAXChildrenAttribute) as? [Any] else { return [] }
        return raw.map { $0 as! AXUIElement } // swiftlint:disable:this force_cast
    }
}

/// Reads the call window while Scribe records. `poll(now:)` is cheap when nothing is due; the walk is bounded.
/// It never prompts, never reads while Accessibility is not already granted, never touches Zeus's own process,
/// and restores the one setting it may switch on in a browser or Electron app when the session ends.
@MainActor
final class MeetingSpeakerMonitor {
    static let pollInterval: TimeInterval = 0.7
    static let walkBudget: TimeInterval = 0.08

    private let sources: [any MeetingSpeakerSource]
    private let trusted: () -> Bool
    private var lastPoll = -TimeInterval.infinity
    /// Apps whose web accessibility this monitor switched on, with the value to put back.
    private var switchedOn: [pid_t: Bool] = [:]
    private(set) var consecutiveEmptyPolls = 0

    init(
        sources: [any MeetingSpeakerSource] = [ZoomSpeakerSource(), TeamsSpeakerSource(), MeetSpeakerSource(), SlackHuddleSpeakerSource()],
        trusted: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.sources = sources
        self.trusted = trusted
    }

    /// Whether Accessibility is already granted. Names from the call window work only then.
    var isAvailable: Bool { trusted() }

    /// One reading when one is due (at most every `pollInterval`), stamped `elapsed`. Nil when not due, not
    /// trusted, or no call window with participants is on screen.
    func poll(now: TimeInterval, elapsed: TimeInterval) -> MeetingSpeakerObservation? {
        guard now - lastPoll >= Self.pollInterval || now < lastPoll else { return nil }
        lastPoll = now
        guard trusted() else { return nil }
        let deadline = Date().addingTimeInterval(Self.walkBudget)
        var readings: [MeetingWindowReading] = []
        for source in sources {
            readings += read(source, deadline: deadline)
        }
        guard let observation = MeetingWindowArbiter.observation(at: elapsed, readings: readings) else {
            consecutiveEmptyPolls += 1
            return nil
        }
        consecutiveEmptyPolls = 0
        return observation
    }

    /// Puts back what was switched on. Called when the session ends or is cancelled.
    func stop() {
        for (pid, previous) in switchedOn {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { continue }
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, previous ? kCFBooleanTrue : kCFBooleanFalse)
        }
        switchedOn = [:]
    }

    private func read(_ source: any MeetingSpeakerSource, deadline: Date) -> [MeetingWindowReading] {
        var readings: [MeetingWindowReading] = []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for running in NSWorkspace.shared.runningApplications where !running.isTerminated {
            guard let bundle = running.bundleIdentifier, source.bundleIdentifiers.contains(bundle),
                  running.processIdentifier != ownPID, Date() < deadline else { continue }
            let element = AXUIElementCreateApplication(running.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.15)
            if source.needsWebAccessibility { enableWebAccessibility(element, pid: running.processIdentifier) }
            guard let windows = MeetingAXSnapshotter.attribute(element, kAXWindowsAttribute) as? [Any] else { continue }
            for (index, raw) in windows.enumerated() {
                guard Date() < deadline else { break }
                let window = raw as! AXUIElement // swiftlint:disable:this force_cast
                let title = MeetingAXSnapshotter.string(window, kAXTitleAttribute) ?? ""
                guard source.looksLikeCallWindow(title: title),
                      let root = MeetingAXSnapshotter.snapshot(window: window, deadline: deadline) else { continue }
                let tiles = MeetingTileExtractor.participants(app: source.app, root: root)
                // A window that shows nobody is not a call window, whatever its title says.
                guard !tiles.isEmpty else { continue }
                readings.append(MeetingWindowReading(app: source.app, windowID: "\(running.processIdentifier)-\(index)", participants: tiles))
            }
        }
        return readings
    }

    private func enableWebAccessibility(_ element: AXUIElement, pid: pid_t) {
        guard switchedOn[pid] == nil else { return }
        let previous = (MeetingAXSnapshotter.attribute(element, "AXManualAccessibility") as? Bool) ?? false
        if previous { return }
        if AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success {
            switchedOn[pid] = previous
        }
    }
}
