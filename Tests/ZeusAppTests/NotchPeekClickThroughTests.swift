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
        #expect(size.width == max(184 + 2 * 8 + 240, 440))
        #expect(size.height == 32 + 98 + (model.approval?.extraHeight ?? 0))
    }
}
