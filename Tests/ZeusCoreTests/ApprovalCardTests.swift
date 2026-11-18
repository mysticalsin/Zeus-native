import Foundation
import Testing
@testable import ZeusCore

@Suite("Approval card")
struct ApprovalCardTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func inputIsIgnoredUntilTheQuietIntervalEnds() {
        let appeared = now
        #expect(!ApprovalCard.inputOpen(now: appeared.addingTimeInterval(0.399), appearedAt: appeared))
        #expect(ApprovalCard.inputOpen(now: appeared.addingTimeInterval(0.4), appearedAt: appeared))
    }

    @Test func keysKeepTheExistingAnswersAndAddJumpArrowsAndChat() {
        #expect(ApprovalCard.key(letter: "Y", risk: .low) == .allow)
        #expect(ApprovalCard.key(letter: "N", risk: .medium) == .deny)
        #expect(ApprovalCard.key(letter: "O", risk: .high) == .open)
        #expect(ApprovalCard.key(letter: "J", risk: .low) == .jump)
        #expect(ApprovalCard.key(letter: "A", risk: .low) == .allowChat)
        #expect(ApprovalCard.key(letter: "A", risk: .high) == nil)
        #expect(ApprovalCard.arrow(-1) == .previous)
        #expect(ApprovalCard.arrow(1) == .next)
        #expect(ApprovalCard.keycap(.allow, risk: .high, modifiersHeld: false) == nil)
        #expect(ApprovalCard.keycap(.allow, risk: .high, modifiersHeld: true) == "Y")
        #expect(ApprovalCard.keycap(.allowChat, risk: .high, modifiersHeld: true) == nil)
        #expect(ApprovalCard.keycap(.allowChat, risk: .low, modifiersHeld: true) == "A")
    }

    @Test func theHeadlineIsAVerbAndTheCommandStaysWhole() {
        #expect(ApprovalCard.headline(tool: "Bash", command: "git status --short", file: nil, added: nil, removed: nil, host: nil) == "Run git status --short")
        #expect(ApprovalCard.headline(tool: "Edit", command: "Edit View.swift", file: "View.swift", added: 4, removed: 1, host: nil) == "Edit View.swift +4 −1")
        #expect(ApprovalCard.headline(tool: "Write", command: "Write Note.md", file: "Note.md", added: nil, removed: nil, host: nil) == "Write Note.md")
        #expect(ApprovalCard.headline(tool: "Read", command: "Read /tmp/a.txt", file: "/tmp/a.txt", added: nil, removed: nil, host: nil) == "Read /tmp/a.txt")
        #expect(ApprovalCard.headline(tool: "WebFetch", command: "https://example.com/a", file: nil, added: nil, removed: nil, host: "example.com") == "Fetch example.com")
        let command = (1...8).map { "line \($0)" }.joined(separator: "\n")
        let collapsed = ApprovalCard.commandBlock(command, expanded: false)
        #expect(collapsed.canExpand)
        #expect(collapsed.text.split(separator: "\n").count == 6)
        #expect(!collapsed.text.contains("…"))
        let open = ApprovalCard.commandBlock(command, expanded: true)
        #expect(open.text == command)
    }

    @Test func theHeaderWhyAndHighRiskAreSeparateFromAStatusChip() {
        let card = ApprovalCard.make(ApprovalCard.Input(
            tool: "Bash", command: "rm -rf /tmp/build", file: nil, added: nil, removed: nil, host: nil,
            why: "Clean the build folder", sessionTitle: "Ship the card", agent: "Zeus", project: "repo",
            risk: .high, reasons: ["deletes files"], queueIndex: 0, queueCount: 1,
            modifiersHeld: false, expanded: false, holdElapsed: 0, reduceMotion: false, phase: .asking))
        #expect(card.headline == "Run rm -rf /tmp/build")
        #expect(card.why == "Clean the build folder")
        #expect(card.header == "Ship the card · Zeus · repo")
        #expect(card.highRisk)
        #expect(card.reasons == ["deletes files"])
        #expect(card.statusChip == nil)
        #expect(card.countdown == nil)
    }

    @Test func theQueueShowsPipsAPeekAndADecidedFlash() {
        #expect(ApprovalCard.position(index: 0, count: 3) == "1 of 3")
        #expect(ApprovalCard.showsNextEdge(count: 3))
        #expect(!ApprovalCard.showsNextEdge(count: 1))
        #expect(ApprovalCard.step(index: 0, count: 3, by: 1) == 1)
        #expect(ApprovalCard.step(index: 0, count: 3, by: -1) == 0)
        #expect(ApprovalCard.flash(allowed: true) == "Allowed")
        #expect(ApprovalCard.flash(allowed: false) == "Denied")
        #expect(ApprovalCard.timeout(risk: .low) == "Handed back to terminal")
        #expect(ApprovalCard.timeout(risk: .high) == "Denied (timed out)")
        #expect(ApprovalCard.denyAllTitle == "Deny all")
        #expect(!ApprovalQueueState.allowAllExists)
        #expect(ApprovalCard.holdFraction(elapsed: 0.4) == 0.5)
    }

    @Test func reduceMotionFadesAndConfirmsHighRiskInTwoSteps() {
        #expect(ApprovalCard.motion(reduceMotion: true) == .fade)
        #expect(ApprovalCard.motion(reduceMotion: false) == .slide)
        #expect(ApprovalCard.usesTwoStep(risk: .high, reduceMotion: true))
        #expect(!ApprovalCard.usesTwoStep(risk: .high, reduceMotion: false))
        #expect(ApprovalCard.nextAllowStep(.idle, risk: .high, reduceMotion: true) == .confirm)
        #expect(ApprovalCard.nextAllowStep(.confirm, risk: .high, reduceMotion: true) == .done)
        #expect(ApprovalCard.announcement(risk: .high, position: "2 of 3", outcome: "Allowed") == "High risk, 2 of 3, Allowed")
    }
}
