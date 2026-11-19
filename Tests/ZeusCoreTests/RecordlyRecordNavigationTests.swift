import Foundation
import Testing
@testable import ZeusCore

@Suite("Record section navigation")
struct RecordlyRecordNavigationTests {
    private let window = RecordlySourceSelection.SelectionIntent.window(number: 42, identityToken: "w42")
    private let display = RecordlySourceSelection.SelectionIntent.display(id: 1)

    @Test func singleClickSelectsAndStaysOnTheGrid() {
        var navigation = RecordlyRecordNavigation()
        let effect = navigation.click(window, count: 1, canChoose: true, isSelected: false)
        #expect(effect == .select)
        #expect(navigation.screen == .grid)
        #expect(navigation.openCount == 0)
    }

    @Test func doubleClickSelectsAndOpensTheDetail() {
        var navigation = RecordlyRecordNavigation()
        let effect = navigation.click(window, count: 2, canChoose: true, isSelected: false)
        #expect(effect == .selectAndOpen)
        #expect(navigation.screen == .detail(window))
        #expect(navigation.detailSource == window)
        #expect(navigation.isDetail)
    }

    @Test func displaysOpenTheirOwnDetailToo() {
        var navigation = RecordlyRecordNavigation()
        navigation.click(display, count: 2, canChoose: true, isSelected: true)
        #expect(navigation.screen == .detail(display))
    }

    @Test func whileCapturingOnlyTheSelectedSourceOpens() {
        var navigation = RecordlyRecordNavigation()
        let other = navigation.click(window, count: 2, canChoose: false, isSelected: false)
        #expect(other == .none)
        #expect(navigation.screen == .grid)
        let single = navigation.click(window, count: 1, canChoose: false, isSelected: true)
        #expect(single == .none)
        let selected = navigation.click(window, count: 2, canChoose: false, isSelected: true)
        #expect(selected == .open)
        #expect(navigation.screen == .detail(window))
    }

    @Test func areaAndZeroClicksDoNothing() {
        var navigation = RecordlyRecordNavigation()
        let area = RecordlySourceSelection.SelectionIntent.region(displayID: 1, x: 0, y: 0, width: 10, height: 10)
        let areaEffect = navigation.click(area, count: 2, canChoose: true, isSelected: false)
        #expect(areaEffect == .none)
        let zero = navigation.click(window, count: 0, canChoose: true, isSelected: false)
        #expect(zero == .none)
        #expect(navigation.screen == .grid)
    }

    @Test func everyOpenIsANewDetailThatStartsAtTheTop() {
        var navigation = RecordlyRecordNavigation()
        navigation.open(window)
        let first = navigation.openCount
        navigation.back()
        #expect(navigation.screen == .grid)
        navigation.open(window)
        #expect(navigation.openCount == first + 1)
        navigation.open(display)
        #expect(navigation.openCount == first + 2)
        #expect(navigation.screen == .detail(display))
    }

    @Test func detailClosesWhenItsSourceIsGoneWhileIdle() {
        var navigation = RecordlyRecordNavigation()
        navigation.open(window)
        navigation.reconcile(sourceAvailable: true, capturing: false, editor: false)
        #expect(navigation.isDetail)
        navigation.reconcile(sourceAvailable: false, capturing: true, editor: false)
        #expect(navigation.isDetail)
        navigation.reconcile(sourceAvailable: false, capturing: false, editor: false)
        #expect(navigation.screen == .grid)
    }

    @Test func savedClipReturnsToTheGrid() {
        var navigation = RecordlyRecordNavigation()
        navigation.open(display)
        navigation.reconcile(sourceAvailable: true, capturing: false, editor: true)
        #expect(navigation.screen == .grid)
    }

    @Test func pagingFitsTilesAndNeverDropsBelowOne() {
        let paging = RecordlySourceGridPaging(width: 520, height: RecordlyRecordLayout.standardTileRoomHeight,
                                              minTileWidth: RecordlyRecordLayout.windowTileMinWidth,
                                              tileHeight: RecordlyRecordLayout.windowTileHeight,
                                              spacing: RecordlyRecordLayout.gridSpacing)
        #expect(paging.columns == 3)
        #expect(paging.rows == 3)
        #expect(paging.pageSize == 9)
        let tiny = RecordlySourceGridPaging(width: 10, height: 10, minTileWidth: 150, tileHeight: 38, spacing: 6)
        #expect(tiny.pageSize == 1)
        let broken = RecordlySourceGridPaging(width: .infinity, height: .nan, minTileWidth: 0, tileHeight: 38, spacing: 6)
        #expect(broken.pageSize >= 1)
    }

    @Test func pagesClampAndSlice() {
        let paging = RecordlySourceGridPaging(columns: 3, rows: 2)
        #expect(paging.pageCount(items: 0) == 1)
        #expect(paging.pageCount(items: 6) == 1)
        #expect(paging.pageCount(items: 7) == 2)
        #expect(paging.clamp(-3, items: 7) == 0)
        #expect(paging.clamp(9, items: 7) == 1)
        #expect(paging.range(page: 0, items: 7) == 0..<6)
        #expect(paging.range(page: 1, items: 7) == 6..<7)
        #expect(paging.range(page: 5, items: 7) == 6..<7)
        #expect(paging.range(page: 0, items: 0) == 0..<0)
        #expect(paging.page(of: 0) == 0)
        #expect(paging.page(of: 6) == 1)
    }

    @Test func bothScreensFitTheTopBarPageWithoutScrolling() {
        #expect(RecordlyRecordLayout.contentHeight <= RecordlyPageLayout.innerHeight)
        #expect(RecordlyRecordLayout.minimumHeight <= RecordlyPageLayout.innerHeight)
        #expect(RecordlyRecordLayout.headerHeight + RecordlyRecordLayout.sectionGap
            + RecordlyRecordLayout.idleColumnHeight <= RecordlyPageLayout.innerHeight)
        #expect(RecordlyRecordLayout.headerHeight + RecordlyRecordLayout.sectionGap
            + RecordlyRecordLayout.capturingColumnHeight <= RecordlyPageLayout.innerHeight)
        // Three rows of window tiles fit the stage with the pager under them.
        #expect(3 * RecordlyRecordLayout.windowTileHeight + 2 * RecordlyRecordLayout.gridSpacing
            <= RecordlyRecordLayout.standardTileRoomHeight)
    }
}
