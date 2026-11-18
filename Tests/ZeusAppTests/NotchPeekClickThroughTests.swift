import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// While a peek or an approval is up, the notch window takes the mouse only over the card on screen.
@MainActor @Suite("Notch peek click-through") struct NotchPeekClickThroughTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let notch = NotchFootprint.hardware(CGSize(width: 184, height: 32))

    private func approvalModel() -> NotchModel {
        let model = NotchModel()
        model.approval = NotchModel.Approval(id: "a", agent: "Claude", project: "zeus", tool: "Bash", command: "ls",
                                             risk: .low, resolve: { _ in })
        model.presentation = .peek
        return model
    }

    private func takes(_ model: NotchModel, x: CGFloat, fromTop: CGFloat) -> Bool {
        NotchController.peekTakesMouse(model: model, footprint: notch, pointer: CGPoint(x: x, y: screen.maxY - fromTop),
                                       screenFrame: screen, topOffset: 0)
    }

    @Test func approvalCardTakesTheMouseOnlyUnderThePointer() {
        let model = approvalModel()
        #expect(takes(model, x: screen.midX, fromTop: 60))
        #expect(!takes(model, x: screen.midX, fromTop: 300))
        #expect(!takes(model, x: screen.maxX - 2, fromTop: 60))
    }

    @Test func completionCardTakesTheMouseOnlyUnderThePointer() {
        let model = NotchModel()
        model.completion = AgentCompletion(sessionID: "s", agent: "Claude", project: "zeus", summary: "Done", startedAt: nil)
        model.presentation = .peek
        #expect(takes(model, x: screen.midX, fromTop: 40))
        #expect(!takes(model, x: screen.midX, fromTop: 300))
        #expect(!takes(model, x: screen.minX + 2, fromTop: 40))
    }

    @Test func approvalCardSizeMatchesWhatTheViewDraws() {
        let model = approvalModel()
        let size = NotchView.peekSize(model: model, footprint: notch)
        // Fixture width: the hardware notch is 184 pt.
        #expect(notch.layoutSize.width == 184)
        #expect(size.width == max(notch.layoutSize.width + 2 * 8 + 240, 440))
        #expect(size.height == 32 + 98 + (model.approval?.extraHeight ?? 0))
    }

    // MARK: Controller wiring

    private let midX: CGFloat = 756

    private func controller(pointerFromTop fromTop: CGFloat, x: CGFloat? = nil) -> NotchController {
        let controller = NotchController()
        controller.frameOverride = screen
        controller.pointer = { CGPoint(x: x ?? 756, y: 982 - fromTop) }
        return controller
    }

    private func approve(_ model: NotchModel, resolve: @escaping @MainActor (HookDecision.Verdict) -> Void = { _ in }) {
        model.approval = NotchModel.Approval(id: "a", agent: "Claude", project: "zeus", tool: "Bash", command: "ls",
                                             risk: .low, resolve: resolve)
    }

    private func barOnlyPeek(_ controller: NotchController) {
        controller.model.sessions = [NotchModel.Session(id: "s", agent: "Claude", project: "zeus", task: "t", status: .working, startedAt: Date())]
        controller.model.peekSessionID = "s"
        controller.show(.peek)
    }

    @Test func showingAnApprovalPeekWithThePointerOutsideTheCardIsClickThrough() {
        let outside = controller(pointerFromTop: 60, x: 1500)
        defer { outside.show(.closed) }
        approve(outside.model)
        outside.show(.peek)
        #expect(outside.clickThrough)
        let inside = controller(pointerFromTop: 60)
        defer { inside.show(.closed) }
        approve(inside.model)
        inside.show(.peek)
        #expect(!inside.clickThrough)
    }

    @Test func aCompletionSetWhileABarOnlyPeekIsUpTakesTheMouseWithoutAMouseMove() {
        let controller = controller(pointerFromTop: 50)
        defer { controller.show(.closed) }
        barOnlyPeek(controller)
        #expect(controller.clickThrough)
        controller.model.completion = AgentCompletion(sessionID: "s", agent: "Claude", project: "zeus", summary: "Done", startedAt: nil)
        #expect(!controller.clickThrough)
        controller.model.completion = nil
        #expect(controller.clickThrough)
    }

    @Test func aFailureSetWhileAPeekIsUpTakesTheMouseWithoutAMouseMove() {
        let controller = controller(pointerFromTop: 50)
        defer { controller.show(.closed) }
        barOnlyPeek(controller)
        controller.model.failure = NotchModel.Failure(sessionID: "s", agent: "Claude", project: "zeus", reason: "boom")
        #expect(!controller.clickThrough)
    }

    @Test func aRecapSetWhileAPeekIsUpTakesTheMouseWithoutAMouseMove() {
        let controller = controller(pointerFromTop: 50)
        defer { controller.show(.closed) }
        barOnlyPeek(controller)
        controller.model.recap = WelcomeRecap(awaySeconds: 600, finished: [], failed: [], waiting: [])
        #expect(!controller.clickThrough)
    }

    @Test func aSelectionEditAndWorkBehindSetWhileAPeekIsUpTakeTheMouseWithoutAMouseMove() {
        let edit = controller(pointerFromTop: 50)
        defer { edit.show(.closed) }
        barOnlyPeek(edit)
        edit.model.selectionEdit = SelectionEdit(kind: .replace, before: "a", after: "b")
        #expect(!edit.clickThrough)
        let behind = controller(pointerFromTop: 50)
        defer { behind.show(.closed) }
        barOnlyPeek(behind)
        behind.model.workBehind = WorkBehindPreview(streaming: true, title: "Notes")
        #expect(!behind.clickThrough)
    }

    @Test func aStalledSessionPeekTakesTheMouseOverItsCardWithoutAMouseMove() {
        let controller = controller(pointerFromTop: 50)
        defer { controller.show(.closed) }
        barOnlyPeek(controller)
        controller.model.sessions[0].status = .stalled
        #expect(!controller.clickThrough)
    }

    @Test func answeringAnApprovalLeavesTheLingeringPeekClickThroughOutsideTheBar() async {
        _ = NSApplication.shared
        let controller = controller(pointerFromTop: 100)
        defer { controller.show(.closed) }
        let verdict = Task { @MainActor in
            await controller.requestApproval(agent: "Claude", project: "zeus", tool: "Bash", command: "ls", risk: .low,
                                             timeout: .seconds(30))
        }
        while controller.model.approval == nil { await Task.yield() }
        #expect(controller.model.presentation == .peek)
        #expect(!controller.clickThrough)
        controller.model.approval?.resolve(.allow)
        #expect(await verdict.value == .allow)
        #expect(controller.model.presentation == .peek)
        #expect(controller.clickThrough)
    }

    @Test func aBarOnlyPeekFollowsTheClosedRuleSoTheMenuBarStaysClickable() {
        let controller = controller(pointerFromTop: 10)
        defer { controller.show(.closed) }
        barOnlyPeek(controller)
        // The pill is click-through while closed; a session peek with no card is no different.
        #expect(controller.clickThrough)
    }

    @Test func aSelectionEditPeekIsDrawnAtItsOwnSizeWithRoomForAccept() {
        let model = NotchModel()
        model.selectionEdit = SelectionEdit(kind: .replace, before: "one", after: "two")
        model.presentation = .peek
        let size = NotchView.peekSize(model: model, footprint: notch)
        #expect(size.width == 520)
        #expect(size.height >= 32 + 10 + 28)
        #expect(takes(model, x: screen.midX, fromTop: size.height - 10))
    }

    @Test func aWorkBehindPeekIsDrawnAtItsOwnSize() {
        let model = NotchModel()
        model.workBehind = WorkBehindPreview(streaming: true, title: "Notes")
        model.presentation = .peek
        let size = NotchView.peekSize(model: model, footprint: notch)
        #expect(size.height >= 32 + 10 + 24)
    }

    // MARK: Long selection edits stay inside the window

    /// The diff is a settable array, so a producer can hand the card any number of long rows.
    private func longEdit(lines: Int, width: Int = 200) -> SelectionEdit {
        var edit = SelectionEdit(kind: .replace, before: "old", after: "new")
        edit.diff = (0..<lines).map {
            TextDiffLine(id: $0, kind: $0 % 2 == 0 ? .removed : .added, text: "line \($0) " + String(repeating: "x", count: width))
        }
        return edit
    }

    private func editPeek(_ edit: SelectionEdit) -> NotchModel {
        let model = NotchModel()
        model.selectionEdit = edit
        model.presentation = .peek
        return model
    }

    private let lowestOffset = CGFloat(TopBarPosition.maximum)

    @Test func aLongSelectionEditCardKeepsItsAcceptRowInsideTheNotchWindow() {
        let size = NotchView.peekSize(model: editPeek(longEdit(lines: 60)), footprint: notch)
        #expect(lowestOffset + size.height <= GlanceTopBar.windowHeight)
    }

    @Test func aLongSelectionEditCardLayoutFitsTheBudgetAndCountsWhatItHides() {
        let edit = longEdit(lines: 60)
        let layout = NotchView.selectionEditLayout(edit, barHeight: 32)
        #expect(layout.hidden > 0)
        #expect(layout.moreText == "+\(layout.hidden) more lines")
        #expect(layout.rows.count + layout.hidden == edit.diff.count)
        let size = NotchView.peekSize(model: editPeek(edit), footprint: notch)
        #expect(size.height == 32 + 10 + layout.height)
    }

    @Test func aShortSelectionEditCardIsUnchangedAndHidesNothing() {
        let edit = SelectionEdit(kind: .replace, before: "one", after: "two")
        let layout = NotchView.selectionEditLayout(edit, barHeight: 32)
        #expect(layout.hidden == 0)
        #expect(layout.moreText == nil)
        #expect(layout.rows.count == edit.diff.count)
        #expect(layout.height == 28 + CGFloat(edit.diff.count) * (15 + 4))
        #expect(NotchView.peekSize(model: editPeek(edit), footprint: notch).height == 32 + 10 + layout.height)
    }

    @Test func aLongSelectionEditCardPinsEachRowToTheHeightTheSizeUses() {
        let layout = NotchView.selectionEditLayout(longEdit(lines: 3), barHeight: 32)
        #expect(layout.rows.allSatisfy { $0.textLines == 2 && $0.height == 30 })
        let short = NotchView.selectionEditLayout(SelectionEdit(kind: .replace, before: "a", after: "b"), barHeight: 32)
        #expect(short.rows.allSatisfy { $0.textLines == 1 && $0.height == 15 })
    }

    @Test func aCappedSelectionEditCardTakesTheMouseOverItsAcceptRow() {
        let model = editPeek(longEdit(lines: 60))
        let size = NotchView.peekSize(model: model, footprint: notch)
        let acceptFromTop = lowestOffset + size.height - 14
        let hit = NotchController.peekTakesMouse(
            model: model, footprint: notch, pointer: CGPoint(x: screen.maxX / 2 + 100, y: screen.maxY - acceptFromTop),
            screenFrame: screen, topOffset: lowestOffset)
        #expect(hit)
        #expect(acceptFromTop < GlanceTopBar.windowHeight)
    }
}
