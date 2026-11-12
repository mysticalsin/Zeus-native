import Foundation

/// Pure chart scales. Drawing code receives a finished `ChartPlan` and never does arithmetic on
/// raw model numbers, so a non-finite or degenerate value can only ever produce a refusal, not a
/// NaN pixel. Every mark in a plan is an observed value: nothing is interpolated or smoothed.
public enum ExplanationChartMath {
    public struct TickSet: Equatable, Sendable {
        public let values: [Double]
        public let step: Double
        public let fractionDigits: Int
        public var lower: Double { values[0] }
        public var upper: Double { values[values.count - 1] }
    }

    public struct Tick: Equatable, Sendable {
        public let value: Double
        /// 0 at the plotted lower bound, 1 at the upper bound.
        public let normalized: Double
        public let label: String
    }

    public struct Mark: Equatable, Sendable {
        public let index: Int
        public let label: String
        public let value: Double
        /// Bars: the value on the value axis. Timeline: the position along the time axis.
        public let normalized: Double
    }

    public struct ChartPlan: Equatable, Sendable {
        public enum Layout: Equatable, Sendable { case bars, timeline }
        public let layout: Layout
        /// The plotted domain, aligned to the first and last tick.
        public let lower: Double
        public let upper: Double
        public let ticks: [Tick]
        public let marks: [Mark]
        /// Bars only: where zero sits, when it lies inside the plotted domain.
        public let zeroNormalized: Double?
        public let unitsCaption: String?
        public let source: ExplanationDataSource
        public let sourceNote: String
        /// A bar axis that does not start at zero, by the model's explicit request.
        public let isTruncated: Bool
        /// Short plain-language notes the chart must show (truncation, spacing, flat data).
        public let notes: [String]
        public var tickLabelCharacters: Int { ticks.map { $0.label.count }.max() ?? 0 }
    }

    public enum PlanResult: Equatable, Sendable {
        case plan(ChartPlan)
        case rejected(String)
    }

    // MARK: Nice numbers and ticks

    /// Heckbert's "nice number": 1, 2, 5 or 10 times a power of ten.
    public static func niceNumber(_ x: Double, round: Bool) -> Double {
        guard x.isFinite, x > 0 else { return 1 }
        var exponent = floor(log10(x))
        var fraction = x / pow(10, exponent)
        // log10 can land one ulp across a power of ten.
        if fraction >= 10 { fraction /= 10; exponent += 1 } else if fraction < 1 { fraction *= 10; exponent -= 1 }
        let nice: Double
        if round { nice = fraction < 1.5 ? 1 : fraction < 3 ? 2 : fraction < 7 ? 5 : 10 }
        else { nice = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 5 ? 5 : 10 }
        return nice * pow(10, exponent)
    }

    /// Ticks that cover `low...high` on nice values. nil unless both ends are finite and low < high,
    /// or when the span cannot be scaled without overflow.
    public static func niceTicks(low: Double, high: Double, hint: Int = 5) -> TickSet? {
        guard low.isFinite, high.isFinite, low < high else { return nil }
        let span = high - low
        guard span.isFinite else { return nil }
        let count = min(max(hint, 2), 12)
        let step = niceNumber(niceNumber(span, round: false) / Double(count - 1), round: true)
        guard step.isFinite, step > 0 else { return nil }
        let first = floor(low / step), last = ceil(high / step)
        guard first.isFinite, last.isFinite, last > first, last - first <= 50 else { return nil }
        let digits = fractionDigits(step: step)
        let factor = pow(10, Double(digits))
        var values: [Double] = []
        var index = first
        while index <= last {
            let raw = index * step
            let cleaned = digits <= 15 ? (raw * factor).rounded() / factor : raw
            values.append(cleaned == 0 ? 0 : cleaned)
            index += 1
        }
        guard values.allSatisfy(\.isFinite) else { return nil }
        return TickSet(values: values, step: step, fractionDigits: digits)
    }

    static func fractionDigits(step: Double) -> Int {
        guard step.isFinite, step > 0 else { return 0 }
        return max(0, -Int(floor(log10(step) + 1e-9)))
    }

    /// Tick labels with one shared magnitude suffix, so "2M" and "4M" never mix with "500000".
    public static func tickLabels(for ticks: TickSet) -> [String] {
        let big = max(abs(ticks.lower), abs(ticks.upper))
        if big >= 1e15 { return ticks.values.map { $0 == 0 ? "0" : String(format: "%.2e", $0) } }
        let (divisor, suffix): (Double, String) = big >= 1e12 ? (1e12, "T") : big >= 1e9 ? (1e9, "B")
            : big >= 1e6 ? (1e6, "M") : (1, "")
        let digits = fractionDigits(step: ticks.step / divisor)
        return ticks.values.map { $0 == 0 ? "0" : String(format: "%.\(digits)f", $0 / divisor) + suffix }
    }

    /// Indices of ticks to draw so labels at least `minSpacing` apart fit in `available`.
    public static func thinned(count: Int, available: Double, minSpacing: Double) -> [Int] {
        guard count > 0 else { return [] }
        guard available.isFinite, minSpacing > 0, available > 0 else { return [0] }
        let stride = max(1, Int(ceil(Double(count) * minSpacing / available)))
        return Array(Swift.stride(from: 0, to: count, by: stride))
    }

    // MARK: Pixel mapping

    /// y = plotBottom - normalized * plotHeight. Top-left, y-down pixels. Input is clamped to 0...1.
    public static func y(normalized: Double, plotBottom: Double, plotHeight: Double) -> Double {
        plotBottom - min(max(normalized.isFinite ? normalized : 0, 0), 1) * plotHeight
    }

    public static func x(normalized: Double, plotLeft: Double, plotWidth: Double) -> Double {
        plotLeft + min(max(normalized.isFinite ? normalized : 0, 0), 1) * plotWidth
    }

    // MARK: Plan

    public static func plan(kind: ExplanationGeometry.Kind, values: [Double], labels: [String],
                            axis: ExplanationChartAxis?) -> PlanResult {
        guard kind == .chart || kind == .timeline else { return .rejected("Not a chart") }
        guard !values.isEmpty, values.count == labels.count else { return .rejected("Values and labels do not match") }
        guard values.allSatisfy(\.isFinite) else { return .rejected("A value is not a finite number") }
        let source = axis?.source ?? .example
        let note = sourceNote(source, asOf: axis?.asOf)
        let hint = axis?.tickHint ?? 5
        if let domain = axis?.domain {
            guard domain.lower.isFinite, domain.upper.isFinite, domain.lower < domain.upper else {
                return .rejected("The axis domain is not valid")
            }
            guard values.allSatisfy({ $0 >= domain.lower && $0 <= domain.upper }) else {
                return .rejected("The axis domain does not contain every value")
            }
        }
        let units = axis?.units.flatMap { $0.isEmpty ? nil : $0 }
        return kind == .chart
            ? barPlan(values: values, labels: labels, axis: axis, hint: hint, units: units, source: source, note: note)
            : timelinePlan(values: values, labels: labels, axis: axis, hint: hint, units: units, source: source, note: note)
    }

    private static func barPlan(values: [Double], labels: [String], axis: ExplanationChartAxis?, hint: Int,
                                units: String?, source: ExplanationDataSource, note: String) -> PlanResult {
        let includeZero = axis?.includeZero ?? true
        var low = axis?.domain?.lower ?? (values.min() ?? 0)
        var high = axis?.domain?.upper ?? (values.max() ?? 0)
        if includeZero { low = Swift.min(low, 0); high = Swift.max(high, 0) }
        var notes: [String] = []
        if low == high {
            // All equal and zero is not forced in: pad symmetrically so the span is never zero.
            if low == 0 { high = 1; notes.append("All values are zero") }
            else { let pad = Swift.max(abs(low) * 0.1, Double.leastNormalMagnitude); low -= pad; high += pad }
        }
        guard let ticks = niceTicks(low: low, high: high, hint: hint) else { return .rejected("The values cannot be scaled") }
        let truncated = !includeZero && (ticks.lower > 0 || ticks.upper < 0)
        let tickText = tickLabels(for: ticks)
        if truncated { notes.append("Axis starts at \(tickText[0]), not zero") }
        let span = ticks.upper - ticks.lower
        func normalized(_ value: Double) -> Double { Swift.min(Swift.max((value - ticks.lower) / span, 0), 1) }
        let marks = values.indices.map { Mark(index: $0, label: labels[$0], value: values[$0], normalized: normalized(values[$0])) }
        let plotted = ticks.values.indices.map { Tick(value: ticks.values[$0], normalized: normalized(ticks.values[$0]), label: tickText[$0]) }
        guard marks.allSatisfy({ $0.normalized.isFinite }), plotted.allSatisfy({ $0.normalized.isFinite }) else {
            return .rejected("The values cannot be scaled")
        }
        return .plan(ChartPlan(layout: .bars, lower: ticks.lower, upper: ticks.upper, ticks: plotted, marks: marks,
                               zeroNormalized: ticks.lower <= 0 && ticks.upper >= 0 ? normalized(0) : nil,
                               unitsCaption: units, source: source, sourceNote: note, isTruncated: truncated, notes: notes))
    }

    private static func timelinePlan(values: [Double], labels: [String], axis: ExplanationChartAxis?, hint: Int,
                                     units: String?, source: ExplanationDataSource, note: String) -> PlanResult {
        let categorical = axis?.scale == .categorical
        let count = Double(values.count)
        if categorical {
            let marks = values.indices.map { Mark(index: $0, label: labels[$0], value: values[$0], normalized: (Double($0) + 0.5) / count) }
            return .plan(ChartPlan(layout: .timeline, lower: 0, upper: 1, ticks: [], marks: marks, zeroNormalized: nil,
                                   unitsCaption: nil, source: source, sourceNote: note, isTruncated: false,
                                   notes: ["Evenly spaced, not to time scale"]))
        }
        let low = axis?.domain?.lower ?? (values.min() ?? 0), high = axis?.domain?.upper ?? (values.max() ?? 0)
        if low == high {
            // One shared instant: a single centred tick, never a zero-width scale.
            let label = [low == 0 ? "0" : String(format: "%g", low)]
            let marks = values.indices.map { Mark(index: $0, label: labels[$0], value: values[$0], normalized: 0.5) }
            return .plan(ChartPlan(layout: .timeline, lower: low, upper: high,
                                   ticks: [Tick(value: low, normalized: 0.5, label: label[0])], marks: marks,
                                   zeroNormalized: nil, unitsCaption: units, source: source, sourceNote: note,
                                   isTruncated: false, notes: ["All points share one time"]))
        }
        guard let ticks = niceTicks(low: low, high: high, hint: hint) else { return .rejected("The times cannot be scaled") }
        let tickText = tickLabels(for: ticks)
        let span = ticks.upper - ticks.lower
        func normalized(_ value: Double) -> Double { Swift.min(Swift.max((value - ticks.lower) / span, 0), 1) }
        let marks = values.indices.map { Mark(index: $0, label: labels[$0], value: values[$0], normalized: normalized(values[$0])) }
        let plotted = ticks.values.indices.map { Tick(value: ticks.values[$0], normalized: normalized(ticks.values[$0]), label: tickText[$0]) }
        guard marks.allSatisfy({ $0.normalized.isFinite }) else { return .rejected("The times cannot be scaled") }
        return .plan(ChartPlan(layout: .timeline, lower: ticks.lower, upper: ticks.upper, ticks: plotted, marks: marks,
                               zeroNormalized: nil, unitsCaption: units, source: source, sourceNote: note,
                               isTruncated: false, notes: []))
    }

    public static func sourceNote(_ source: ExplanationDataSource, asOf: String?) -> String {
        switch source {
        case .userProvided: "From your data"
        case .onScreen: "From the screen"
        case .live: "Live data as of \(asOf ?? "an unknown time")"
        case .example: "Example data, not measured"
        }
    }

    /// ISO 8601 date-time with an offset, with or without fractional seconds.
    public static func isISO8601(_ text: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if formatter.date(from: text) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) != nil
    }
}
