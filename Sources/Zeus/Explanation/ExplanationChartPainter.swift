import AppKit
import SwiftUI
import ZeusCore

/// Draws a finished `ExplanationChartMath.ChartPlan` into an object's local rectangle. Every number
/// that reaches a pixel was produced by the pure scale in ZeusCore; this file only places text and
/// strokes. Marks are the observed values only: nothing is smoothed or interpolated.
@MainActor
enum ExplanationChartPainter {
    typealias Plan = ExplanationChartMath.ChartPlan
    private static let labelFont = Font.system(size: 11)
    private static let noteFont = Font.system(size: 10)

    /// The rectangles a plan is drawn into, derived once so drawing stays small.
    struct Frame {
        let plot: CGRect
        let header: CGRect
        let footer: CGRect
        let gutter: CGFloat

        init?(plan: Plan, local: CGRect) {
            let noteLines = plan.notes.isEmpty ? 1 : 2
            let footerHeight = CGFloat(noteLines) * 13
            let headerHeight: CGFloat = plan.unitsCaption == nil ? 0 : 15
            let gutter: CGFloat = plan.layout == .bars ? CGFloat(plan.tickLabelCharacters) * 6.4 + 12 : 0
            let labelRow: CGFloat = plan.layout == .bars ? 20 : 0
            let box = local.insetBy(dx: 8, dy: 6)
            let plot = CGRect(x: box.minX + gutter, y: box.minY + headerHeight,
                              width: box.width - gutter, height: box.height - headerHeight - footerHeight - labelRow - 4)
            guard plot.width >= 40, plot.height >= 36, plot.width.isFinite, plot.height.isFinite else { return nil }
            self.plot = plot; self.gutter = gutter
            header = CGRect(x: box.minX, y: box.minY, width: box.width, height: headerHeight)
            footer = CGRect(x: box.minX, y: box.maxY - footerHeight, width: box.width, height: footerHeight)
        }
    }

    static func draw(_ plan: Plan, in local: CGRect, color: Color, context: inout GraphicsContext) {
        guard let frame = Frame(plan: plan, local: local) else {
            drawRefusal("Too small to chart", in: local, context: &context)
            return
        }
        drawNotes(plan, frame: frame, context: &context)
        if plan.layout == .bars { drawBars(plan, frame: frame, color: color, context: &context) }
        else { drawTimeline(plan, frame: frame, color: color, context: &context) }
    }

    /// A rejected plan is stated, never drawn.
    static func drawRefusal(_ reason: String, in local: CGRect, context: inout GraphicsContext) {
        context.stroke(Path(roundedRect: local.insetBy(dx: 2, dy: 2), cornerRadius: 6),
                       with: .color(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        context.draw(Text("Chart not shown: \(reason)").font(labelFont).foregroundStyle(.secondary),
                     in: local.insetBy(dx: 10, dy: 8))
    }

    private static func drawNotes(_ plan: Plan, frame: Frame, context: inout GraphicsContext) {
        if let units = plan.unitsCaption {
            context.draw(Text(units).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary),
                         at: CGPoint(x: frame.header.minX, y: frame.header.minY), anchor: .topLeading)
        }
        context.draw(Text(plan.sourceNote).font(noteFont).foregroundStyle(.secondary),
                     at: CGPoint(x: frame.footer.minX, y: frame.footer.minY), anchor: .topLeading)
        if !plan.notes.isEmpty {
            context.draw(Text(plan.notes.joined(separator: " · ")).font(noteFont).foregroundStyle(.secondary),
                         at: CGPoint(x: frame.footer.minX, y: frame.footer.minY + 13), anchor: .topLeading)
        }
    }

    private static func drawBars(_ plan: Plan, frame: Frame, color: Color, context: inout GraphicsContext) {
        let plot = frame.plot
        let bottom = Double(plot.maxY), height = Double(plot.height)
        func y(_ normalized: Double) -> CGFloat { CGFloat(ExplanationChartMath.y(normalized: normalized, plotBottom: bottom, plotHeight: height)) }
        let shown = ExplanationChartMath.thinned(count: plan.ticks.count, available: height, minSpacing: 18)
        for index in shown {
            let tick = plan.ticks[index], line = y(tick.normalized)
            context.stroke(ExplanationCanvasLayout.polyline([.init(x: plot.minX, y: line), .init(x: plot.maxX, y: line)]),
                           with: .color(.secondary.opacity(0.18)), lineWidth: 1)
            context.draw(Text(tick.label).font(labelFont).foregroundStyle(.secondary),
                         at: CGPoint(x: plot.minX - 6, y: line), anchor: .trailing)
        }
        let baseline = plan.zeroNormalized.map(y) ?? plot.maxY
        context.stroke(ExplanationCanvasLayout.polyline([.init(x: plot.minX, y: baseline), .init(x: plot.maxX, y: baseline)]),
                       with: .color(.secondary.opacity(0.6)), lineWidth: 1.2)
        let band = plot.width / CGFloat(plan.marks.count)
        for mark in plan.marks {
            let top = y(mark.normalized), centre = plot.minX + (CGFloat(mark.index) + 0.5) * band
            let bar = CGRect(x: centre - max(1, band * 0.36), y: min(top, baseline),
                             width: max(2, band * 0.72), height: max(1, abs(top - baseline)))
            context.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(color.opacity(0.8)))
        }
        for index in ExplanationChartMath.thinned(count: plan.marks.count, available: Double(plot.width), minSpacing: 30) {
            let centre = plot.minX + (CGFloat(index) + 0.5) * band
            context.draw(Text(plan.marks[index].label).font(labelFont).foregroundStyle(.secondary),
                         in: CGRect(x: centre - band / 2, y: plot.maxY + 4, width: band, height: 18))
        }
    }

    private static func drawTimeline(_ plan: Plan, frame: Frame, color: Color, context: inout GraphicsContext) {
        let plot = frame.plot
        let axisY = plot.midY, left = Double(plot.minX), width = Double(plot.width)
        func x(_ normalized: Double) -> CGFloat { CGFloat(ExplanationChartMath.x(normalized: normalized, plotLeft: left, plotWidth: width)) }
        context.stroke(ExplanationCanvasLayout.polyline([.init(x: plot.minX, y: axisY), .init(x: plot.maxX, y: axisY)]),
                       with: .color(color), lineWidth: 2)
        for index in ExplanationChartMath.thinned(count: plan.ticks.count, available: width, minSpacing: 52) {
            let tick = plan.ticks[index], at = x(tick.normalized)
            context.stroke(ExplanationCanvasLayout.polyline([.init(x: at, y: axisY), .init(x: at, y: axisY + 5)]),
                           with: .color(.secondary), lineWidth: 1)
            context.draw(Text(tick.label).font(labelFont).foregroundStyle(.secondary),
                         at: CGPoint(x: at, y: axisY + 7), anchor: .top)
        }
        let rowSpacing = plot.width / CGFloat(plan.marks.count) * 2
        for mark in plan.marks {
            let at = x(mark.normalized)
            context.fill(Path(ellipseIn: .init(x: at - 4, y: axisY - 4, width: 8, height: 8)), with: .color(color))
            guard rowSpacing >= 60 else { continue }
            let above = mark.index.isMultiple(of: 2)
            let clamped = max(plot.minX + 35, min(at, plot.maxX - 35))
            context.draw(Text(mark.label).font(labelFont).foregroundStyle(.primary),
                         at: CGPoint(x: clamped, y: above ? axisY - 10 : axisY + 24), anchor: above ? .bottom : .top)
        }
    }
}
