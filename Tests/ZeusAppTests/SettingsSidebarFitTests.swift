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
        #expect(bottom(rowCount: GSSection.shown.count) <= Layout.versionY)
    }

    @Test func everySectionShownStillClearsTheVersionLine() {
        // The worst case: the iPhone page joins the sidebar and nothing is hidden.
        #expect(bottom(rowCount: GSSection.allCases.count) <= Layout.versionY)
        for count in 1...(GSSection.allCases.count + 4) {
            #expect(bottom(rowCount: count) <= Layout.versionY, "\(count) rows")
        }
    }

    @Test func theHeadingsAreThreeGroupsWithTwoGaps() {
        #expect(GSSection.Group.allCases.count == 3)
        #expect(Layout.headingsHeight == 92)
    }

    @Test func fewRowsKeepTheOriginalSpacing() {
        let metrics = Layout.rowMetrics(rowCount: 19)
        #expect(metrics.height == 26)
        #expect(metrics.gap == 2)
    }

    @Test func aRowNeverGetsTallerThanTheDesign() {
        for count in 1...30 {
            let metrics = Layout.rowMetrics(rowCount: count)
            #expect(metrics.height <= 26, "\(count) rows")
            #expect(metrics.height > 0, "\(count) rows")
            #expect(metrics.gap >= 1, "\(count) rows")
        }
    }
}
