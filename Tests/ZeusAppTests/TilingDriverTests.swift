import ApplicationServices
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The real Accessibility driver with Accessibility off. The Accessibility and window-list paths themselves are
/// proven on a Mac, not here: this suite checks only that nothing is read or written without the permission.
@Suite(.serialized) @MainActor struct TilingDriverTests {
    @Test func withAccessibilityOffEveryEntryPointIsANoOpThatReportsTheState() {
        let driver = AXTilingWindowDriver(isTrusted: { false })
        #expect(!driver.isTrusted)
        #expect(driver.windows(config: TileConfig()).isEmpty)
        #expect(!driver.setFrame(TileRect(x: 0, y: 0, width: 500, height: 500), for: TileWindowID(pid: 1, index: 1)))
        driver.focus(TileWindowID(pid: 1, index: 1))

        let move = TileMove(id: TileWindowID(pid: 1, index: 1), target: TileRect(x: 0, y: 0, width: 500, height: 500),
                            current: TileRect(x: 50, y: 50, width: 300, height: 300))
        let outcome = TileApplier.apply(TileMovePlan(moves: [move], inPlace: [], missing: []), with: driver)
        #expect(outcome.state == .accessibilityOff)
        #expect(outcome.moved.isEmpty && outcome.refused.isEmpty)
    }

    @Test func aWindowTheDriverNeverListedIsNotWritten() {
        let driver = AXTilingWindowDriver(isTrusted: { true })
        #expect(!driver.setFrame(TileRect(x: 0, y: 0, width: 500, height: 500), for: TileWindowID(pid: 999_999, index: 77)),
                "no element is known for that id, so nothing is written")
    }

    @Test func theAnswerCodesThePureRuleReadsAreTheSystemsOwn() {
        #expect(TileWindowsAnswer.cannotCompleteCode == AXError.cannotComplete.rawValue)
        #expect(TileWindowsAnswer.attributeUnsupportedCode == AXError.attributeUnsupported.rawValue)
        #expect(TileWindowsAnswer.noValueCode == AXError.noValue.rawValue)
        #expect(TileWindowsAnswer.classify(axError: AXError.success.rawValue) == .answered)
        #expect(TileWindowsAnswer.classify(axError: AXError.noValue.rawValue) == .noWindows)
        #expect(TileWindowsAnswer.classify(axError: AXError.cannotComplete.rawValue) == .unread)
        #expect(TileWindowsAnswer.windowRead(axError: AXError.success.rawValue))
        #expect(!TileWindowsAnswer.windowRead(axError: AXError.cannotComplete.rawValue))
        #expect(!TileWindowsAnswer.windowRead(axError: AXError.invalidUIElement.rawValue))
        #expect(TileWindowsAnswer.sizeSettable(axError: AXError.success.rawValue, value: true) == true)
        #expect(TileWindowsAnswer.sizeSettable(axError: AXError.attributeUnsupported.rawValue, value: true) == false)
        #expect(TileWindowsAnswer.sizeSettable(axError: AXError.cannotComplete.rawValue, value: false) == nil)
    }
}
