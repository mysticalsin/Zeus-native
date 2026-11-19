import Foundation
import Testing
@testable import ZeusCore

/// How an app's answer to the window list question counts for the pass: a list, a clear "none", or no answer in time.
@Suite struct TileWindowsAnswerTests {
    @Test func successIsAList() {
        #expect(TileWindowsAnswer.classify(axError: 0) == .answered)
    }

    @Test func noValueAndUnsupportedAreAnAnswerOfNoWindows() {
        #expect(TileWindowsAnswer.classify(axError: TileWindowsAnswer.noValueCode) == .noWindows,
                "an app that closed its last window may say it has no value")
        #expect(TileWindowsAnswer.classify(axError: TileWindowsAnswer.attributeUnsupportedCode) == .noWindows)
    }

    @Test func aTimeoutAndEveryOtherFailureLeaveTheAppUnread() {
        #expect(TileWindowsAnswer.classify(axError: TileWindowsAnswer.cannotCompleteCode) == .unread, "the app did not answer in time")
        for code: Int32 in [-25200, -25201, -25202, -25203, -25206, -25207, -25208, -25209, -25210, -25211, 1, -1] {
            #expect(TileWindowsAnswer.classify(axError: code) == .unread, "code \(code)")
        }
    }

    // MARK: One window's attribute read

    @Test func onlyASuccessfulReadOfAWindowCountsAsRead() {
        #expect(TileWindowsAnswer.windowRead(axError: 0))
        #expect(!TileWindowsAnswer.windowRead(axError: TileWindowsAnswer.cannotCompleteCode),
                "a busy app times out on one window: that window is slow, not closed")
        for code: Int32 in [-25200, -25201, -25202, -25203, -25205, -25206, -25207, -25208, -25209, -25210, -25211, -25212, 1, -1] {
            #expect(!TileWindowsAnswer.windowRead(axError: code), "code \(code)")
        }
    }

    // MARK: The size-settable question

    @Test func aSuccessfulSettableCheckGivesItsOwnAnswer() {
        #expect(TileWindowsAnswer.sizeSettable(axError: 0, value: true) == true)
        #expect(TileWindowsAnswer.sizeSettable(axError: 0, value: false) == false)
    }

    @Test func aWindowWithNoSizeAttributeIsDefinitelyNotResizable() {
        #expect(TileWindowsAnswer.sizeSettable(axError: TileWindowsAnswer.attributeUnsupportedCode, value: true) == false,
                "the value out parameter is not read after a failure")
    }

    @Test func aTimeoutAndEveryOtherFailureGiveNoAnswerSoTheAppCountsAsUnread() {
        #expect(TileWindowsAnswer.sizeSettable(axError: TileWindowsAnswer.cannotCompleteCode, value: false) == nil,
                "a busy app that answered the list and the attributes, then timed out on this one question")
        for code: Int32 in [-25200, -25201, -25202, -25203, -25206, -25207, -25208, -25209, -25210, -25211, -25212, 1, -1] {
            #expect(TileWindowsAnswer.sizeSettable(axError: code, value: false) == nil, "code \(code)")
        }
    }
}
