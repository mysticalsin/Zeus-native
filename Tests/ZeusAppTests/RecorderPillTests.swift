import Foundation
import Testing
@testable import Zeus

/// Section 10 P0 (Devon, murmure dictation pill): the elapsed-time label must render as one
/// token on one line ("0:02"), never wrap ("0:" over "02").
@Suite struct RecorderPillTests {
    @Test func clockIsOneLineMinuteColonTwoDigitSeconds() {
        #expect(RecorderPillView.clock(0) == "0:00")
        #expect(RecorderPillView.clock(2) == "0:02")
        #expect(RecorderPillView.clock(9) == "0:09")
        #expect(RecorderPillView.clock(61) == "1:01")
        #expect(RecorderPillView.clock(599) == "9:59")
    }

    @Test func clockNeverContainsWhitespaceOrNewlines() {
        for seconds in [0.0, 2.0, 9.4, 61.9, 3599.0] {
            let text = RecorderPillView.clock(seconds)
            #expect(!text.contains(" "))
            #expect(!text.contains("\n"))
        }
    }

    @Test func clockClampsNegativeToZero() {
        #expect(RecorderPillView.clock(-1) == "0:00")
    }
}
