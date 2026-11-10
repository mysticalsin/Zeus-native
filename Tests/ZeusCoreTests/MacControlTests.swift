import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Show-me annotation")
struct AnnotationTests {
    static func circle(center: CGPoint, radius: CGFloat, count: Int = 40) -> [CGPoint] {
        (0...count).map { i in
            let a = Double(i) / Double(count) * 2 * .pi
            return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        }
    }

    @Test func circleMarksItsInside() {
        let stroke = AnnotationStroke(points: Self.circle(center: CGPoint(x: 500, y: 400), radius: 50))
        #expect(stroke.shape == .circle)
        let region = stroke.region(in: CGRect(x: 0, y: 0, width: 1512, height: 982))
        #expect(abs(region.midX - 500) < 1 && abs(region.midY - 400) < 1)
        #expect(region.width >= 100 && region.width <= 130)
    }

    @Test func lineTapAndClamp() {
        let line = AnnotationStroke(points: (0...20).map { CGPoint(x: 100 + Double($0) * 10, y: 300) })
        #expect(line.shape == .line)
        #expect(line.region(in: CGRect(x: 0, y: 0, width: 1000, height: 1000)).height >= 48)
        let tap = AnnotationStroke(points: [CGPoint(x: 5, y: 5), CGPoint(x: 6, y: 5)])
        #expect(tap.shape == .spot)
        let clamped = tap.region(in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        #expect(clamped.minX == 0 && clamped.minY == 0)
    }

    @Test func pixelsAreTopLeft() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let px = AnnotationStroke.pixelRect(CGRect(x: 100, y: 400, width: 100, height: 50), displayFrame: frame,
                                            pixelWidth: 2000, pixelHeight: 1000)
        #expect(px == CGRect(x: 200, y: 100, width: 200, height: 100))
        let prompt = AnnotationStroke(points: Self.circle(center: CGPoint(x: 10, y: 10), radius: 20))
            .prompt(question: "what is this?", pixels: px, screen: 1)
        #expect(prompt.contains("circled") && prompt.contains("x=200 y=100 w=200 h=100") && prompt.contains("what is this?"))
    }
}

@Suite("Drive mode")
struct DrivePlanTests {
    static func plan(_ json: String) -> DrivePlan? {
        guard case .action(let action)? = ZeusTagParser.parseAction(json) else { return nil }
        #expect(action.kind == .macDrive)
        return DrivePlan.parse(action.payload)
    }

    @Test func safePlanAutoRunsByDefault() throws {
        let plan = try #require(Self.plan(#"{"type":"mac.drive","goal":"Start a note","steps":[{"do":"open","app":"Notes"},{"do":"type","text":"Groceries"},{"do":"scroll","dy":-2}]}"#))
        #expect(plan.steps.count == 3)
        #expect(plan.risk == .undoable)
        #expect(!plan.needsApproval(.default))
        #expect(plan.needsApproval(.ask))
        #expect(plan.card.hasPrefix("Start a note\n1. Open Notes\n2. Type"))
    }

    @Test func clicksAskAndSendIsDestructive() throws {
        let click = try #require(Self.plan(#"{"type":"mac.drive","steps":[{"do":"click","label":"New Folder","x":10,"y":20}]}"#))
        #expect(click.risk == .risky && click.needsApproval(.safe) && !click.needsApproval(.trusted))
        let send = try #require(Self.plan(#"{"type":"mac.drive","steps":[{"do":"click","label":"Send"}]}"#))
        #expect(send.risk == .destructive && send.needsApproval(.trusted))
        let quit = try #require(Self.plan(#"{"type":"mac.drive","steps":[{"do":"key","keys":"Cmd+Q"}]}"#))
        #expect(quit.risk == .destructive)
    }

    @Test func rejectsBadPlans() {
        #expect(Self.plan(#"{"type":"mac.drive","steps":[]}"#) == nil)
        #expect(Self.plan(#"{"type":"mac.drive","steps":[{"do":"teleport"}]}"#) == nil)
        #expect(Self.plan(#"{"type":"mac.drive","steps":[{"do":"click"}]}"#) == nil)
        let many = (0..<21).map { _ in #"{"do":"wait"}"# }.joined(separator: ",")
        #expect(Self.plan(#"{"type":"mac.drive","steps":["# + many + "]}") == nil)
    }

    @Test func parsesNewStepKinds() throws {
        let plan = try #require(Self.plan(#"{"type":"mac.drive","goal":"Tidy settings","steps":[{"do":"focus","app":"Mail","title":"Inbox"},{"do":"set","ref":"s3:e4","value":"Groceries"},{"do":"select","label":"Size","option":"Large"},{"do":"toggle","target":"s3:e9","on":false},{"do":"check","label":"Bold"},{"do":"expand","ref":"@s3:e2"},{"do":"read_clipboard"},{"do":"writeClipboard","text":"hello"}]}"#))
        #expect(plan.steps == [
            .focusWindow(app: "Mail", title: "Inbox"),
            .setValue(DriveTarget(ref: "s3:e4"), "Groceries"),
            .select(DriveTarget(label: "Size"), option: "Large"),
            .toggle(DriveTarget(ref: "s3:e9"), on: false),
            .toggle(DriveTarget(label: "Bold"), on: true),
            .expand(DriveTarget(ref: "s3:e2")),
            .readClipboard,
            .writeClipboard("hello"),
        ])
        #expect(plan.card.contains("1. Switch to Mail, window \u{201C}Inbox\u{201D}"))
        #expect(plan.card.contains("2. Set element s3:e4 to \u{201C}Groceries\u{201D}"))
        // Old steps take a ref too, and setting a field empty clears it.
        let click = try #require(Self.plan(#"{"type":"mac.drive","steps":[{"do":"click","ref":"s2:e5"},{"do":"set","label":"Search","value":""}]}"#))
        #expect(click.steps == [.click(DriveTarget(ref: "s2:e5"), double: false), .setValue(DriveTarget(label: "Search"), "")])
    }

    @Test func rejectsIncompleteNewSteps() {
        for step in [#"{"do":"set","value":"x"}"#, #"{"do":"select","label":"Size"}"#, #"{"do":"toggle","label":"Bold"}"#,
                     #"{"do":"expand"}"#, #"{"do":"focus"}"#, #"{"do":"writeclipboard","text":""}"#,
                     #"{"do":"set","ref":"nonsense","value":"x"}"#] {
            #expect(Self.plan(#"{"type":"mac.drive","steps":["# + step + "]}") == nil, "\(step)")
        }
    }

    @Test func newStepRisks() {
        let field = DriveTarget(ref: "s1:e1", label: "Name")
        #expect(DriveStep.readClipboard.risk == .safe)
        #expect(DriveStep.focusWindow(app: "Mail", title: nil).risk == .safe)
        #expect(DriveStep.expand(field).risk == .safe)
        #expect(DriveStep.setValue(field, "Tony").risk == .risky)
        #expect(DriveStep.setValue(DriveTarget(label: "Password"), "x").risk == .destructive)
        #expect(DriveStep.setValue(DriveTarget(label: "Shipping address"), "x").risk == .risky)
        #expect(DriveStep.setValue(DriveTarget(ref: "s1:e2", secure: true), "x").risk == .destructive)
        #expect(DriveStep.select(DriveTarget(label: "Size"), option: "Large").risk == .risky)
        #expect(DriveStep.select(DriveTarget(label: "Action"), option: "Delete all").risk == .destructive)
        #expect(DriveStep.toggle(DriveTarget(label: "Bold"), on: true).risk == .risky)
        #expect(DriveStep.toggle(DriveTarget(label: "Remove after import"), on: true).risk == .destructive)
        #expect(DriveStep.writeClipboard("hi").risk == .destructive)
        // Reads and focus alone run under the default autonomy; a field write waits for a yes.
        #expect(!DrivePlan(goal: "", steps: [.focusWindow(app: "Notes", title: nil), .readClipboard]).needsApproval(.default))
        #expect(DrivePlan(goal: "", steps: [.setValue(field, "x")]).needsApproval(.default))
        // {clipboard} may hold a newline, so typing it is not just undoable.
        #expect(DriveStep.type("{clipboard}", into: nil).risk == .risky)
        #expect(DriveStep.type("pasted: {clipboard}", into: nil).filling(clipboard: "abc") == .type("pasted: abc", into: nil))
    }

    @Test func approvalByRiskAtEachAutonomy() {
        // One step of each risk: scroll (safe), type (undoable), click (risky), Send (destructive).
        let steps: [(DriveStep, DriveStep.Risk)] = [
            (.scroll(-2), .safe), (.type("hi", into: nil), .undoable),
            (.click(DriveTarget(label: "New Folder"), double: false), .risky),
            (.click(DriveTarget(label: "Send"), double: false), .destructive),
        ]
        let expected: [DriveAutonomy: [Bool]] = [
            .ask: [true, true, true, true],
            .safe: [false, false, true, true],
            .trusted: [false, false, false, true],
        ]
        for autonomy in DriveAutonomy.allCases {
            let asks = steps.map { step, risk in
                #expect(step.risk == risk)
                return DrivePlan(goal: "", steps: [step]).needsApproval(autonomy)
            }
            #expect(asks == expected[autonomy], "\(autonomy)")
        }
        // High risk always asks, even when trusted: the clipboard, secure fields, typed passwords.
        let secure = DriveTarget(ref: "s1:e1", secure: true)
        for step: DriveStep in [.writeClipboard("x"), .setValue(secure, "x"), .type("x", into: secure),
                                .type("x", into: DriveTarget(label: "Password")), .key("cmd+q")] {
            #expect(DrivePlan(goal: "", steps: [.scroll(1), step]).needsApproval(.trusted), "\(step)")
        }
        #expect(!DrivePlan(goal: "", steps: [.setValue(DriveTarget(label: "Name"), "x"), .toggle(DriveTarget(label: "Bold"), on: true)]).needsApproval(.trusted))
        #expect(DriveAutonomy.allCases.map(\.title) == ["Always ask", "Safe steps alone", "Trusted"])
        #expect(DriveAutonomy.allCases.allSatisfy { $0.explanation.contains("Esc stops Zeus") })
    }

    @Test func toggleIsANoOpWhenAlreadySet() {
        #expect(!DriveStep.needsPress(current: 1, on: true))
        #expect(!DriveStep.needsPress(current: 0, on: false))
        #expect(DriveStep.needsPress(current: 0, on: true))
        #expect(DriveStep.needsPress(current: 2, on: true) && DriveStep.needsPress(current: 2, on: false))
    }

    @Test func refsTakeTheirLabelFromTheSnapshot() throws {
        let snapshot = AXSnapshot(id: 7, app: "Mail", elements: [
            AXSnapshotElement(role: "AXButton", label: "Send", actions: ["AXPress"]),
            AXSnapshotElement(role: "AXTextField", label: "Subject"),
        ])
        // The plan claims e1 is "Cancel"; the snapshot says it is "Send", so it is destructive.
        let plan = try #require(Self.plan(#"{"type":"mac.drive","steps":[{"do":"click","ref":"s7:e1","label":"Cancel"},{"do":"set","ref":"s7:e2","value":"Hi"}]}"#))
        let labelled = plan.labelled { try? snapshot.element($0) }
        #expect(labelled.steps[0] == .click(DriveTarget(ref: "s7:e1", label: "Send"), double: false))
        #expect(labelled.risk == .destructive)
        #expect(labelled.card.contains("Set \u{201C}Subject\u{201D} to"))
        #expect(labelled.refusal == nil)
    }

    @Test func refusesSecureFieldSetValue() throws {
        let snapshot = AXSnapshot(id: 3, app: "Safari", elements: [
            AXSnapshotElement(role: "AXTextField", label: "Email", value: "tony@example.com"),
            AXSnapshotElement(role: "AXTextField", subrole: "AXSecureTextField", label: "Password", value: "hunter2"),
            AXSnapshotElement(role: "AXSecureTextField", label: "PIN"),
        ])
        for ref in ["s3:e2", "s3:e3"] {
            let plan = try #require(Self.plan(#"{"type":"mac.drive","steps":[{"do":"set","ref":""# + ref + #"","value":"x"}]}"#))
                .labelled { try? snapshot.element($0) }
            let refusal = try #require(plan.refusal)
            #expect(refusal.kind == .secureField && !refusal.retrySafe)
            #expect(plan.risk == .destructive)
        }
        let email = try #require(Self.plan(#"{"type":"mac.drive","steps":[{"do":"set","ref":"s3:e1","value":"x"}]}"#))
        #expect(email.labelled { try? snapshot.element($0) }.refusal == nil)
        // A secure field's value never reaches the brain, even if a model carried one.
        #expect(!snapshot.render().contains("hunter2"))
    }

    @Test func driveErrorsSayWhetherARetryIsSafe() {
        #expect(DriveError.staleRef("s1:e2").retrySafe)
        #expect(DriveError.notFound("\u{201C}Save\u{201D}").retrySafe)
        #expect(DriveError.ax(-25202, doing: "press", on: "Save").retrySafe) // element went away first
        #expect(DriveError.ax(-25206, doing: "press", on: "Save").kind == .unsupported)
        let maybe = DriveError.ax(-25204, doing: "press", on: "Save") // cannot complete: it may have pressed
        #expect(maybe.kind == .mayHaveActed && !maybe.retrySafe)
        #expect(!DriveError.ax(-25200, doing: "fill", on: "Name").retrySafe)
        #expect(!DriveError.secureField("Password").retrySafe)
    }

    @Test func keyCombos() {
        let combo = KeyCombo.split("Command+Shift+S")
        #expect(combo?.modifiers == ["cmd", "shift"] && combo?.key == "s")
        #expect(KeyCombo.split("hyper+x") == nil)
    }
}

@Suite("Walkthroughs")
struct WalkthroughTests {
    @Test func runsBackAndFinishes() throws {
        guard case .action(let action)? = ZeusTagParser.parseAction(
            #"{"type":"mac.walkthrough","title":"Share a file","steps":[{"say":"Click Share","x":100,"y":40,"label":"Share"},{"say":"Pick Mail"},{"say":"Press Send"}]}"#
        ) else { Issue.record("no action"); return }
        var session = WalkthroughSession(try #require(Walkthrough.parse(action.payload)))
        #expect(session.progress == "Step 1 of 3" && session.current?.target?.x == 100)
        session.next(); session.back(); #expect(session.progress == "Step 1 of 3")
        session.next(); session.next(); #expect(session.current?.say == "Press Send")
        session.next(); #expect(session.state == .finished && session.current == nil)
        #expect(WalkthroughSession.command(for: "Next.") == "next")
        #expect(WalkthroughSession.command(for: "stop the tour") == "cancel")
    }
}

@Suite("Named agents")
struct NamedAgentTests {
    @Test func routesByName() throws {
        let agents = AgentProfile.builtIn
        let ask = try #require(AgentRouter.route("Ask Scout to find the Swift 6 release date", agents: agents))
        #expect(ask.agent.name == "Scout" && ask.request == "find the Swift 6 release date" && ask.remember == nil)
        let note = try #require(AgentRouter.route("Scribe, remember that I sign emails as Tony", agents: agents))
        #expect(note.remember == "I sign emails as Tony")
        #expect(AgentRouter.route("what's the weather", agents: agents) == nil)
    }

    @Test func memoryPersistsPerAgent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-agents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentStore(root: root)
        let scout = AgentProfile.builtIn[0], scribe = AgentProfile.builtIn[1]
        var memory = store.memory(for: scout)
        memory.remember("Tony prefers primary sources", pinned: true)
        for i in 0..<(AgentMemory.maxNotes + 5) { memory.remember("note \(i)") }
        try store.save(memory, for: scout)
        let back = store.memory(for: scout)
        #expect(back.notes.count == AgentMemory.maxNotes)
        #expect(back.notes.first?.pinned == true)
        #expect(store.memory(for: scribe).notes.isEmpty)
        let preamble = AgentRouter.preamble(scout, memory: back)
        #expect(preamble.contains("You are Scout") && preamble.contains("Tony prefers primary sources"))
        #expect(preamble.contains("note 204") && !preamble.contains("note 100"))
    }

    @Test func customAgentsOverride() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-agents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try #"[{"name":"Atlas","role":"travel","instructions":"Plan trips."}]"#.write(
            to: root.appendingPathComponent("agents.json"), atomically: true, encoding: .utf8)
        let names = AgentStore(root: root).profiles().map(\.name)
        #expect(names == ["Atlas", "Pilot", "Scout", "Scribe"])
    }
}

@Suite("Drive snapshots")
struct AXSnapshotTests {
    static func element(_ role: String, _ label: String?, enabled: Bool = true, value: String? = nil,
                        x: Double = 0, subrole: String? = nil, actions: [String] = []) -> AXSnapshotElement {
        AXSnapshotElement(role: role, subrole: subrole, label: label, value: value, enabled: enabled,
                          frame: CGRect(x: x, y: 10, width: 40, height: 20), actions: actions)
    }

    @Test func refsAreScopedToTheirSnapshot() throws {
        let elements = [Self.element("AXButton", "New Note"), Self.element("AXTextField", "Search")]
        let first = AXSnapshot(id: 4, app: "Notes", elements: elements)
        #expect(first.elements.map(\.ref.description) == ["s4:e1", "s4:e2"])
        #expect(try first.element("s4:e2").label == "Search")
        #expect(try first.element("@s4:e1").label == "New Note")
        let second = AXSnapshot(id: 5, app: "Notes", elements: elements)
        #expect(throws: AXSnapshotError.staleRef(ref: "s4:e2", current: 5)) { try second.element("s4:e2") }
        #expect(throws: AXSnapshotError.unknownRef("s5:e9")) { try second.element("s5:e9") }
        #expect(throws: AXSnapshotError.malformedRef("button 2")) { try second.element("button 2") }
        #expect(AXRef("s0:e1") == nil && AXRef("e1:s2") == nil && AXRef("[s12:e40]") == AXRef(snapshot: 12, index: 40))
    }

    @Test func staleRefsAreFoundAgainByRoleAndLabel() throws {
        let old = AXSnapshot(id: 1, app: "Finder", elements: [Self.element("AXButton", "Share", x: 100)])
        let new = AXSnapshot(id: 2, app: "Finder", elements: [
            Self.element("AXStaticText", "Share"), Self.element("AXButton", "Share", x: 600),
            Self.element("AXButton", "Share", x: 120), Self.element("AXButton", "Tags"),
        ])
        let found = try #require(new.relocate(try old.element("s1:e1")))
        #expect(found.ref.description == "s2:e3") // same role and label, nearest the old spot
        #expect(new.relocate(Self.element("AXButton", nil)) == nil)
    }

    @Test func renderingPutsControlsFirstAndCaps() {
        var elements = [Self.element("AXStaticText", "Welcome back"), Self.element("AXGroup", nil),
                        Self.element("AXButton", "Disabled one", enabled: false)]
        elements += (1...50).map { Self.element("AXButton", "Button \($0)") }
        elements += [Self.element("AXCheckBox", "Bold", value: "1"), Self.element("AXTextField", "Title", value: "Groceries"),
                     Self.element("AXGroup", "Toolbar", actions: ["AXShowMenu"])]
        let snapshot = AXSnapshot(id: 9, app: "Notes", window: "Groceries", elements: elements, truncated: true)
        let ranked = snapshot.ranked
        #expect(ranked.count == 55) // the unlabelled group is left out
        #expect(ranked.first?.label == "Button 1")
        #expect(ranked.suffix(2).map(\.label) == ["Welcome back", "Disabled one"])

        let text = snapshot.render(limit: 10)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 12) // header, ten elements, the "more" line
        #expect(lines[0].hasPrefix("Controls in Notes, window \"Groceries\" (snapshot s9"))
        #expect(lines[1] == "- button \"Button 1\" [s9:e4]")
        #expect(lines.last == "- ... 45 more not listed; the walk stopped early")
        #expect(!text.contains("Welcome back"))

        let all = snapshot.render(limit: 100)
        #expect(all.contains("- checkbox \"Bold\" on [s9:e54]"))
        #expect(all.contains("- textfield \"Title\" = \"Groceries\" [s9:e55]"))
        #expect(all.contains("- group \"Toolbar\" [s9:e56]"))
        #expect(all.contains("- button \"Disabled one\" disabled [s9:e3]"))
        #expect(all.contains("- ... 0 more not listed; the walk stopped early"))
        #expect(!AXSnapshot(id: 1, app: "Notes", elements: [Self.element("AXButton", "OK")]).render().contains("more not listed"))
    }

    @Test func secureFieldsShowNoValue() {
        let snapshot = AXSnapshot(id: 2, app: "Safari", elements: [
            Self.element("AXTextField", "Password", value: "hunter2", subrole: "AXSecureTextField"),
        ])
        #expect(snapshot.elements[0].isSecure)
        #expect(snapshot.render().contains("- securefield \"Password\" [s2:e1]"))
        #expect(!snapshot.render().contains("hunter2"))
    }
}
