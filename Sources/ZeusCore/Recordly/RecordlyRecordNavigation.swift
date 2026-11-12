import Foundation

/// Which screen the Record section shows, and what a click on a source tile does.
/// Pure rules: the page owns one value and applies the effect it returns. See docs/RECORD-LAYOUT.md.
public struct RecordlyRecordNavigation: Equatable, Sendable {
    public enum Screen: Equatable, Sendable {
        case grid
        case detail(RecordlySourceSelection.SelectionIntent)
    }

    /// What the page should do with the controller after a click.
    public enum ClickEffect: Equatable, Sendable {
        case none
        case select
        case selectAndOpen
        case open
    }

    public private(set) var screen: Screen = .grid
    /// Bumps on every open. The detail view takes it as its identity, so each open starts at the top.
    public private(set) var openCount = 0

    public init() {}

    public var isDetail: Bool {
        if case .detail = screen { return true }
        return false
    }

    public var detailSource: RecordlySourceSelection.SelectionIntent? {
        if case .detail(let intent) = screen { return intent }
        return nil
    }

    /// One click selects at once. A double click (count 2 or more) selects and opens the detail screen.
    /// While capturing nothing can be selected, so only the source already selected opens.
    @discardableResult
    public mutating func click(
        _ intent: RecordlySourceSelection.SelectionIntent, count: Int, canChoose: Bool, isSelected: Bool
    ) -> ClickEffect {
        guard count >= 1, intent.kind != .region else { return .none }
        if count == 1 { return canChoose ? .select : .none }
        guard canChoose || isSelected else { return .none }
        open(intent)
        return canChoose ? .selectAndOpen : .open
    }

    public mutating func open(_ intent: RecordlySourceSelection.SelectionIntent) {
        screen = .detail(intent)
        openCount &+= 1
    }

    public mutating func back() {
        screen = .grid
    }

    /// Returns to the grid when a saved clip opens the editor, or when the detail's source is gone while idle.
    /// A capture in progress keeps the detail screen open.
    public mutating func reconcile(sourceAvailable: Bool, capturing: Bool, editor: Bool) {
        guard isDetail else { return }
        if editor || (!capturing && !sourceAvailable) { screen = .grid }
    }
}

/// Window tiles are paged, never scrolled: how many fit the stage, and which page shows which tiles.
public struct RecordlySourceGridPaging: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }

    /// As many tiles of at least `minTileWidth` x `tileHeight` as fit, `spacing` apart; never fewer than one.
    public init(width: Double, height: Double, minTileWidth: Double, tileHeight: Double, spacing: Double) {
        func fit(_ room: Double, _ item: Double) -> Int {
            guard room.isFinite, item > 0 else { return 1 }
            return Int(((room + spacing) / (item + spacing)).rounded(.down))
        }
        self.init(columns: fit(width, minTileWidth), rows: fit(height, tileHeight))
    }

    public var pageSize: Int { columns * rows }

    public func pageCount(items: Int) -> Int {
        max(1, (max(0, items) + pageSize - 1) / pageSize)
    }

    public func clamp(_ page: Int, items: Int) -> Int {
        min(max(0, page), pageCount(items: items) - 1)
    }

    /// Indices of the tiles on `page`, after clamping it.
    public func range(page: Int, items: Int) -> Range<Int> {
        let count = max(0, items)
        let start = clamp(page, items: count) * pageSize
        return min(start, count)..<min(start + pageSize, count)
    }

    /// The page that holds the tile at `index`.
    public func page(of index: Int) -> Int {
        max(0, index) / pageSize
    }
}

/// Fixed sizes of the Record section, chosen so the grid and the detail screen fit the top bar page
/// (`RecordlyPageLayout.innerHeight`) with no scroll view.
public enum RecordlyRecordLayout {
    public static let headerHeight: CGFloat = 30
    public static let sectionGap: CGFloat = 8
    public static let sideColumnWidth: CGFloat = 264
    public static let detailPreviewWidth: CGFloat = 320
    public static let optionsHeight: CGFloat = 58
    public static let noticeHeight: CGFloat = 28
    public static let controlHeight: CGFloat = 58
    /// The live capsule that replaces options and notices while capturing.
    public static let liveCapsuleHeight: CGFloat = 100
    public static let stagePadding: CGFloat = 10
    public static let windowTileMinWidth: CGFloat = 150
    public static let windowTileHeight: CGFloat = 36
    public static let gridSpacing: CGFloat = 6
    public static let pagerHeight: CGFloat = 18

    /// Header, one gap, then the side column: options, notices and the control with a gap between each.
    public static var idleColumnHeight: CGFloat { optionsHeight + noticeHeight + controlHeight + 2 * sectionGap }
    public static var capturingColumnHeight: CGFloat { liveCapsuleHeight + controlHeight + sectionGap }
    public static var contentHeight: CGFloat {
        headerHeight + sectionGap + max(idleColumnHeight, capturingColumnHeight)
    }

    /// Below this the page keeps this height inside a scroll view (the top bar itself never gets there).
    public static var minimumHeight: CGFloat { contentHeight }

    /// The stage's inner room for window tiles at the standard page size, with the pager row taken out.
    public static var standardTileRoomHeight: CGFloat {
        RecordlyPageLayout.innerHeight - headerHeight - sectionGap - 2 * stagePadding - pagerHeight - gridSpacing
    }
}
