import AppKit
import ApplicationServices
import ZeusCore

/// Takes `AXSnapshot`s of the frontmost app's focused window and keeps the live AX elements behind
/// each ref, so a drive step can act on "s4:e7" without searching again. Each capture gets a new
/// id; refs from older captures resolve to `.staleRef`. Only the newest capture keeps live
/// elements; a few older models are kept so a stale ref can be found again by role and label.
@MainActor
final class AXSnapshotter {
    static let shared = AXSnapshotter()

    /// The same cap as the title search in `AXFinder`.
    static let maxElements = 3_000

    private var nextID = 1
    private(set) var latest: AXSnapshot?
    private var handles: [AXUIElement] = []
    private var models: [Int: AXSnapshot] = [:]

    /// Walks the focused window breadth-first, stopping at `maxElements` or after `budget`
    /// seconds. Hidden elements, and elements outside the screen, window or their scroll area,
    /// are skipped. Nil without Accessibility access, or when ZEUS itself is in front.
    @discardableResult
    func capture(budget: TimeInterval = 0.3, maxElements: Int = AXSnapshotter.maxElements) -> AXSnapshot? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // A hung app answers each call only after the messaging timeout; keep it short.
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        let window = Self.element(appElement, kAXFocusedWindowAttribute) ?? Self.element(appElement, kAXMainWindowAttribute)
        let root = window ?? appElement
        let deadline = Date().addingTimeInterval(budget)
        let screens = NSScreen.screens.map { Self.quartzRect($0.frame) }.reduce(CGRect.null) { $0.union($1) }

        var elements: [AXSnapshotElement] = []
        var live: [AXUIElement] = []
        var queue: [(element: AXUIElement, clip: CGRect)] = [(root, screens)]
        var head = 0
        var truncated = false
        while head < queue.count {
            if live.count >= maxElements || Date() > deadline { truncated = true; break }
            let (element, parentClip) = queue[head]
            head += 1
            let attributes = Self.attributes(element)
            if attributes.hidden { continue }
            var clip = parentClip
            if let frame = attributes.frame, frame.width > 0, frame.height > 0 {
                // Fully outside what can be seen: skip it and everything inside it.
                guard frame.intersects(parentClip) else { continue }
                if ["AXWindow", "AXScrollArea"].contains(attributes.role) { clip = parentClip.intersection(frame) }
                if !CFEqual(element, root) {
                    elements.append(AXSnapshotElement(
                        role: attributes.role, subrole: attributes.subrole, label: attributes.label,
                        value: attributes.isSecure ? nil : attributes.value, enabled: attributes.enabled,
                        focused: attributes.focused, frame: frame, actions: Self.actions(element)))
                    live.append(element)
                }
            }
            queue += attributes.children.map { ($0, clip) }
        }

        let id = nextID
        nextID += 1
        let snapshot = AXSnapshot(id: id, app: app.localizedName ?? "the front app",
                                  window: window.flatMap { AXFinder.string($0, kAXTitleAttribute) }.flatMap { $0.isEmpty ? nil : $0 },
                                  elements: elements, truncated: truncated)
        latest = snapshot
        handles = live
        models[id] = snapshot
        models = models.filter { $0.key > id - 4 }
        NSLog("[ZEUS] drive: snapshot s%d of %@: %d elements%@", id, snapshot.app, elements.count, truncated ? " (stopped early)" : "")
        return snapshot
    }

    /// The model element for a ref from any recent snapshot, for labelling a plan's card.
    func model(for ref: String) -> AXSnapshotElement? {
        guard let parsed = AXRef(ref), let snapshot = models[parsed.snapshot] else { return nil }
        return try? snapshot.element(ref)
    }

    /// The live element for a ref from the newest snapshot. With `relocate`, a ref from an older
    /// snapshot is looked up again by role and label in the newest one.
    func resolve(_ ref: String, relocate: Bool) throws -> (AXSnapshotElement, AXUIElement) {
        guard let latest else { throw AXSnapshotError.staleRef(ref: ref, current: 0) }
        do {
            let element = try latest.element(ref)
            return (element, handles[element.ref.index - 1])
        } catch AXSnapshotError.staleRef(let stale, let current) {
            guard relocate, let old = model(for: stale), let found = latest.relocate(old) else {
                throw AXSnapshotError.staleRef(ref: stale, current: current)
            }
            NSLog("[ZEUS] drive: %@ found again as %@", stale, found.ref.description)
            return (found, handles[found.ref.index - 1])
        }
    }

    // MARK: Reading attributes

    struct Attributes {
        var role = ""
        var subrole: String?
        var label: String?
        var value: String?
        var enabled = true
        var focused = false
        var hidden = false
        var frame: CGRect?
        var children: [AXUIElement] = []
        var isSecure: Bool { role == "AXSecureTextField" || subrole == "AXSecureTextField" }
    }

    static let wanted = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
                         kAXPlaceholderValueAttribute, kAXValueAttribute, kAXEnabledAttribute, kAXFocusedAttribute,
                         "AXHidden", kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute]

    /// One round trip for all the attributes a snapshot needs. Missing ones come back as errors.
    static func attributes(_ element: AXUIElement) -> Attributes {
        var raw: CFArray?
        var out = Attributes()
        guard AXUIElementCopyMultipleAttributeValues(element, wanted as CFArray, [], &raw) == .success,
              let values = raw as? [AnyObject], values.count == wanted.count else { return out }
        func text(_ i: Int) -> String? {
            guard let s = values[i] as? String else { return nil }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func flag(_ i: Int) -> Bool? { (values[i] as? NSNumber)?.boolValue }
        out.role = text(0) ?? ""
        out.subrole = text(1)
        out.label = text(2) ?? text(3) ?? text(4)
        if out.isSecure {
            out.value = nil
        } else if let string = text(5) {
            out.value = String(string.prefix(200))
        } else if let number = values[5] as? NSNumber, CFGetTypeID(number) != AXValueGetTypeID() {
            out.value = number.stringValue
        }
        if out.label == nil, out.role == "AXStaticText" { out.label = out.value.map { String($0.prefix(120)) } }
        out.enabled = flag(6) ?? true
        out.focused = flag(7) ?? false
        out.hidden = flag(8) ?? false
        var point = CGPoint.zero
        var size = CGSize.zero
        if CFGetTypeID(values[9]) == AXValueGetTypeID(), CFGetTypeID(values[10]) == AXValueGetTypeID(),
           AXValueGetValue(values[9] as! AXValue, .cgPoint, &point), AXValueGetValue(values[10] as! AXValue, .cgSize, &size) { // swiftlint:disable:this force_cast
            out.frame = CGRect(origin: point, size: size)
        }
        out.children = (values[11] as? [AXUIElement]) ?? []
        return out
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement) // swiftlint:disable:this force_cast
    }

    /// AppKit screen frame (bottom-left origin) to Quartz (top-left of the main screen).
    static func quartzRect(_ r: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height)
    }
}
