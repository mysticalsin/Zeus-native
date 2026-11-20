import Testing
@testable import Zeus

/// The Settings sidebar has a fixed height: its rows must end above the version line however many sections show.
struct SettingsSidebarFitTests {
    private typealias Layout = GSSection.SidebarLayout

    private func bottom(rowCount: Int) -> Double {
        let metrics = Layout.rowMetrics(rowCount: rowCount)
        return Layout.top + Layout.headingsHeight + Double(rowCount) * (metrics.height + metrics.gap)
    }

    @Test func theShownRowsClearTheVersionLine() {
        #expect(Layout.scrollHeight <= Layout.versionY - Layout.top)
        #expect(bottom(rowCount: GSSection.shown.count) > Layout.versionY)
    }

    @Test func everySectionShownStillClearsTheVersionLine() {
        // Rows stay 30 points. A full sidebar is taller than the version line and scrolls inside it.
        #expect(bottom(rowCount: GSSection.allCases.count) > Layout.versionY)
        #expect(Layout.rowMetrics(rowCount: GSSection.allCases.count).height == 30)
    }

    @Test func theHeadingsAreThreeGroupsWithTwoGaps() {
        #expect(GSSection.Group.allCases.count == 3)
        #expect(Layout.headingsHeight == 92)
    }

    @Test func fewRowsKeepTheOriginalSpacing() {
        let metrics = Layout.rowMetrics(rowCount: 19)
        #expect(metrics.height == 30)
        #expect(metrics.gap == 2)
    }

    @Test func aRowNeverGetsTallerThanTheDesign() {
        for count in 1...30 {
            let metrics = Layout.rowMetrics(rowCount: count)
            #expect(metrics.height == 30, "\(count) rows")
            #expect(metrics.gap == 2, "\(count) rows")
        }
    }
}
