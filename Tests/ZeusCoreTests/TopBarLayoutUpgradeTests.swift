import Foundation
import Testing
@testable import ZeusCore

@Suite struct TopBarLayoutUpgradeTests {
    /// A layout saved by an older build must still show tabs added since (no saved-layout trap).
    @Test func newTabsAppearInOldSavedLayouts() {
        let old = #"["home","agents","music"]"#
        let layout = TopBarLayout.decode(old, known: nil)
        #expect(layout.tabs == TopBarLayout.standard.tabs)
    }

    @Test func tabsTheUserTurnedOffStayOff() {
        var layout = TopBarLayout.standard
        layout.toggle(.music)
        let saved = layout.encoded()
        let known = TopBarLayout.knownEncoded()
        #expect(TopBarLayout.decode(saved, known: known) == layout)
    }
}

@Suite struct TenTabRowTests {
    @Test func defaultRowIsTwelveWithScribeLast() {
        #expect(TopBarLayout.defaultRow.count == 12)
        #expect(TopBarLayout.defaultRow.last == .scribe)
        let recordly = TopBarLayout.defaultRow.firstIndex(of: .recordly)
        let scribe = TopBarLayout.defaultRow.firstIndex(of: .scribe)
        #expect(recordly != nil && scribe != nil && recordly! < scribe!)
        // Polyglot metadata is unchanged; it is still the tenth tab.
        #expect(TopBarLayout.defaultRow[9] == .polyglot)
        #expect(TopBarTab.polyglot.title == "Polyglot")
        #expect(TopBarTab.polyglot.symbol == "globe")
        #expect(TopBarTab.scribe.title == "Scribe")
        #expect(TopBarTab.scribe.symbol == "waveform.and.mic")
        #expect(TopBarLayout.standard.tabs.prefix(12).elementsEqual(TopBarLayout.defaultRow))
        #expect(GlanceTopBar.maxTabs == 12)
    }

    @Test func recordlyLayoutUpgradesToScribeOnce() {
        let eleven = TopBarLayout(tabs: TopBarLayout.glanceSeven + [.teleprompter, .insomnia, .polyglot, .recordly, .reminders, .usage])
        let upgraded = eleven.upgradedToScribeRow()
        #expect(upgraded.tabs == TopBarLayout.glanceSeven + [.teleprompter, .insomnia, .polyglot, .recordly, .scribe, .reminders, .usage])
        // Running it again changes nothing.
        #expect(upgraded.upgradedToScribeRow() == upgraded)
    }

    @Test func scribeUpgradeKeepsCustomHiddenLayouts() {
        // A tab turned off (Clipboard, Shelf) stays off; Scribe is appended and ordered after Recordly.
        let custom = TopBarLayout(tabs: [.home, .recordly, .chat])
        #expect(custom.upgradedToScribeRow().tabs == [.home, .chat, .recordly, .scribe])
        #expect(!custom.upgradedToScribeRow().contains(.clipboard))
        #expect(!custom.upgradedToScribeRow().contains(.shelf))
    }

    @Test func scribeUpgradeKeepsTheSelectedTabVisible() {
        let layout = TopBarLayout.standard.upgradedToScribeRow()
        let visible = GlanceTabRow.visible(layout.tabs, selected: TopBarTab.usage)
        #expect(visible.count == GlanceTopBar.maxTabs)
        #expect(visible.contains(.usage))
        #expect(GlanceTabRow.visible(layout.tabs, selected: TopBarTab.scribe).contains(.scribe))
    }

    @Test func tenTabLayoutUpgradesToRecordlyOnce() {
        let ten = TopBarLayout(tabs: TopBarLayout.glanceSeven + [.teleprompter, .insomnia, .polyglot, .reminders, .usage])
        let upgraded = ten.upgradedToRecordlyRow()
        #expect(upgraded.tabs == TopBarLayout.glanceSeven + [.teleprompter, .insomnia, .polyglot, .recordly, .reminders, .usage])
        // Running it again changes nothing.
        #expect(upgraded.upgradedToRecordlyRow() == upgraded)
    }

    @Test func recordlyUpgradeKeepsCustomHiddenLayouts() {
        // A tab turned off (Clipboard, Shelf) stays off; Recordly is appended and ordered after Polyglot.
        let custom = TopBarLayout(tabs: [.home, .polyglot, .chat])
        #expect(custom.upgradedToRecordlyRow().tabs == [.home, .chat, .polyglot, .recordly])
        #expect(!custom.upgradedToRecordlyRow().contains(.clipboard))
        #expect(!custom.upgradedToRecordlyRow().contains(.shelf))
    }

    @Test func recordlyUpgradeKeepsTheSelectedTabVisible() {
        let layout = TopBarLayout.standard.upgradedToRecordlyRow()
        let visible = GlanceTabRow.visible(layout.tabs, selected: TopBarTab.usage)
        #expect(visible.count == GlanceTopBar.maxTabs)
        #expect(visible.contains(.usage))
        #expect(GlanceTabRow.visible(layout.tabs, selected: TopBarTab.recordly).contains(.recordly))
    }

    @Test func nineTabLayoutUpgradesOnce() {
        let nine = TopBarLayout(tabs: TopBarLayout.glanceSeven + [.teleprompter, .insomnia, .reminders, .usage])
        let upgraded = nine.upgradedToTenTabRow()
        #expect(upgraded.tabs == TopBarLayout.glanceSeven + [.teleprompter, .insomnia, .polyglot, .reminders, .usage])
        // Running it again changes nothing.
        #expect(upgraded.upgradedToTenTabRow() == upgraded)
        // Tabs turned off stay off.
        let custom = TopBarLayout(tabs: [.home, .shelf, .insomnia])
        #expect(custom.upgradedToTenTabRow().tabs == [.home, .shelf, .insomnia, .polyglot])
    }

    @Test func polyglotAppearsInLayoutsSavedBeforeIt() {
        let knownBefore = TopBarTab.allCases.filter { $0 != .polyglot }.map(\.rawValue)
        let known = String(decoding: try! JSONEncoder().encode(knownBefore), as: UTF8.self)
        let layout = TopBarLayout.decode(#"["home","chat"]"#, known: known)
        #expect(layout.contains(.polyglot))
    }

    @Test func twelveTabsFitTheRoom() {
        // Worst case: the longest selected label ("Teleprompter" is "Prompter"; Polyglot and Recordly are 8 letters) and three counts.
        let widest = TopBarLayout.defaultRow.map { GlanceTopBar.selectedPillWidth(title: $0.title, countWidth: 26) }.max() ?? 0
        let worst = GlanceTopBar.capsuleWidth(tabs: 12, countsExtra: 3 * 26 + widest - GlanceTopBar.selectedPill.width)
        #expect(worst < GlanceTopBar.rowRoom)
        // Plain case: no counts, Home selected. The old fixed 600 pt bound cannot hold for twelve tabs
        // (12 tabs are 632 pt wide), so the bound is the real row room.
        #expect(GlanceTopBar.capsuleWidth(tabs: 12) < GlanceTopBar.rowRoom)
    }
}
