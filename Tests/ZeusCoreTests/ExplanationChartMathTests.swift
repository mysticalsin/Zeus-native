import Foundation
import Testing
@testable import ZeusCore

@Suite("Explanation chart scales: ticks, domains, mapping and provenance")
struct ExplanationChartMathTests {
    private typealias Math = ExplanationChartMath

    private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    private func plan(_ result: Math.PlanResult) -> Math.ChartPlan? {
        if case .plan(let value) = result { return value }
        return nil
    }

    private func bars(_ values: [Double], axis: ExplanationChartAxis? = nil) -> Math.PlanResult {
        Math.plan(kind: .chart, values: values, labels: values.indices.map { "L\($0)" }, axis: axis)
    }

    private func timeline(_ values: [Double], axis: ExplanationChartAxis? = nil) -> Math.PlanResult {
        Math.plan(kind: .timeline, values: values, labels: values.indices.map { "E\($0)" }, axis: axis)
    }

    // MARK: nice-number ticks

    @Test func chartTicksCoverZeroToSevenOnNiceSteps() {
        let ticks = Math.niceTicks(low: 0, high: 7)
        #expect(ticks?.values == [0, 2, 4, 6, 8])
        #expect(ticks?.step == 2)
        #expect(ticks.map { Math.tickLabels(for: $0) } == ["0", "2", "4", "6", "8"])
    }

    @Test func chartTicksStartBelowAnOffsetRange() {
        let ticks = Math.niceTicks(low: 3, high: 1003)
        #expect(ticks?.values == [0, 200, 400, 600, 800, 1000, 1200])
    }

    @Test func chartTicksCrossZeroForNegativeToPositiveData() {
        let ticks = Math.niceTicks(low: -5, high: 12)
        #expect(ticks?.values == [-5, 0, 5, 10, 15])
        let negative = Math.niceTicks(low: -1003, high: -3)
        #expect(negative?.values.first == -1200)
        #expect(negative?.values.last == 0)
    }

    @Test func chartTicksHandleFractionsWithoutFloatingPointResidue() {
        let ticks = Math.niceTicks(low: 0, high: 0.7)
        #expect(ticks?.values == [0, 0.2, 0.4, 0.6, 0.8])
        #expect(ticks.map { Math.tickLabels(for: $0) } == ["0", "0.2", "0.4", "0.6", "0.8"])
    }

    @Test func chartTicksHandleHugeMagnitudesWithOneSharedSuffix() {
        let ticks = Math.niceTicks(low: 0, high: 1e12)
        #expect(ticks?.values == [0, 2e11, 4e11, 6e11, 8e11, 1e12])
        #expect(ticks.map { Math.tickLabels(for: $0) } == ["0", "0.2T", "0.4T", "0.6T", "0.8T", "1.0T"])
        let millions = Math.niceTicks(low: 0, high: 2_000_000)
        #expect(millions.map { Math.tickLabels(for: $0) } == ["0", "0.5M", "1.0M", "1.5M", "2.0M"])
    }

    @Test func chartTicksRefuseUnscalableRanges() {
        #expect(Math.niceTicks(low: 5, high: 5) == nil)
        #expect(Math.niceTicks(low: 9, high: 1) == nil)
        #expect(Math.niceTicks(low: .nan, high: 1) == nil)
        #expect(Math.niceTicks(low: 0, high: .infinity) == nil)
        #expect(Math.niceTicks(low: -Double.greatestFiniteMagnitude, high: Double.greatestFiniteMagnitude) == nil)
        #expect(Math.niceTicks(low: 0, high: 1.7e308) == nil)
    }

    @Test func chartTickHintIsClampedAndTickCountStaysBounded() {
        let few = Math.niceTicks(low: 0, high: 100, hint: 2)
        let many = Math.niceTicks(low: 0, high: 100, hint: 12)
        #expect((few?.values.count ?? 99) <= 4)
        #expect((many?.values.count ?? 0) >= 6 && (many?.values.count ?? 99) <= 20)
        #expect(Math.niceTicks(low: 0, high: 100, hint: 1_000)?.values.count ?? 99 <= 20)
    }

    @Test func chartThinningKeepsLabelsApartAndKeepsAllWhenTheyFit() {
        #expect(Math.thinned(count: 10, available: 100, minSpacing: 16) == [0, 2, 4, 6, 8])
        #expect(Math.thinned(count: 3, available: 100, minSpacing: 16) == [0, 1, 2])
        #expect(Math.thinned(count: 0, available: 100, minSpacing: 16).isEmpty)
    }

    // MARK: pixel mapping

    @Test func chartYMappingIsPlotBottomMinusNormalizedTimesHeight() {
        #expect(Math.y(normalized: 0, plotBottom: 300, plotHeight: 200) == 300)
        #expect(Math.y(normalized: 1, plotBottom: 300, plotHeight: 200) == 100)
        #expect(Math.y(normalized: 0.5, plotBottom: 300, plotHeight: 200) == 200)
        #expect(Math.y(normalized: 5, plotBottom: 300, plotHeight: 200) == 100)
        #expect(Math.y(normalized: .nan, plotBottom: 300, plotHeight: 200) == 300)
        #expect(Math.x(normalized: 0.25, plotLeft: 40, plotWidth: 400) == 140)
    }

    // MARK: bars

    @Test func chartBarsIncludeZeroByDefault() throws {
        let result = try #require(plan(bars([3, 1003])))
        #expect(result.lower == 0)
        #expect(result.upper == 1500)
        #expect(result.zeroNormalized == 0)
        #expect(result.isTruncated == false)
        #expect(near(result.marks[0].normalized, 3.0 / 1500))
        #expect(near(result.marks[1].normalized, 1003.0 / 1500))
    }

    @Test func chartBarsKeepNegativeValuesBelowALabelledZeroLine() throws {
        let result = try #require(plan(bars([-5, 12])))
        #expect(result.lower == -5)
        #expect(result.upper == 15)
        let zero = try #require(result.zeroNormalized)
        #expect(near(zero, 0.25))
        #expect(near(result.marks[0].normalized, 0))
        #expect(result.ticks.map(\.label) == ["-5", "0", "5", "10", "15"])
    }

    @Test func chartTruncatedAxisIsAllowedOnlyWhenRequestedAndIsLabelled() throws {
        let spec = ExplanationChartAxis(scale: .linear, includeZero: false, source: .userProvided)
        let truncated = try #require(plan(bars([100, 120], axis: spec)))
        #expect(truncated.isTruncated)
        #expect(truncated.lower == 100)
        #expect(truncated.zeroNormalized == nil)
        #expect(truncated.notes.contains("Axis starts at 100, not zero"))
        let defaulted = try #require(plan(bars([100, 120])))
        #expect(defaulted.lower == 0 && !defaulted.isTruncated && defaulted.notes.isEmpty)
        let spanning = try #require(plan(bars([-5, 12], axis: spec)))
        #expect(!spanning.isTruncated)
    }

    @Test func chartExplicitDomainIsHonouredAndNeverNarrowerThanTheData() throws {
        let spec = ExplanationChartAxis(scale: .linear, domain: .init(lower: 0, upper: 10), units: "ms", source: .userProvided)
        let result = try #require(plan(bars([3, 5], axis: spec)))
        #expect(result.ticks.map(\.value) == [0, 2, 4, 6, 8, 10])
        #expect(result.unitsCaption == "ms")
        let outside = bars([20], axis: spec)
        #expect(outside == .rejected("The axis domain does not contain every value"))
    }

    @Test func chartSingleValueAndAllEqualValuesGetAScale() throws {
        let single = try #require(plan(bars([7])))
        #expect(single.lower == 0 && single.upper == 8)
        #expect(near(single.marks[0].normalized, 7.0 / 8))
        let equal = try #require(plan(bars([7, 7, 7])))
        #expect(equal.marks.allSatisfy { near($0.normalized, 7.0 / 8) })
        let flatSpec = ExplanationChartAxis(scale: .linear, includeZero: false, source: .example)
        let flat = try #require(plan(bars([50, 50], axis: flatSpec)))
        #expect(flat.upper > flat.lower)
        #expect(flat.marks.allSatisfy { $0.normalized > 0 && $0.normalized < 1 })
    }

    @Test func chartAllZeroValuesGetAUnitDomainAndANote() throws {
        let zero = try #require(plan(bars([0, 0])))
        #expect(zero.upper >= 1 && zero.lower == 0)
        #expect(zero.marks.allSatisfy { $0.normalized == 0 })
        #expect(zero.notes.contains("All values are zero"))
    }

    // MARK: never NaN pixels

    @Test func chartNonFiniteValuesAreRejectedNotDrawn() {
        #expect(bars([1, .nan]) == .rejected("A value is not a finite number"))
        #expect(bars([.infinity]) == .rejected("A value is not a finite number"))
        #expect(bars([-.infinity, 1]) == .rejected("A value is not a finite number"))
        #expect(timeline([1, .nan]) == .rejected("A value is not a finite number"))
    }

    @Test func chartMismatchedOrEmptyDataIsRejected() {
        #expect(Math.plan(kind: .chart, values: [1, 2], labels: ["a"], axis: nil) == .rejected("Values and labels do not match"))
        #expect(Math.plan(kind: .chart, values: [], labels: [], axis: nil) == .rejected("Values and labels do not match"))
        #expect(Math.plan(kind: .ring, values: [1], labels: ["a"], axis: nil) == .rejected("Not a chart"))
    }

    @Test func chartEveryAcceptedPlanHasOnlyFiniteBoundedNormalizedPositions() {
        let sets: [[Double]] = [[0], [1], [-1], [0, 0], [1e-9, 2e-9], [-1e6, 1e6], [0, 1e300], [5, 5, 5], [1, 2, 3, 4, 5, 6, 7, 8],
                                [0, 1.7e308], [-1e300, 1e300], [Double.leastNormalMagnitude, 1]]
        for values in sets {
            for result in [bars(values), timeline(values.sorted())] {
                guard case .plan(let value) = result else { continue }
                #expect(value.marks.allSatisfy { $0.normalized.isFinite && (0...1).contains($0.normalized) })
                #expect(value.ticks.allSatisfy { $0.normalized.isFinite && (0...1).contains($0.normalized) && !$0.label.isEmpty })
                #expect(value.lower.isFinite && value.upper.isFinite)
                #expect(value.marks.count == values.count)
            }
        }
    }

    @Test func chartPlanHasOneMarkPerObservedValueAndNothingInterpolated() throws {
        let values: [Double] = [1, 4, 2]
        let result = try #require(plan(timeline(values, axis: .init(scale: .time, source: .userProvided))))
        #expect(result.marks.map(\.value) == values)
        #expect(result.marks.map(\.index) == [0, 1, 2])
    }

    // MARK: categorical versus true time

    @Test func chartTimeAxisSpacesPointsByValueAndCategoricalSpacesThemEvenly() throws {
        let years: [Double] = [2000, 2010, 2030]
        let time = try #require(plan(timeline(years, axis: .init(scale: .time, source: .userProvided))))
        #expect(time.ticks.map(\.value) == [2000, 2010, 2020, 2030])
        #expect(near(time.marks[0].normalized, 0))
        #expect(near(time.marks[1].normalized, 1.0 / 3))
        #expect(near(time.marks[2].normalized, 1))
        let even = try #require(plan(timeline(years, axis: .init(scale: .categorical, source: .userProvided))))
        #expect(even.ticks.isEmpty)
        #expect(near(even.marks[0].normalized, 1.0 / 6) && near(even.marks[1].normalized, 0.5) && near(even.marks[2].normalized, 5.0 / 6))
        #expect(even.notes.contains("Evenly spaced, not to time scale"))
        #expect(time.marks[1].normalized != even.marks[1].normalized)
    }

    @Test func chartTimelineWithoutAnAxisKeepsTheProportionalLegacyBehaviour() throws {
        let legacy = try #require(plan(timeline([0, 1, 4])))
        #expect(near(legacy.marks[1].normalized, 0.25))
        #expect(near(legacy.marks[2].normalized, 1))
    }

    @Test func chartTimelineWithOneSharedInstantHasACentredTickAndNoZeroWidthScale() throws {
        let flat = try #require(plan(timeline([5, 5, 5], axis: .init(scale: .time, source: .userProvided))))
        #expect(flat.ticks.count == 1 && flat.ticks[0].normalized == 0.5 && flat.ticks[0].label == "5")
        #expect(flat.marks.allSatisfy { $0.normalized == 0.5 })
        #expect(flat.notes.contains("All points share one time"))
        let single = try #require(plan(timeline([2026])))
        #expect(single.marks[0].normalized == 0.5)
    }

    // MARK: provenance

    @Test func chartProvenanceDefaultsToExampleAndCarriesEachSourceNote() throws {
        let legacy = try #require(plan(bars([1, 2])))
        #expect(legacy.source == .example)
        #expect(legacy.sourceNote == "Example data, not measured")
        #expect(Math.sourceNote(.userProvided, asOf: nil) == "From your data")
        #expect(Math.sourceNote(.onScreen, asOf: nil) == "From the screen")
        let live = ExplanationChartAxis(scale: .linear, source: .live, asOf: "2026-11-11T10:00:00Z")
        let result = try #require(plan(bars([1, 2], axis: live)))
        #expect(result.source == .live)
        #expect(result.sourceNote == "Live data as of 2026-11-11T10:00:00Z")
    }

    @Test func chartAsOfMustBeAnISODateTime() {
        #expect(Math.isISO8601("2026-11-11T10:00:00Z"))
        #expect(Math.isISO8601("2026-11-11T10:00:00.250Z"))
        #expect(Math.isISO8601("2026-11-11T05:00:00-05:00"))
        #expect(!Math.isISO8601("yesterday"))
        #expect(!Math.isISO8601("2026-11-11"))
        #expect(!Math.isISO8601(""))
    }
}
