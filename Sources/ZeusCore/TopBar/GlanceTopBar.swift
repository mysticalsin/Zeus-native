import CoreGraphics
import Foundation

/// The Glance top bar, measured live (teardown/glance-live/TOPBAR-SPEC.md), in points.
public enum GlanceTopBar {
    // Window: full screen width, 470 tall, flush with the top, at the status-bar layer (25).
    public static let windowHeight: CGFloat = 470
    public static let windowLayer = 25

    // Closed
    public static let closedSize = CGSize(width: 185, height: 32)
    public static let closedBottomRadius: CGFloat = 6

    // Open body
    public static let bodyWidth: CGFloat = 870
    public static let ear: CGFloat = 27.5
    public static let earHeight: CGFloat = 30
    public static let bottomRadius: CGFloat = 22

    // Tab row, measured on the live pair (parity/N4): capsule x 453.5 to 864.5, y 38 to 72 (centre 55;
    // TOPBAR-SPEC's "top 41" was 3 pt low). The pill sits 5.5 in from the capsule's ends and 3 from its
    // top and bottom. Unselected tabs are a 13 pt icon with 11 either side (35), 14 apart, so plain
    // icons are 49 apart; a count widens its tab (Clipboard "39" +15.5, Shelf "7" +9).
    public static let tabRowTop: CGFloat = 38
    public static let tabRowHeight: CGFloat = 34
    public static let tabRowInset: CGFloat = 24
    public static let selectedPill = CGSize(width: 82, height: 28)
    public static let capsuleInset = CGSize(width: 5.5, height: 3)
    public static let tabIcon: CGFloat = 13
    public static let tabPadding: CGFloat = 11
    /// 12 pt (was 14) so a thirteenth tab, Agents, fits with the widest selected label and three counts.
    public static let tabSpacing: CGFloat = 12
    public static var plainTabSlot: CGFloat { tabIcon + 2 * tabPadding + tabSpacing }
    public static let moreSize: CGFloat = 30
    /// Thirteen tabs: the default row with Agents after Home. At 12 pt spacing the widest selected label
    /// ("Clipboard") with three 3-digit counts is 801.75 pt of the 803 pt `rowRoom`.
    public static let maxTabs = 13
    /// Space after the "more" circle, to the body's right edge.
    public static let rowTrailing: CGFloat = 13
    /// Width the capsule may take: the body less its left inset, the more circle and the right inset.
    public static var rowRoom: CGFloat { bodyWidth - tabRowInset - rowTrailing - moreSize }
    /// Glance's 12.5 pt tab label, per character (its "Home" is 35 pt): a safe over-estimate.
    public static let labelCharWidth: CGFloat = 8.75

    /// The selected pill: 12 pt padding, icon, 7 pt gap and label, never under Glance's 82 pt.
    public static func selectedPillWidth(title: String, countWidth: CGFloat = 0) -> CGFloat {
        max(selectedPill.width, 24 + tabIcon + 7 + CGFloat(title.count) * labelCharWidth + countWidth)
    }

    // Cards
    public static let cardTop: CGFloat = 82
    public static let cardHeight: CGFloat = 114
    public static let cardGap: CGFloat = 10.5
    public static let cardInset: CGFloat = 18
    public static let cardRadius: CGFloat = 22
    public static let bottomGap: CGFloat = 14
    /// Pages other than Home get more room under the tab row.
    public static let tallPageHeight: CGFloat = 236

    // Motion. Open: fitted to Glance's 60 fps hover-open (parity/N7-glance.mp4, width along y 37),
    // rms 14 pt; it overshoots under 3 pt, as Glance does (871 to 873 on the 870 body). Close: not yet
    // recorded on Glance; a firm 0.40 s with no overshoot. The bloom rim is 9 pt and gone by 0.4 s.
    public static let openSpring = (response: 0.30, damping: 0.87)
    /// Close: Glance shrinks into the notch over about 6 frames (parity/N8-glance.mp4, height at x 1000:
    /// 231, 184, 157, 114, 101, 90, 72, 65, then a thin strip fades), about 0.54 s after the pointer leaves.
    public static let closeDuration = 0.1
    public static let closeDelay = 0.5
    /// The open height leads the width: Glance's body is about 163 pt tall in the first frame the width
    /// is 311 (parity/N7, height_track.py), full by about 130 ms; fitted rms 15.6 pt (shadow in the trace).
    public static let openHeightSpring = (response: 0.105, damping: 1.0)

    /// Glance's measured open: ms after the body first reaches y 37, width there in pt.
    public static let measuredOpen: [(ms: Double, width: Double)] = [
        (0, 311), (17, 408), (33, 447), (50, 588), (67, 660), (83, 717), (100, 762.5),
        (150, 840), (167, 842.5), (217, 866.5), (233, 869), (267, 870),
    ]
    /// When Glance's body first reaches y 37 after the open starts (fitted with the spring).
    public static let measuredOpenOffset = 0.034
    public static let bloomDuration = 0.4
    public static let bloomRim: CGFloat = 9

    /// What is left of a SwiftUI spring(response:dampingFraction:) moving 0 to 1, at time t: 1 at the
    /// start, 0 once settled, negative past the target (overshoot).
    public static func springRemaining(at t: Double, response: Double, damping: Double) -> Double {
        let omega = 2 * Double.pi / response
        if damping >= 1 {
            return (1 + omega * t) * exp(-omega * t)
        }
        let damped = omega * (1 - damping * damping).squareRoot()
        return exp(-damping * omega * t) * (cos(damped * t) + damping * omega / damped * sin(damped * t))
    }

    /// When a move of `distance` pt last changes by a visible amount (half a point, one pixel at 2x).
    public static func settleTime(response: Double, damping: Double, distance: Double, tolerance: Double = 0.5) -> Double {
        var last = 0.0
        for frame in 0...600 {
            let t = Double(frame) / 600
            if abs(springRemaining(at: t, response: response, damping: damping)) * distance >= tolerance { last = t }
        }
        return last
    }

    /// The width a hover open travels: the 185 pt notch to the 925 pt outline with ears.
    public static var openDistance: Double { Double(bodyWidth + 2 * ear - closedSize.width) }

    /// The notch window on a screen: full width, 470 tall, top flush. AppKit coordinates.
    public static func windowFrame(screen: CGRect) -> CGRect {
        CGRect(x: screen.minX, y: screen.maxY - windowHeight, width: screen.width, height: windowHeight)
    }

    /// Home's height is exactly 210; other pages are taller.
    public static func pageHeight(home: Bool) -> CGFloat { home ? cardHeight : tallPageHeight }

    /// Everything from the top of the screen to the bottom of the panel.
    public static func bodyHeight(home: Bool, extra: CGFloat = 0) -> CGFloat {
        cardTop + pageHeight(home: home) + bottomGap + extra
    }

    /// The outer size including the concave ears at the top.
    public static func panelSize(home: Bool, extra: CGFloat = 0) -> CGSize {
        CGSize(width: bodyWidth + 2 * ear, height: bodyHeight(home: home, extra: extra))
    }

    /// Four equal Home cards across the body, as x offsets and a width.
    public static func cardFrames() -> [CGRect] {
        let width = (bodyWidth - 2 * cardInset - 3 * cardGap) / 4
        return (0..<4).map { index in
            CGRect(x: cardInset + CGFloat(index) * (width + cardGap), y: cardTop, width: width, height: cardHeight)
        }
    }

    /// The tab capsule's width: the pill, plain icon slots, and whatever the counts add.
    public static func capsuleWidth(tabs: Int, countsExtra: CGFloat = 0) -> CGFloat {
        guard tabs > 0 else { return 0 }
        return 2 * capsuleInset.width + selectedPill.width + CGFloat(tabs - 1) * plainTabSlot + countsExtra
    }

    /// Opens on the hardware notch itself, nothing beside or below it. Probed live on Glance with a
    /// 1.5 s dwell (glance-clone-proof/PROGRESS.md, N3): opens at x 772 and 956, not 768 or 960 (notch
    /// 771.5 to 956.5); opens at y 30 from the top, not 31. AppKit coordinates (origin bottom-left).
    public static func hoverZone(screen: CGRect, notch: CGSize) -> CGRect {
        let width = max(notch.width, 160)
        let height = max(notch.height, 30) - 1
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
    }

    /// Whether a point is on the open notch's drawn shape (the same outline NotchShape draws): the body,
    /// the concave ears in the top `earHeight`, and the rounded bottom corners. `size` includes the ears.
    /// The full-width window only takes the mouse there; clicks anywhere else reach the app below.
    /// AppKit coordinates (origin bottom-left).
    public static func openShapeContains(_ point: CGPoint, screen: CGRect, size: CGSize,
                                         ear: CGFloat = ear, earHeight: CGFloat = earHeight, radius: CGFloat = bottomRadius) -> Bool {
        let fromTop = screen.maxY - point.y
        let dx = abs(point.x - screen.midX)
        let half = size.width / 2 - ear
        guard fromTop >= 0, fromTop <= size.height else { return false }
        if fromTop < earHeight {
            // Same quadratic as the ear curve: ear * (1 - sqrt(y / h))^2 beyond the body.
            let reach = ear * pow(1 - (fromTop / earHeight).squareRoot(), 2)
            return dx <= half + reach
        }
        guard dx <= half else { return false }
        let cornerTop = size.height - radius
        guard fromTop > cornerTop, dx > half - radius else { return true }
        let cx = half - radius, cy = cornerTop
        return pow(dx - cx, 2) + pow(fromTop - cy, 2) <= radius * radius
    }

    /// Whether the pointer is in the hover zone. The top edge counts (the pointer can rest on the
    /// screen's top row) and the bottom edge does not, so this is not CGRect.contains.
    public static func inHoverZone(_ mouse: CGPoint, screen: CGRect, notch: CGSize) -> Bool {
        let zone = hoverZone(screen: screen, notch: notch)
        return abs(mouse.x - zone.midX) <= zone.width / 2 && mouse.y > zone.minY && mouse.y <= zone.maxY
    }
}

/// Height budget of the Recordly idle page inside the fixed 236 pt tall page. The action footer is pinned inside the
/// frame, so the Record button is always within the open shape's hit area; everything above it scrolls.
public enum RecordlyPageLayout {
    /// The Tile's inset on every side (TopBarViews Tile, GlassTheme).
    public static let tilePadding: CGFloat = 14
    public static let footerHeight: CGFloat = 36
    public static let footerGap: CGFloat = 10
    /// Rows and the fixed header above the source list, for estimating content height.
    public static let headerHeight: CGFloat = 84
    public static let displayRowHeight: CGFloat = 16
    public static let windowRowHeight: CGFloat = 28
    public static let rowSpacing: CGFloat = 4

    /// Room inside the Tile.
    public static var innerHeight: CGFloat { GlanceTopBar.tallPageHeight - 2 * tilePadding }
    /// The most the scrolling body may take; the footer and its gap come out of the inner height.
    public static var scrollMaxHeight: CGFloat { innerHeight - footerHeight - footerGap }

    /// The scroll area is the stack's first child and the footer its second, with exactly one gap between them (no
    /// Spacer), so the scroll area keeps `scrollMaxHeight` and shows at least this many display rows below the header.
    public static let minVisibleDisplayRows = 4

    /// Height of the source rows that stay visible under the fixed header when the scroll area is at its maximum.
    public static var visibleRowsHeight: CGFloat { scrollMaxHeight - headerHeight }

    /// The whole stack's height for a scrolling body that would like `contentHeight`.
    public static func stackHeight(contentHeight: CGFloat) -> CGFloat {
        min(max(contentHeight, 0), scrollMaxHeight) + footerGap + footerHeight
    }

    public static func estimatedContentHeight(rows: Int, rowHeight: CGFloat) -> CGFloat {
        let count = CGFloat(max(rows, 0))
        return headerHeight + count * rowHeight + max(count - 1, 0) * rowSpacing
    }
}

/// The tabs in the Glance row: at most ten, in the person's order, keeping the selected
/// one visible (it takes the last slot when it would otherwise fall off).
public enum GlanceTabRow {
    public static func visible<Tab: Equatable>(_ tabs: [Tab], selected: Tab, max: Int = GlanceTopBar.maxTabs) -> [Tab] {
        guard tabs.count > max else { return tabs }
        var row = Array(tabs.prefix(max))
        if !row.contains(selected), tabs.contains(selected) { row[max - 1] = selected }
        return row
    }
}
