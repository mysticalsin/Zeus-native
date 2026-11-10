import Foundation
import Testing
import ZeusCore

/// The tab-row rules Settings › Appearance › Top bar tabs leans on: it toggles, moves and counts through
/// `TopBarLayout`, so a full row, Home's place and the saved format have to hold.
struct W5SettingsTabRowTests {
    private func fullRow() -> TopBarLayout {
        TopBarLayout(tabs: Array(TopBarTab.allCases.prefix(GlanceTopBar.maxTabs)))
    }

    @Test func fullRowReportsFullAndRefusesAnotherTab() {
        var layout = fullRow()
        #expect(layout.isFull())
        let before = layout.tabs
        let extra = TopBarTab.allCases.first { !layout.contains($0) }
        #expect(extra != nil)
        if let extra { layout.append(extra) }
        #expect(layout.tabs == before)
    }

    @Test func rowBelowTheLimitIsNotFull() {
        let layout = TopBarLayout(tabs: [.chat, .music])
        #expect(!layout.isFull())
        #expect(layout.tabs == [.home, .chat, .music])
    }

    @Test func toggleBringsATabBackInItsUsualPlace() {
        var layout = TopBarLayout(tabs: [.chat, .music])
        layout.toggle(.today)
        #expect(layout.tabs == [.home, .today, .chat, .music])
        layout.toggle(.calendar)
        #expect(layout.tabs == [.home, .today, .chat, .music, .calendar])
    }

    @Test func toggleOffRemovesAndHomeNeverToggles() {
        var layout = TopBarLayout(tabs: [.chat, .music])
        layout.toggle(.chat)
        #expect(layout.tabs == [.home, .music])
        layout.toggle(.home)
        #expect(layout.tabs == [.home, .music])
    }

    @Test func moveKeepsHomeFirstAndClampsAtBothEnds() {
        var layout = TopBarLayout(tabs: [.chat, .music, .calendar])
        layout.move(.calendar, by: -10)
        #expect(layout.tabs == [.home, .calendar, .chat, .music])
        layout.move(.calendar, by: 10)
        #expect(layout.tabs == [.home, .chat, .music, .calendar])
        layout.move(.home, by: 2)
        #expect(layout.tabs.first == .home)
        #expect(layout.tabs == [.home, .chat, .music, .calendar])
    }

    @Test func savedLayoutRoundTrips() {
        let layout = TopBarLayout(tabs: [.music, .chat, .waves])
        let decoded = TopBarLayout.decode(layout.encoded(), known: TopBarLayout.knownEncoded())
        #expect(decoded == layout)
    }

    @Test func unreadableSavedLayoutFallsBackToTheStandardRow() {
        #expect(TopBarLayout.decode("not json") == .standard)
        #expect(TopBarLayout.decode(nil, known: nil) == .standard)
    }

    @Test func aLayoutWithoutItsKnownListShowsTheStandardRow() {
        // Why the export carries `topBar.tabs.known` with `topBar.tabs`: without it the saved row is ignored.
        let layout = TopBarLayout(tabs: [.chat])
        #expect(TopBarLayout.decode(layout.encoded(), known: nil) == .standard)
    }

    @Test func selectedTabStaysVisibleWhenTheSavedRowIsLonger() {
        let tabs = Array(TopBarTab.allCases.prefix(GlanceTopBar.maxTabs + 2))
        let selected = tabs[tabs.count - 1]
        let visible = GlanceTabRow.visible(tabs, selected: selected)
        #expect(visible.count == GlanceTopBar.maxTabs)
        #expect(visible.contains(selected))
    }
}
