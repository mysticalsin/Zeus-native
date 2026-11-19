import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing stroke targeting")
struct PointingStrokeTargetingTests {
    private let button = PointingTargetCandidate(id: "t0", role: "AXButton", label: "Share",
                                                 imageRect: .init(x: 100, y: 100, width: 200, height: 50))
    private let field = PointingTargetCandidate(id: "t1", role: "AXTextField", label: "Search",
                                                imageRect: .init(x: 400, y: 100, width: 100, height: 50))

    private func pt(_ x: Double, _ y: Double) -> ExplanationVector3 { .init(x: x, y: y) }

    private var loopAroundButton: [ExplanationVector3] {
        [pt(90, 125), pt(120, 90), pt(200, 90), pt(280, 90), pt(310, 125), pt(280, 160), pt(200, 160), pt(120, 160), pt(92, 127)]
    }

    @Test func aLoopAroundAControlPicksThatControl() {
        let result = PointingStrokeTargeting.target(stroke: loopAroundButton, candidates: [button, field])
        #expect(result?.shape == .closed)
        #expect(result?.best?.candidateID == "t0")
        #expect(result?.ranked.count == 1)
    }

    @Test func anUnderlinePicksTheControlItPassesThrough() {
        let line = (0..<6).map { pt(400 + Double($0) * 20, 155) }
        let result = PointingStrokeTargeting.target(stroke: line, candidates: [button, field])
        #expect(result?.shape == .open)
        #expect(result?.best?.candidateID == "t1")
    }

    @Test func aDotPicksTheControlUnderIt() {
        let result = PointingStrokeTargeting.target(stroke: [pt(150, 120)], candidates: [button, field])
        #expect(result?.shape == .dot)
        #expect(result?.best?.candidateID == "t0")
    }

    @Test func aLoopAroundSeveralControlsRanksTheTighterFitFirst() {
        let loop = [pt(50, 125), pt(150, 50), pt(300, 50), pt(450, 50), pt(550, 125), pt(450, 200), pt(300, 200), pt(150, 200), pt(52, 127)]
        let result = PointingStrokeTargeting.target(stroke: loop, candidates: [button, field])
        #expect(result?.ranked.map(\.candidateID) == ["t0", "t1"])
    }

    @Test func aSecureFieldIsNeverATarget() {
        let secure = PointingTargetCandidate(id: "t0", role: "AXTextField", imageRect: .init(x: 100, y: 100, width: 200, height: 50),
                                             isSecure: true)
        let result = PointingStrokeTargeting.target(stroke: [pt(150, 120)], candidates: [secure])
        #expect(result?.ranked.isEmpty == true)
        #expect(result?.useRegion == true)
    }

    @Test func aStrokeOverEmptyScreenBecomesARegionCandidate() {
        let loop = [pt(600, 350), pt(650, 300), pt(700, 350), pt(650, 400), pt(602, 352), pt(601, 351)]
        let size = ExplanationSize2(width: 1440, height: 900)
        let strokes = [PointingStrokeTargeting.ImageStroke(id: "s0", points: loop, time: 2)]
        let resolution = PointingStrokeTargeting.resolve(strokes: strokes, candidates: [button, field], imageSize: size)
        #expect(resolution.assignments["s0"] == "t2")
        #expect(resolution.candidates.count == 3)
        #expect(resolution.candidates[2].source == .strokeBounds)
        #expect(resolution.candidates[2].role == "region")
        let rect = resolution.candidates[2].imageRect
        #expect(rect?.x == 592 && rect?.y == 292)
    }

    @Test func aRegionIsClippedToTheImageAndDroppedWhenOutside() {
        let size = ExplanationSize2(width: 100, height: 100)
        let near = PointingStrokeTargeting.regionCandidate(id: "t0", bounds: .init(x: 90, y: 90, width: 30, height: 30), imageSize: size)
        #expect(near?.imageRect == ExplanationRect(x: 82, y: 82, width: 18, height: 18))
        let outside = PointingStrokeTargeting.regionCandidate(id: "t0", bounds: .init(x: 500, y: 500, width: 10, height: 10), imageSize: size)
        #expect(outside == nil)
    }

    @Test func theCandidateListStaysBounded() {
        let full = (0..<PointingContext.maxCandidates).map {
            PointingTargetCandidate(id: "t\($0)", role: "AXGroup", imageRect: .init(x: 2000, y: 2000, width: 10, height: 10))
        }
        let loop = [pt(600, 350), pt(650, 300), pt(700, 350), pt(650, 400), pt(602, 352), pt(601, 351)]
        let resolution = PointingStrokeTargeting.resolve(strokes: [.init(id: "s0", points: loop, time: 0)], candidates: full, imageSize: nil)
        #expect(resolution.candidates.count == PointingContext.maxCandidates)
        #expect(resolution.assignments.isEmpty)
    }

    @Test func nonFinitePointsProduceNoBounds() {
        #expect(PointingStrokeTargeting.bounds(of: [pt(.nan, 1)]) == nil)
        #expect(PointingStrokeTargeting.bounds(of: []) == nil)
    }
}
