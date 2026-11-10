import Foundation
import Testing
@testable import ZeusCore

@Suite struct DictateFileRoutingTests {
    @Test func wakePhraseNeedsWakePathNotDictationAlone() {
        #expect(WakePhrase.spot("hey zeus what time is it")?.request == "what time is it")
        #expect(WakePhrase.spot("hello zeus this is a dictation test") == nil)
    }
}
