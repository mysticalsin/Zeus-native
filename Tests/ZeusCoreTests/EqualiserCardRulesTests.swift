import Foundation
import Testing
@testable import ZeusCore

private func hasNoDash(_ text: String) -> Bool {
    !text.contains("\u{2014}") && !text.contains("\u{2013}")
}

@Suite("Equaliser band control")
struct EqualiserBandControlTests {
    @Test func labelsNameTheTenBands() {
        let labels = (0..<EqualiserParameters.bandCount).map(EqualiserBandControl.label(at:))
        #expect(labels == ["31.5", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"])
    }

    @Test func spokenNamesSayHertzAndKilohertz() {
        #expect(EqualiserBandControl.spokenName(at: 0) == "31.5 hertz band")
        #expect(EqualiserBandControl.spokenName(at: 2) == "125 hertz band")
        #expect(EqualiserBandControl.spokenName(at: 5) == "1 kilohertz band")
        #expect(EqualiserBandControl.spokenName(at: 9) == "16 kilohertz band")
        #expect((0..<EqualiserParameters.bandCount).allSatisfy { hasNoDash(EqualiserBandControl.spokenName(at: $0)) })
    }

    @Test func anIndexOutOfRangeHasNoLabelAndNoName() {
        #expect(EqualiserBandControl.label(at: -1).isEmpty)
        #expect(EqualiserBandControl.label(at: 10).isEmpty)
        #expect(EqualiserBandControl.spokenName(at: 10).isEmpty)
    }

    @Test func snapKeepsHalfDecibelStepsInsideTheRange() {
        #expect(EqualiserBandControl.snapped(0.2) == 0)
        #expect(EqualiserBandControl.snapped(0.3) == 0.5)
        #expect(EqualiserBandControl.snapped(-1.76) == -2)
        #expect(EqualiserBandControl.snapped(40) == 12)
        #expect(EqualiserBandControl.snapped(-40) == -12)
        #expect(EqualiserBandControl.snapped(.nan) == 0)
    }

    @Test func fractionRunsFromTheBottomToTheTop() {
        #expect(EqualiserBandControl.fraction(for: -12) == 0)
        #expect(EqualiserBandControl.fraction(for: 0) == 0.5)
        #expect(EqualiserBandControl.fraction(for: 12) == 1)
        #expect(EqualiserBandControl.fraction(for: 99) == 1)
        #expect(EqualiserBandControl.fraction(for: .nan) == 0.5)
    }

    @Test func aPositionGivesASnappedGainAndBackAgain() {
        #expect(EqualiserBandControl.gain(atFraction: 0) == -12)
        #expect(EqualiserBandControl.gain(atFraction: 0.5) == 0)
        #expect(EqualiserBandControl.gain(atFraction: 1) == 12)
        #expect(EqualiserBandControl.gain(atFraction: 2) == 12)
        #expect(EqualiserBandControl.gain(atFraction: -1) == -12)
        for step in stride(from: -12.0, through: 12.0, by: 0.5) {
            let there = EqualiserBandControl.fraction(for: step)
            #expect(EqualiserBandControl.gain(atFraction: there) == step)
        }
    }

    @Test func adjustingMovesOneStepAndStopsAtTheEnds() {
        #expect(EqualiserBandControl.adjusted(0, steps: 1) == 0.5)
        #expect(EqualiserBandControl.adjusted(0, steps: -2) == -1)
        #expect(EqualiserBandControl.adjusted(11.5, steps: 5) == 12)
        #expect(EqualiserBandControl.adjusted(-11.5, steps: -5) == -12)
    }

    @Test func aGainIsCentredOnlyWhenItSnapsToZero() {
        #expect(EqualiserBandControl.isCentred(0))
        #expect(EqualiserBandControl.isCentred(0.2))
        #expect(EqualiserBandControl.isCentred(-0.2))
        #expect(EqualiserBandControl.isCentred(.nan))
        #expect(!EqualiserBandControl.isCentred(0.5))
        #expect(!EqualiserBandControl.isCentred(-0.5))
        #expect(!EqualiserBandControl.isCentred(12))
        #expect(!EqualiserBandControl.isCentred(-12))
    }

    @Test func ticksMarkMinusTwelveToPlusTwelveInSixes() {
        #expect(EqualiserBandControl.ticks == [-12, -6, 0, 6, 12])
    }
}

@Suite("Equaliser card layout")
struct EqualiserCardLayoutTests {
    @Test func theOpenedRowEndsWhereTheHeaderEnds() {
        #expect(EqualiserCardLayout.panelTrailingInset == 0)
    }

    @Test func theOpenedRowStartsUnderTheAppName() {
        #expect(EqualiserCardLayout.panelLeadingInset == EqualiserCardLayout.iconSize + EqualiserCardLayout.iconGap)
    }
}

@Suite("Equaliser response curve")
struct EqualiserCurveTests {
    @Test func aFlatSettingDrawsAFlatLine() {
        let points = EqualiserCurve.points(gainsDB: [Double](repeating: 0, count: 10))
        #expect(points.count == EqualiserCurve.pointCount)
        #expect(points.allSatisfy { abs($0.decibels) < 0.0001 })
    }

    @Test func pointsAreLogSpacedFromTwentyHertzToTwentyKilohertz() throws {
        let points = EqualiserCurve.points(gainsDB: [])
        let first = try #require(points.first)
        let last = try #require(points.last)
        #expect(abs(first.frequency - 20) < 0.001)
        #expect(abs(last.frequency - 20_000) < 0.01)
        let ratios = zip(points, points.dropFirst()).map { $1.frequency / $0.frequency }
        let mean = ratios.reduce(0, +) / Double(ratios.count)
        #expect(ratios.allSatisfy { abs($0 - mean) < 0.0001 })
    }

    @Test func aBoostedBandPeaksNearItsCentre() throws {
        var gains = [Double](repeating: 0, count: 10)
        gains[5] = 6
        let points = EqualiserCurve.points(gainsDB: gains)
        let top = try #require(points.max { $0.decibels < $1.decibels })
        #expect(top.frequency > 700 && top.frequency < 1400)
        #expect(top.decibels > 4.5 && top.decibels <= 6.01)
    }

    @Test func aCutLowShelfPullsTheBottomDown() throws {
        var gains = [Double](repeating: 0, count: 10)
        gains[0] = -6
        let points = EqualiserCurve.points(gainsDB: gains)
        let first = try #require(points.first)
        let last = try #require(points.last)
        #expect(first.decibels < -4)
        #expect(abs(last.decibels) < 0.5)
    }

    @Test func damagedGainsDrawLikeTheClampedOnes() {
        let wild = EqualiserCurve.points(gainsDB: [99, .nan, -99])
        let tame = EqualiserCurve.points(gainsDB: [12, 0, -12])
        #expect(wild == tame)
        #expect(wild.allSatisfy { $0.decibels.isFinite })
    }

    @Test func theDrawingRangeCoversTheBoostAndTheCut() {
        #expect(EqualiserCurve.displayRange == -12...12)
    }
}
