import Foundation
import Testing
@testable import ZeusCore

@Suite("Top bar upgrade and saved row")
struct W5TopBarNotchTests {
    /// The row an install had before the Recordly and Scribe tabs existed.
    private var oldRow: TopBarLayout {
        TopBarLayout(tabs: TopBarLayout.glanceSeven + [.teleprompter, .insomnia, .polyglot])
    }

    @Test func upgradeChainAddsRecordlyAndScribe() {
        let upgraded = oldRow.upgradedToRecordlyRow().upgradedToScribeRow()
        #expect(upgraded.contains(.recordly))
        #expect(upgraded.contains(.scribe))
        #expect(upgraded.tabs.first == .home)
    }

    @Test func upgradeKeepsTabsThePersonTurnedOff() {
        var row = oldRow
        row.remove(.chat)
        let upgraded = row.upgradedToScribeRow()
        #expect(!upgraded.contains(.chat))
        #expect(upgraded.contains(.scribe))
    }

    @Test func upgradedRowSurvivesTheSavedForm() {
        // init now writes this pair itself, so a relaunch must read back the same row.
        let upgraded = oldRow.upgradedToRecordlyRow().upgradedToScribeRow()
        let restored = TopBarLayout.decode(upgraded.encoded(), known: TopBarLayout.knownEncoded())
        #expect(restored == upgraded)
    }

    @Test func upgradeIsStableWhenRunTwice() {
        let once = oldRow.upgradedToScribeRow()
        let twice = once.upgradedToScribeRow()
        #expect(once == twice)
    }
}
