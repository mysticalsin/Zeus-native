import Foundation

/// How much ZEUS may do on its own when it drives the Mac.
public enum DriveAutonomy: String, CaseIterable, Sendable {
    /// Every plan waits for a yes.
    case ask
    /// Plans made only of safe or undoable steps (move, scroll, open an app, type into a
    /// field) run at once; a click or a shortcut waits for a yes. The default.
    case safe
    /// Everything runs except high-risk steps: send, delete, pay or quit, replacing the
    /// clipboard, or anything aimed at a password field.
    case trusted

    public static let settingsKey = "drive.autonomy"
    public static let `default`: DriveAutonomy = .safe

    /// The picker label.
    public var title: String {
        switch self {
        case .ask: return "Always ask"
        case .safe: return "Safe steps alone"
        case .trusted: return "Trusted"
        }
    }

    /// The one line under the picker.
    public var explanation: String {
        switch self {
        case .ask: return "Every drive plan waits for your yes. Esc stops Zeus."
        case .safe: return "Opening apps, scrolling and typing you can undo run at once; the rest waits for your yes. Esc stops Zeus."
        case .trusted: return "Low- and medium-risk steps run at once; sending, deleting, the clipboard and password fields always ask. Esc stops Zeus."
        }
    }
}

/// Where a step acts: a snapshot ref (preferred), an element title to find with Accessibility,
/// a screenshot point, or a mix. `secure` is filled from the snapshot, never from the plan.
public struct DriveTarget: Equatable, Sendable {
    public var ref: String?
    public var label: String?
    public var x: Int?
    public var y: Int?
    public var screen: Int?
    /// The ref resolved to a password field (AXSecureTextField).
    public var secure: Bool

    public init(ref: String? = nil, label: String? = nil, x: Int? = nil, y: Int? = nil, screen: Int? = nil, secure: Bool = false) {
        self.ref = ref
        self.label = label
        self.x = x
        self.y = y
        self.screen = screen
        self.secure = secure
    }

    public var hasPoint: Bool { x != nil && y != nil }
    /// Something to aim at: a ref, a label or a point.
    public var isSpecified: Bool { hasPoint || ref != nil || label != nil }
}

public enum DriveStep: Equatable, Sendable {
    case openApp(String)
    case move(DriveTarget)
    case click(DriveTarget, double: Bool)
    case type(String, into: DriveTarget?)
    case key(String)
    case scroll(Int)
    case wait(Double)
    /// Puts text straight into the element's AXValue; nothing is typed.
    case setValue(DriveTarget, String)
    /// Picks `option` in a pop-up button, menu, tab group or list.
    case select(DriveTarget, option: String)
    /// Sets a checkbox or switch; a no-op when it is already that way.
    case toggle(DriveTarget, on: Bool)
    /// Opens a disclosure triangle, outline row or menu.
    case expand(DriveTarget)
    /// Brings a running app forward, and one of its windows when `title` is given.
    case focusWindow(app: String, title: String?)
    /// Reads the clipboard text; later steps use it as {clipboard}.
    case readClipboard
    case writeClipboard(String)

    public enum Risk: Int, Comparable, Sendable {
        case safe, undoable, risky, destructive
        public static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }
    }

    static let destructiveWords = ["send", "delete", "remove", "erase", "pay", "buy", "purchase", "submit",
                                   "quit", "trash", "discard", "unsubscribe", "transfer", "sign out", "log out", "post"]
    static let destructiveKeys: Set<String> = ["cmd+q", "cmd+delete", "cmd+backspace", "cmd+shift+delete", "cmd+w",
                                                "cmd+option+esc", "return", "enter", "cmd+return", "cmd+enter"]

    /// Words in a label that mean a secret: setting such a field is high risk even without a snapshot.
    static let secretWords: Set<String> = ["password", "passcode", "passphrase", "pin", "secret", "cvv", "cvc", "otp", "token"]
    static let secretPhrases = ["card number", "security code", "api key", "verification code"]

    static func isDestructive(_ texts: String?...) -> Bool {
        texts.contains { text in
            let lower = (text ?? "").lowercased()
            return destructiveWords.contains { lower.contains($0) }
        }
    }

    static func looksSecret(_ target: DriveTarget) -> Bool {
        if target.secure { return true }
        let label = (target.label ?? "").lowercased()
        let words = Set(label.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return !words.isDisjoint(with: secretWords) || secretPhrases.contains { label.contains($0) }
    }

    public var risk: Risk {
        switch self {
        case .openApp, .move, .scroll, .wait, .focusWindow, .readClipboard, .expand: return .safe
        case .type(let text, let into):
            if let into, Self.looksSecret(into) { return .destructive }
            // {clipboard} may hold anything, a newline included.
            return text.contains("\n") || text.contains(Self.clipboardToken) ? .risky : .undoable
        case .key(let combo):
            let k = combo.lowercased().replacingOccurrences(of: " ", with: "")
            if Self.destructiveKeys.contains(k) { return .destructive }
            return ["cmd+z", "cmd+c", "cmd+a", "tab", "escape", "esc", "up", "down", "left", "right"].contains(k) ? .safe : .risky
        case .click(let target, _):
            return Self.isDestructive(target.label) ? .destructive : .risky
        case .setValue(let target, _):
            // AXValue skips the app's Undo, so it is never just "undoable".
            return Self.looksSecret(target) ? .destructive : .risky
        case .select(let target, let option):
            return Self.isDestructive(target.label, option) ? .destructive : .risky
        case .toggle(let target, _):
            return Self.isDestructive(target.label) ? .destructive : .risky
        case .writeClipboard:
            // Replaces whatever Tony had copied, with no undo.
            return .destructive
        }
    }

    public static let clipboardToken = "{clipboard}"

    /// A checkbox or switch reports 0 (off), 1 (on) or 2 (mixed). A toggle presses only when the
    /// current state is not the wanted one, so asking for "on" twice is harmless.
    public static func needsPress(current: Int, on: Bool) -> Bool { current != (on ? 1 : 0) }

    /// The step with {clipboard} replaced by what an earlier readClipboard step read.
    public func filling(clipboard: String) -> DriveStep {
        func fill(_ text: String) -> String { text.replacingOccurrences(of: Self.clipboardToken, with: clipboard) }
        switch self {
        case .type(let text, let into): return .type(fill(text), into: into)
        case .setValue(let target, let text): return .setValue(target, fill(text))
        case .writeClipboard(let text): return .writeClipboard(fill(text))
        default: return self
        }
    }

    /// The element the step acts on, when it has one.
    public var target: DriveTarget? {
        switch self {
        case .move(let t), .click(let t, _), .setValue(let t, _), .select(let t, _), .toggle(let t, _), .expand(let t): return t
        case .type(_, let into): return into
        default: return nil
        }
    }

    /// The same step aimed at `target` (no change for steps without one).
    public func with(_ target: DriveTarget) -> DriveStep {
        switch self {
        case .move: return .move(target)
        case .click(_, let double): return .click(target, double: double)
        case .type(let text, .some(_)): return .type(text, into: target)
        case .setValue(_, let text): return .setValue(target, text)
        case .select(_, let option): return .select(target, option: option)
        case .toggle(_, let on): return .toggle(target, on: on)
        case .expand: return .expand(target)
        default: return self
        }
    }

    /// One line for the approval card.
    public var summary: String {
        switch self {
        case .openApp(let name): return "Open \(name)"
        case .move(let t): return "Move to \(Self.describe(t))"
        case .click(let t, let double): return (double ? "Double-click " : "Click ") + Self.describe(t)
        case .type(let text, let into):
            return "Type \u{201C}\(Self.shorten(text))\u{201D}" + (into.map { " into " + Self.describe($0) } ?? "")
        case .key(let combo): return "Press \(combo)"
        case .scroll(let lines): return lines < 0 ? "Scroll down \(-lines)" : "Scroll up \(lines)"
        case .wait(let seconds): return "Wait \(seconds.formatted())s"
        case .setValue(let t, let text): return "Set \(Self.describe(t)) to \u{201C}\(Self.shorten(text))\u{201D}"
        case .select(let t, let option): return "Choose \u{201C}\(option)\u{201D} in \(Self.describe(t))"
        case .toggle(let t, let on): return "Turn \(on ? "on" : "off") \(Self.describe(t))"
        case .expand(let t): return "Expand \(Self.describe(t))"
        case .focusWindow(let app, let title): return "Switch to \(app)" + (title.map { ", window \u{201C}\($0)\u{201D}" } ?? "")
        case .readClipboard: return "Read the clipboard"
        case .writeClipboard(let text): return "Copy \u{201C}\(Self.shorten(text))\u{201D} to the clipboard"
        }
    }

    static func shorten(_ text: String) -> String { text.count > 40 ? String(text.prefix(40)) + "..." : text }

    static func describe(_ t: DriveTarget) -> String {
        if let label = t.label, !label.isEmpty { return "\u{201C}\(label)\u{201D}" }
        if let ref = t.ref { return "element \(ref)" }
        if let x = t.x, let y = t.y { return "(\(x), \(y))" }
        return "the focused field"
    }
}

/// A `[ACTION:{"type":"mac.drive",...}]` plan: what ZEUS will do, shown in the notch first.
public struct DrivePlan: Equatable, Sendable {
    public static let maxSteps = 20

    public var goal: String
    public var steps: [DriveStep]

    public init(goal: String, steps: [DriveStep]) {
        self.goal = goal
        self.steps = steps
    }

    public var risk: DriveStep.Risk { steps.map(\.risk).max() ?? .safe }

    /// True when the plan must wait for a yes under `autonomy`.
    public func needsApproval(_ autonomy: DriveAutonomy) -> Bool {
        switch autonomy {
        case .ask: return true
        case .safe: return risk > .undoable
        case .trusted: return risk == .destructive
        }
    }

    /// The card text: the goal, then numbered steps.
    public var card: String {
        let lines = steps.enumerated().map { "\($0.offset + 1). \($0.element.summary)" }
        return ([goal.isEmpty ? "Drive the Mac" : goal] + lines).joined(separator: "\n")
    }

    /// The plan with each ref's label and secure flag taken from the snapshot that issued it,
    /// so the card and the risk use what is really on screen, not what the plan claims.
    public func labelled(by lookup: (String) -> AXSnapshotElement?) -> DrivePlan {
        DrivePlan(goal: goal, steps: steps.map { step in
            guard var target = step.target, let ref = target.ref, let element = lookup(ref) else { return step }
            if let label = element.label, !label.isEmpty { target.label = label }
            target.secure = element.isSecure
            return step.with(target)
        })
    }

    /// Why the whole plan is refused before anything runs: setting the value of a password field.
    public var refusal: DriveError? {
        for step in steps {
            if case .setValue(let target, _) = step, target.secure { return .secureField(DriveStep.describe(target)) }
        }
        return nil
    }

    public static func parse(_ payload: [String: JSONValue]) -> DrivePlan? {
        guard let raw = payload["steps"]?.arrayValue, !raw.isEmpty, raw.count <= maxSteps else { return nil }
        var steps: [DriveStep] = []
        for item in raw {
            guard let step = parseStep(item) else { return nil }
            steps.append(step)
        }
        return DrivePlan(goal: payload["goal"]?.stringValue ?? "", steps: steps)
    }

    static func target(_ item: JSONValue) -> DriveTarget? {
        var label = item["label"]?.stringValue ?? item["target"]?.stringValue ?? item["title"]?.stringValue
        var ref: String?
        if let value = item["ref"] {
            guard let text = value.stringValue, let parsed = AXRef(text) else { return nil }
            ref = parsed.description
        }
        // A ref given where a label goes ("target":"s3:e7") still counts as a ref.
        if ref == nil, let text = label, let parsed = AXRef(text) { ref = parsed.description; label = nil }
        var x: Int?
        var y: Int?
        if item["x"] != nil || item["y"] != nil {
            guard let rawX = item["x"], let rawY = item["y"],
                  let parsedX = MacActionNumbers.integer(rawX), let parsedY = MacActionNumbers.integer(rawY) else { return nil }
            x = parsedX
            y = parsedY
        }
        var screen: Int?
        if let value = item["screen"] {
            guard let parsed = MacActionNumbers.screen(value) else { return nil }
            screen = parsed
        }
        return DriveTarget(ref: ref, label: label, x: x, y: y, screen: screen)
    }

    /// "on"/"off", true/false, 1/0.
    static func onOff(_ value: JSONValue?) -> Bool? {
        if let bool = value?.boolValue { return bool }
        switch value?.stringValue?.lowercased() {
        case "on", "true", "yes", "1", "checked": return true
        case "off", "false", "no", "0", "unchecked": return false
        default:
            guard let number = value?.numberValue, number.isFinite else { return nil }
            return number != 0
        }
    }

    static func parseStep(_ item: JSONValue) -> DriveStep? {
        guard let raw = (item["do"] ?? item["action"])?.stringValue?.lowercased() else { return nil }
        let action = raw.filter { !"-_. ".contains($0) }
        guard let t = target(item) else { return nil }
        switch action {
        case "open", "openapp", "app":
            guard let name = item["app"]?.stringValue ?? item["name"]?.stringValue, !name.isEmpty else { return nil }
            return .openApp(name)
        case "move", "hover":
            return t.isSpecified ? .move(t) : nil
        case "click", "doubleclick":
            return t.isSpecified ? .click(t, double: action != "click" || item["double"]?.boolValue == true) : nil
        case "type":
            guard let text = item["text"]?.stringValue, !text.isEmpty, text.count <= 2_000 else { return nil }
            return .type(text, into: t.isSpecified ? t : nil)
        case "key", "press", "shortcut":
            guard let keys = item["keys"]?.stringValue ?? item["key"]?.stringValue, !keys.isEmpty else { return nil }
            return .key(keys)
        case "scroll":
            guard let lines = MacActionNumbers.scrollLines(item["dy"] ?? item["lines"] ?? .number(-3)) else { return nil }
            return .scroll(lines)
        case "wait":
            let value = item["seconds"] ?? .number(0.5)
            guard let seconds = value.numberValue, seconds.isFinite else { return nil }
            return .wait(min(max(seconds, 0), 5))
        case "set", "setvalue", "fill":
            // An empty value clears the field.
            guard t.isSpecified, let text = item["value"]?.stringValue ?? item["text"]?.stringValue, text.count <= 2_000 else { return nil }
            return .setValue(t, text)
        case "select", "choose", "pick":
            guard t.isSpecified, let option = item["option"]?.stringValue ?? item["value"]?.stringValue, !option.isEmpty else { return nil }
            return .select(t, option: option)
        case "toggle", "check", "uncheck":
            let on = action == "check" ? true : action == "uncheck" ? false : onOff(item["on"] ?? item["state"] ?? item["value"])
            guard t.isSpecified, let on else { return nil }
            return .toggle(t, on: on)
        case "expand", "disclose", "showmenu":
            return t.isSpecified ? .expand(t) : nil
        case "focus", "focuswindow", "window", "activate":
            guard let app = item["app"]?.stringValue ?? item["name"]?.stringValue, !app.isEmpty else { return nil }
            let title = item["window"]?.stringValue ?? item["title"]?.stringValue
            return .focusWindow(app: app, title: title?.isEmpty == false ? title : nil)
        case "readclipboard", "clipboardread", "getclipboard":
            return .readClipboard
        case "writeclipboard", "clipboardwrite", "setclipboard":
            guard let text = item["text"]?.stringValue ?? item["value"]?.stringValue, !text.isEmpty, text.count <= 2_000 else { return nil }
            return .writeClipboard(text)
        default:
            return nil
        }
    }
}

/// Why a step did not run, said aloud, and whether trying again is safe.
public struct DriveError: Error, Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// The ref came from an older snapshot. Nothing was done.
        case staleRef
        /// The element went away or could not be found. Nothing was done.
        case notFound
        /// A password field: ZEUS never sets one.
        case secureField
        /// The element has no way to do this. Nothing was done.
        case unsupported
        /// The app reported an error mid-action; it may still have happened.
        case mayHaveActed
    }

    public var kind: Kind
    public var message: String
    /// True only when the step certainly had no effect and a fresh snapshot may fix it. A step
    /// that may have acted is never retried on its own.
    public var retrySafe: Bool

    public init(_ kind: Kind, _ message: String, retrySafe: Bool) {
        self.kind = kind
        self.message = message
        self.retrySafe = retrySafe
    }

    public static func staleRef(_ ref: String) -> DriveError {
        DriveError(.staleRef, "That screen changed before I got to \(ref).", retrySafe: true)
    }

    public static func notFound(_ what: String) -> DriveError {
        DriveError(.notFound, "I couldn't find \(what).", retrySafe: true)
    }

    public static func secureField(_ what: String) -> DriveError {
        DriveError(.secureField, "\(what) is a password field, so I'll leave that one to you.", retrySafe: false)
    }

    public static func unsupported(_ what: String) -> DriveError {
        DriveError(.unsupported, what, retrySafe: false)
    }

    /// Classifies an AXError raw value from an action or attribute write on `what`.
    /// -25202 invalid element: it went away first, nothing happened. -25205/-25206/-25201/-25208:
    /// unsupported, nothing happened. Anything else (-25204 cannot complete, -25200 failure) can
    /// come back after the app already acted, so it is not safe to repeat.
    public static func ax(_ code: Int32, doing verb: String, on what: String) -> DriveError {
        switch code {
        case -25202: return DriveError(.notFound, "\(what) went away before I could \(verb) it.", retrySafe: true)
        case -25201, -25205, -25206, -25208: return .unsupported("I can't \(verb) \(what) directly.")
        default: return DriveError(.mayHaveActed, "Something went wrong while I tried to \(verb) \(what), so I stopped. Check it before I try again.", retrySafe: false)
        }
    }
}

/// "cmd+shift+s" -> modifier names and the key name, lowercased.
public enum KeyCombo {
    public static func split(_ combo: String) -> (modifiers: Set<String>, key: String)? {
        let parts = combo.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, !key.isEmpty else { return nil }
        let aliases = ["command": "cmd", "⌘": "cmd", "control": "ctrl", "alt": "option", "opt": "option"]
        let mods = Set(parts.dropLast().map { aliases[$0] ?? $0 })
        guard mods.isSubset(of: ["cmd", "shift", "option", "ctrl", "fn"]) else { return nil }
        return (mods, key)
    }
}
