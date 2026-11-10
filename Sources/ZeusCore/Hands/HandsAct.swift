import Foundation

/// Where the companion flies while an action runs. It never moves the real pointer.
public struct HandsCue: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var label: String

    public init(x: Int, y: Int, label: String) {
        self.x = x
        self.y = y
        self.label = label
    }
}

public struct HandsPoint: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

public struct HandsFrame: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int
    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
    public var center: HandsPoint { HandsPoint(x: x + w / 2, y: y + h / 2) }
}

/// How an action is delivered. Both leave the frontmost app and the pointer where they were.
/// SkyLight and the HID event tap are not cases here.
public enum HandsDelivery: String, Equatable, Sendable {
    case accessibility
    case postToPid
}

public struct HandsElement: Equatable, Sendable, Identifiable {
    public var id: String
    public var role: String
    public var label: String
    public var value: String
    public var secret: Bool
    public var pressed: Bool
    public var frame: HandsFrame
    public var menu: [String]
    public var pid: Int32

    public init(id: String, role: String, label: String, value: String = "", secret: Bool = false,
                pressed: Bool = false, frame: HandsFrame = HandsFrame(x: 0, y: 0, w: 40, h: 20),
                menu: [String] = [], pid: Int32 = 0) {
        self.id = id
        self.role = role
        self.label = label
        self.value = value
        self.secret = secret
        self.pressed = pressed
        self.frame = frame
        self.menu = menu
        self.pid = pid
    }

    /// What a receipt may say. Secret fields never include their value.
    public var state: String {
        if secret { return "\(label) secret" }
        if role == "button" { return "\(label) \(pressed ? "pressed" : "idle")" }
        if !value.isEmpty { return "\(label) \(value)" }
        return "\(label) empty"
    }
}

/// The notch expanding over the covered window. Streaming stops when the task ends.
public struct WorkBehindPreview: Equatable, Sendable {
    public var streaming: Bool
    public var title: String
    public var frames: [HandsFrame]
    public var windowID: String

    public init(streaming: Bool = false, title: String = "", frames: [HandsFrame] = [], windowID: String = "") {
        self.streaming = streaming
        self.title = title
        self.frames = frames
        self.windowID = windowID
    }

    public func stopped() -> WorkBehindPreview {
        WorkBehindPreview(streaming: false, title: "", frames: [], windowID: "")
    }
}

public enum HandsVerb: Equatable, Sendable {
    case click(String, kind: String)
    case menu([String])
    case type(String, into: String)
    case scroll(Int)
    case drag(String, to: String)
    case wait(Double)
}

public struct HandsReceipt: Equatable, Sendable {
    public var verb: String
    public var ok: Bool
    public var changed: String
    public var before: String
    public var after: String
    public var delivery: HandsDelivery
    public var cue: HandsCue?
    public var failure: String?

    public var line: String {
        let cueText = cue.map { " cue=\($0.x),\($0.y)" } ?? ""
        let status = ok ? "ok" : "failed"
        return "receipt \(verb) \(status) changed=\(changed) before=\(before) after=\(after) delivery=\(delivery.rawValue)\(cueText)"
    }
}

/// An accessibility map Zeus can act on. Actions do not raise a window or move the pointer.
public struct HandsWorld: Equatable, Sendable {
    public var frontPid: Int32
    public var cursor: HandsPoint
    public var elements: [HandsElement]
    public var chosenMenu: String?
    public var scroll: Int
    public var owned: [String: String]
    public var preview: WorkBehindPreview
    public var deliveries: [HandsDelivery]

    public init(frontPid: Int32, cursor: HandsPoint, elements: [HandsElement], chosenMenu: String? = nil,
                scroll: Int = 0, owned: [String: String] = [:], preview: WorkBehindPreview = WorkBehindPreview(),
                deliveries: [HandsDelivery] = []) {
        self.frontPid = frontPid
        self.cursor = cursor
        self.elements = elements
        self.chosenMenu = chosenMenu
        self.scroll = scroll
        self.owned = owned
        self.preview = preview
        self.deliveries = deliveries
    }

    public static func fixture() -> HandsWorld {
        HandsWorld(
            frontPid: 100,
            cursor: HandsPoint(x: 12, y: 34),
            elements: [
                HandsElement(id: "save", role: "button", label: "Save", frame: HandsFrame(x: 10, y: 10, w: 60, h: 24), pid: 100),
                HandsElement(id: "file", role: "menuitem", label: "File", frame: HandsFrame(x: 0, y: 0, w: 40, h: 18), menu: ["Export", "Save"], pid: 100),
                HandsElement(id: "search", role: "field", label: "Search", frame: HandsFrame(x: 80, y: 40, w: 120, h: 22), pid: 100),
                HandsElement(id: "password", role: "field", label: "Password", value: "hunter2", secret: true, frame: HandsFrame(x: 80, y: 70, w: 120, h: 22), pid: 100),
                HandsElement(id: "note", role: "field", label: "Note", frame: HandsFrame(x: 20, y: 80, w: 200, h: 80), pid: 200),
                HandsElement(id: "handle", role: "button", label: "Handle", frame: HandsFrame(x: 0, y: 0, w: 20, h: 20), pid: 100),
                HandsElement(id: "drop", role: "button", label: "Drop", frame: HandsFrame(x: 100, y: 40, w: 20, h: 20), pid: 100),
                HandsElement(id: "send", role: "button", label: "Send", frame: HandsFrame(x: 200, y: 80, w: 50, h: 24), pid: 100),
                HandsElement(id: "title", role: "field", label: "Title", value: "theirs", frame: HandsFrame(x: 80, y: 100, w: 120, h: 22), pid: 100),
            ]
        )
    }

    public func element(_ label: String) -> HandsElement? {
        let key = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return elements.first { $0.label.lowercased() == key }
    }

    @discardableResult
    public mutating func perform(_ verb: HandsVerb) -> HandsReceipt {
        let front = frontPid
        let pointer = cursor
        let receipt: HandsReceipt
        switch verb {
        case .click(let label, let kind): receipt = click(label, kind: kind)
        case .menu(let path): receipt = menu(path)
        case .type(let text, let into): receipt = type(text, into: into, behind: false)
        case .scroll(let lines): receipt = scrollBy(lines)
        case .drag(let from, let to): receipt = drag(from, to: to)
        case .wait(let seconds): receipt = wait(seconds)
        }
        frontPid = front
        cursor = pointer
        return receipt
    }

    /// Types into a covered window. The frontmost app and the pointer stay put, and the notch
    /// shows that window's frames until `endBehind`.
    @discardableResult
    public mutating func typeBehind(_ text: String, into label: String) -> HandsReceipt {
        let front = frontPid
        let pointer = cursor
        let receipt = type(text, into: label, behind: true)
        frontPid = front
        cursor = pointer
        if receipt.ok, let element = element(label) {
            preview = WorkBehindPreview(streaming: true, title: label, frames: [element.frame], windowID: element.id)
        }
        return receipt
    }

    public mutating func endBehind() {
        preview = preview.stopped()
    }

    /// Opens the covered window. This is the one path that changes the front app, and only
    /// because the person clicked the mini screen.
    public mutating func openPreview() -> Bool {
        guard preview.streaming, let element = elements.first(where: { $0.id == preview.windowID }) else { return false }
        frontPid = element.pid
        endBehind()
        return true
    }

    private mutating func click(_ label: String, kind: String) -> HandsReceipt {
        guard var element = element(label) else {
            return fail("click \(label)", "couldn't find \(label)")
        }
        let before = element.state
        element.pressed = true
        replace(element)
        deliveries.append(.accessibility)
        let verb = kind == "click" ? "click \(label)" : "\(kind) \(label)"
        return HandsReceipt(verb: verb, ok: true, changed: element.state, before: before, after: element.state,
                            delivery: .accessibility, cue: cue(element, label), failure: nil)
    }

    private mutating func menu(_ path: [String]) -> HandsReceipt {
        guard path.count >= 2, let bar = element(path[0]) else {
            return fail("menu \(path.joined(separator: " > "))", "couldn't find \(path.first ?? "menu")")
        }
        let item = path[1]
        guard bar.menu.contains(where: { $0.lowercased() == item.lowercased() }) else {
            return fail("menu \(path.joined(separator: " > "))", "couldn't find \(item)")
        }
        let before = chosenMenu ?? "closed"
        chosenMenu = path.joined(separator: " > ")
        deliveries.append(.accessibility)
        return HandsReceipt(verb: "menu \(chosenMenu ?? "")", ok: true, changed: chosenMenu ?? "", before: before, after: chosenMenu ?? "",
                            delivery: .accessibility, cue: cue(bar, path[0]), failure: nil)
    }

    private mutating func type(_ text: String, into label: String, behind: Bool) -> HandsReceipt {
        guard var element = element(label) else {
            return fail("type \(text) in \(label)", "couldn't find \(label)")
        }
        let before = element.state
        if element.secret {
            deliveries.append(behind ? .postToPid : .accessibility)
            return HandsReceipt(verb: "type in \(label)", ok: false, changed: "secret left unread", before: before, after: before,
                                delivery: behind ? .postToPid : .accessibility, cue: cue(element, label), failure: "password field left alone")
        }
        if !element.value.isEmpty, owned[element.id] != element.value {
            return fail("type \(text) in \(label)", "not ours to replace")
        }
        element.value = text
        replace(element)
        owned[element.id] = text
        let delivery: HandsDelivery = behind ? .postToPid : .accessibility
        deliveries.append(delivery)
        return HandsReceipt(verb: "type \(text) in \(label)", ok: true, changed: "\(label) is \(text)", before: before, after: element.state,
                            delivery: delivery, cue: cue(element, label), failure: nil)
    }

    private mutating func scrollBy(_ lines: Int) -> HandsReceipt {
        let before = "scroll \(scroll)"
        scroll += lines
        deliveries.append(.postToPid)
        return HandsReceipt(verb: "scroll \(lines)", ok: true, changed: "scrolled \(scroll)", before: before, after: "scroll \(scroll)",
                            delivery: .postToPid, cue: nil, failure: nil)
    }

    private mutating func drag(_ from: String, to: String) -> HandsReceipt {
        guard var source = element(from), let target = element(to) else {
            return fail("drag \(from) to \(to)", "couldn't find \(element(from) == nil ? from : to)")
        }
        let before = "\(from) at \(source.frame.x),\(source.frame.y)"
        source.frame = HandsFrame(x: target.frame.x, y: target.frame.y, w: source.frame.w, h: source.frame.h)
        replace(source)
        deliveries.append(.postToPid)
        let after = "\(from) at \(source.frame.x),\(source.frame.y)"
        return HandsReceipt(verb: "drag \(from) to \(to)", ok: true, changed: after, before: before, after: after,
                            delivery: .postToPid, cue: cue(source, from), failure: nil)
    }

    private func wait(_ seconds: Double) -> HandsReceipt {
        HandsReceipt(verb: "wait \(seconds)", ok: true, changed: "waited \(seconds)s", before: "idle", after: "idle",
                     delivery: .accessibility, cue: nil, failure: nil)
    }

    private func fail(_ verb: String, _ reason: String) -> HandsReceipt {
        HandsReceipt(verb: verb, ok: false, changed: "failed", before: "unchanged", after: "unchanged",
                     delivery: .accessibility, cue: nil, failure: reason)
    }

    private func cue(_ element: HandsElement, _ label: String) -> HandsCue {
        HandsCue(x: element.frame.center.x, y: element.frame.center.y, label: label)
    }

    private mutating func replace(_ element: HandsElement) {
        guard let index = elements.firstIndex(where: { $0.id == element.id }) else { return }
        elements[index] = element
    }
}

/// The scripted checks for click, menu, type, scroll, drag, wait, work-behind and the gate.
public enum HandsAcceptance {
    public static func report(at date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> HandsReport {
        var world = HandsWorld.fixture()
        var session = HandsGateSession(taskID: "acceptance")
        var log = HandsCommandLog()
        var lines: [String] = []
        var problems: [String] = []

        func check(_ name: String, _ ok: Bool) {
            if !ok { problems.append(name) }
        }
        func has(_ fragment: String) -> Bool {
            lines.contains { $0.contains(fragment) }
        }

        let front = world.frontPid
        let pointer = world.cursor
        let save = world.perform(.click("Save", kind: "click"))
        lines.append(save.line)
        check("click Save", save.ok && save.changed == "Save pressed" && save.after == "Save pressed" && save.cue != nil)

        let menu = world.perform(.menu(["File", "Export"]))
        lines.append(menu.line)
        check("menu", menu.ok && menu.changed == "File > Export")

        let typed = world.perform(.type("hello", into: "Search"))
        lines.append(typed.line)
        check("type", typed.ok && world.element("Search")?.value == "hello" && typed.changed.contains("hello"))

        let secret = world.perform(.type("nope", into: "Password"))
        lines.append(secret.line)
        check("secret", !secret.ok && !secret.line.contains("hunter2") && world.element("Password")?.value == "hunter2")

        let missing = world.perform(.click("Missing", kind: "click"))
        lines.append(missing.line)
        check("missing", !missing.ok && missing.changed == "failed")

        let scrolled = world.perform(.scroll(-3))
        lines.append(scrolled.line)
        check("scroll", scrolled.ok && world.scroll == -3 && scrolled.delivery == .postToPid)

        let dragged = world.perform(.drag("Handle", to: "Drop"))
        lines.append(dragged.line)
        check("drag", dragged.ok && world.element("Handle")?.frame.x == 100 && world.element("Handle")?.frame.y == 40)

        let waited = world.perform(.wait(0.2))
        lines.append(waited.line)
        check("wait", waited.ok && waited.changed == "waited 0.2s")

        check("focus", world.frontPid == front && world.cursor == pointer)
        check("delivery", world.deliveries.allSatisfy { $0 == .accessibility || $0 == .postToPid })

        let behind = world.typeBehind("covered", into: "Note")
        lines.append(behind.line)
        lines.append("behind front=\(world.frontPid) cursor=\(world.cursor.x),\(world.cursor.y) streaming=\(world.preview.streaming) frames=\(world.preview.frames.count)")
        check("behind", behind.ok && behind.delivery == .postToPid && world.frontPid == front && world.cursor == pointer
              && world.element("Note")?.value == "covered" && world.preview.streaming && world.preview.frames.count == 1)
        world.endBehind()
        lines.append("behind-end streaming=\(world.preview.streaming) frames=\(world.preview.frames.count)")
        check("behind-end", !world.preview.streaming && world.preview.frames.isEmpty)

        func gate(_ intent: HandsIntent, _ effectsAfter: Int) {
            let verdict = session.propose(intent, log: &log, at: date)
            switch verdict {
            case .approve(let preview):
                lines.append("gate \(intent.command) approve effects=\(session.effects)")
                lines.append(preview.card)
                check(intent.command, session.effects == effectsAfter && session.pending != nil)
            case .block(let reason):
                lines.append("gate \(intent.command) blocked \(reason) effects=\(session.effects)")
                check(intent.command, session.effects == effectsAfter && session.pending == nil)
            case .allow:
                lines.append("gate \(intent.command) allow effects=\(session.effects)")
                check(intent.command, false)
            }
        }

        let before = session.effects
        gate(.send(to: "ada@example.com", text: "Thursday works"), before)
        check("send preview", has("To ada@example.com") && has("Thursday works"))
        check("send held", session.decide(allow: false, log: &log, at: date) == false && session.effects == before)
        gate(.send(to: "ada@example.com", text: "Thursday works"), before)
        check("send allow", session.decide(allow: true, log: &log, at: date) && session.effects == before + 1)

        let deleteAt = session.effects
        let files = ["Notes.txt", "Draft.txt"]
        let plan = HandsGate.trash(files)
        gate(.delete(files: files), deleteAt)
        check("trash", plan.command == "trash" && !plan.usesRemove && has("Notes.txt") && has("Draft.txt"))
        check("delete held", session.effects == deleteAt)
        check("delete allow", session.decide(allow: true, log: &log, at: date) && session.effects == deleteAt + 1)

        let buyAt = session.effects
        gate(.buy(item: "USB cable", price: "$12"), buyAt)
        check("buy held", session.effects == buyAt && has("USB cable") && has("$12"))
        check("buy allow", session.decide(allow: true, log: &log, at: date) && session.effects == buyAt + 1)

        let blockedAt = session.effects
        for command in ["rm -rf build", "sudo ls", "dd if=/dev/zero of=disk", "diskutil eraseDisk", "shutdown -h now", "git push origin main"] {
            gate(.shell(command), blockedAt)
            check("still blocked \(command)", session.decide(allow: true, log: &log, at: date) == false && session.effects == blockedAt)
        }
        check("log", ["rm -rf build", "sudo ls", "git push origin main"].allSatisfy { log.contains(command: $0) })

        let owned = world.perform(.type("other", into: "Title"))
        check("owned", !owned.ok && world.element("Title")?.value == "theirs")

        lines.append("log \(log.lines.count)")
        if problems.isEmpty {
            lines.append("PASS")
        } else {
            lines.append("FAIL \(problems.joined(separator: ", "))")
        }
        return HandsReport(text: lines.joined(separator: "\n"), passed: problems.isEmpty, log: log.text)
    }
}

public struct HandsReport: Equatable, Sendable {
    public var text: String
    public var passed: Bool
    public var log: String
}
