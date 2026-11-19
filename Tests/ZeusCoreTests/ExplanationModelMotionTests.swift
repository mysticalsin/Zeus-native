import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplanationModelMotionTests {
    private func vec(_ x: Double, _ y: Double, _ z: Double) -> ExplanationVector3 { .init(x: x, y: y, z: z) }
    private let viewport = ExplanationSize2(width: 800, height: 600)

    // MARK: Projection and labels

    @Test func projectionPlacesTheTargetAtTheCentreAndKeepsHandedness() throws {
        let camera = ExplanationCamera(position: vec(0, 0, 10), target: .zero, fieldOfView: 60)
        let centre = try #require(ExplanationProjection.project(.zero, camera: camera, viewport: viewport))
        #expect(abs(centre.x - 400) < 1e-9 && abs(centre.y - 300) < 1e-9 && abs(centre.depth - 10) < 1e-9)
        let right = try #require(ExplanationProjection.project(vec(1, 0, 0), camera: camera, viewport: viewport))
        #expect(right.x > 400 && abs(right.y - 300) < 1e-9)
        let up = try #require(ExplanationProjection.project(vec(0, 1, 0), camera: camera, viewport: viewport))
        #expect(up.y < 300)
        let edge = try #require(ExplanationProjection.project(vec(0, 10 * tan(Double.pi / 6), 0), camera: camera, viewport: viewport))
        #expect(abs(edge.y) < 1e-6)
        #expect(ExplanationProjection.project(vec(0, 0, 20), camera: camera, viewport: viewport) == nil)
        #expect(ExplanationProjection.project(.zero, camera: camera, viewport: .init(width: 0, height: 10)) == nil)
    }

    @Test func orbitingKeepsTheTargetCentredAndSwapsSides() throws {
        let start = ExplanationCamera(position: vec(0, 0, 10), target: .zero, fieldOfView: 60)
        let turned = ExplanationCameraMath.apply(.init(orbit: 90), to: start)
        let centre = try #require(ExplanationProjection.project(.zero, camera: turned, viewport: viewport))
        #expect(abs(centre.x - 400) < 1e-6 && abs(centre.y - 300) < 1e-6)
        let before = try #require(ExplanationProjection.project(vec(0, 0, 1), camera: start, viewport: viewport))
        let after = try #require(ExplanationProjection.project(vec(0, 0, 1), camera: turned, viewport: viewport))
        #expect(abs(before.x - 400) < 1e-6 && after.x < 400)
    }

    @Test func labelsNeverOverlapOrCoverAnAnchor() {
        let bounds = ExplanationScreenRect(x: 0, y: 0, width: 600, height: 400)
        let requests = (0..<6).map { ExplanationLabelRequest(id: "l\($0)", anchorX: 200 + Double($0) * 30, anchorY: 200, width: 90, height: 22) }
        let result = ExplanationLabelLayout.place(requests, bounds: bounds)
        #expect(result.placed.count + result.hidden.count == 6)
        let rects = result.placed.sorted { $0.key < $1.key }.map { $0.value }
        for (index, rect) in rects.enumerated() {
            #expect(bounds.contains(rect))
            for other in rects.dropFirst(index + 1) { #expect(!rect.intersects(other)) }
            for request in requests {
                let dot = ExplanationScreenRect(x: request.anchorX - 5, y: request.anchorY - 5, width: 10, height: 10)
                #expect(!rect.intersects(dot))
            }
        }
    }

    @Test func separatedLabelsTakeTheRightHandSlotAndPreviousSlotsAreKept() {
        let bounds = ExplanationScreenRect(x: 0, y: 0, width: 600, height: 400)
        let far = [ExplanationLabelRequest(id: "a", anchorX: 100, anchorY: 100, width: 80, height: 22),
                   ExplanationLabelRequest(id: "b", anchorX: 400, anchorY: 300, width: 80, height: 22)]
        let first = ExplanationLabelLayout.place(far, bounds: bounds)
        #expect(first.slots == ["a": 0, "b": 0])
        let again = ExplanationLabelLayout.place(far, bounds: bounds, previousSlots: ["a": 3])
        #expect(again.slots["a"] == 3 && again.slots["b"] == 0)
    }

    @Test func aLabelWithNoRoomIsHiddenNotStacked() {
        let tiny = ExplanationScreenRect(x: 0, y: 0, width: 60, height: 30)
        let result = ExplanationLabelLayout.place([.init(id: "wide", anchorX: 30, anchorY: 15, width: 80, height: 22)], bounds: tiny)
        #expect(result.placed.isEmpty && result.hidden == ["wide"])
    }

    // MARK: Flow

    private let route = ExplanationFlowPath(id: "route", points: [.zero, ExplanationVector3(x: 4, y: 0, z: 0)])

    @Test func flowMarkersTravelInWorldPathOrderRegardlessOfCamera() {
        let forward = ExplanationFlow(id: "f", pathID: "route", speed: 1, direction: .forward, count: 4)
        let start = ExplanationFlowMath.markers(for: forward, path: route, progress: 0)
        #expect(start.map(\.position.x) == [0, 1, 2, 3])
        #expect(start.allSatisfy { $0.tangent == vec(1, 0, 0) })
        let later = ExplanationFlowMath.markers(for: forward, path: route, progress: 0.5)
        #expect(later.map(\.position.x) == [0.5, 1.5, 2.5, 3.5])
        var reverse = forward; reverse.direction = .reverse
        let back = ExplanationFlowMath.markers(for: reverse, path: route, progress: 0)
        #expect(back.allSatisfy { $0.tangent == vec(-1, 0, 0) })
        // A camera orbit changes only screen positions, never the world tangent that the arrow points along.
        for degrees in stride(from: 0.0, to: 360, by: 45) {
            let camera = ExplanationCameraMath.apply(.init(orbit: degrees), to: ExplanationCamera())
            let tail = ExplanationProjection.project(start[1].position, camera: camera, viewport: viewport)
            #expect(tail != nil)
            #expect(start[1].tangent == vec(1, 0, 0) && back[1].tangent == vec(-1, 0, 0))
        }
    }

    @Test func markersFollowABentPathAndWrap() {
        let bent = ExplanationFlowPath(id: "bent", points: [.zero, vec(1, 0, 0), vec(1, 1, 0)])
        let flow = ExplanationFlow(id: "f", pathID: "bent", speed: 1, count: 1)
        let onSecond = ExplanationFlowMath.markers(for: flow, path: bent, progress: 1.5)
        #expect(onSecond.count == 1 && abs(onSecond[0].position.y - 0.5) < 1e-9 && onSecond[0].tangent == vec(0, 1, 0))
        let wrapped = ExplanationFlowMath.markers(for: flow, path: bent, progress: 2.25)
        #expect(abs(wrapped[0].position.x - 0.25) < 1e-9)
        let negative = ExplanationFlowMath.markers(for: flow, path: bent, progress: -0.5)
        #expect(abs(negative[0].position.y - 0.5) < 1e-9)
    }

    // MARK: Clock

    private func spinning(rate: Double = 2, animationRate: Double = 1) -> ExplanationModel3D {
        .init(parts: ["w": ModelFixtures.recipe("w", .wheel, spin: rate)], animationRate: animationRate)
    }
    private func run(_ model: ExplanationModel3D, frames: Int, seconds: Double) -> ExplanationModelClock {
        var clock = ExplanationModelClock()
        for frame in 0...frames { clock.advance(to: seconds * Double(frame) / Double(frames), model: model) }
        return clock
    }

    @Test func animationIsDrivenByElapsedTimeNotFrameCount() {
        let at60 = run(spinning(), frames: 60, seconds: 1)
        let at30 = run(spinning(), frames: 30, seconds: 1)
        let at144 = run(spinning(), frames: 144, seconds: 1)
        #expect(abs((at60.spinAngles["w"] ?? 0) - 2) < 1e-9)
        #expect(abs((at30.spinAngles["w"] ?? 0) - (at60.spinAngles["w"] ?? 0)) < 1e-9)
        #expect(abs((at144.spinAngles["w"] ?? 0) - (at60.spinAngles["w"] ?? 0)) < 1e-9)
        #expect(abs(at60.elapsed - 1) < 1e-9)
    }

    @Test func animationRateScalesTimeAndRateChangesContinueFromThePose() {
        let half = run(spinning(animationRate: 0.5), frames: 60, seconds: 1)
        #expect(abs((half.spinAngles["w"] ?? 0) - 1) < 1e-9)
        var clock = ExplanationModelClock()
        var model = spinning()
        for frame in 0...30 { clock.advance(to: Double(frame) / 60, model: model) }
        let before = clock.spinAngles["w"] ?? 0
        model.animationRate = 0.4
        clock.advance(to: 31.0 / 60, model: model)
        let after = clock.spinAngles["w"] ?? 0
        #expect(abs(after - before - 2 * 0.4 / 60) < 1e-9)
    }

    @Test func aStalledDisplayCannotJumpTheAnimation() {
        var clock = ExplanationModelClock()
        let model = spinning()
        clock.advance(to: 0, model: model)
        clock.advance(to: 100, model: model)
        #expect(abs(clock.elapsed - ExplanationModelClock.maximumStep) < 1e-12)
        clock.suspend()
        clock.advance(to: 500, model: model)
        #expect(abs(clock.elapsed - ExplanationModelClock.maximumStep) < 1e-12)
    }

    @Test func reduceMotionAndHiddenPartsStayStill() {
        var still = ExplanationModelClock()
        let model = spinning()
        for frame in 0...60 { still.advance(to: Double(frame) / 60, model: model, reduceMotion: true) }
        #expect(still.spinAngles.isEmpty && still.elapsed == 0)
        var hiddenModel = spinning()
        hiddenModel.parts["w"]?.visible = false
        let hidden = run(hiddenModel, frames: 60, seconds: 1)
        #expect((hidden.spinAngles["w"] ?? 0) == 0)
    }

    @Test func reversingAFlowContinuesSmoothlyAndFlowsStopWhenInactive() {
        var model = ExplanationModel3D(paths: ["route": route], flows: ["f": .init(id: "f", pathID: "route", speed: 1)])
        var clock = ExplanationModelClock()
        for frame in 0...60 { clock.advance(to: Double(frame) / 60, model: model) }
        let forward = clock.flowProgress["f"] ?? 0
        #expect(abs(forward - 1) < 1e-9)
        model.flows["f"]?.direction = .reverse
        clock.advance(to: 61.0 / 60, model: model)
        let reversed = clock.flowProgress["f"] ?? 0
        #expect(abs(reversed - (1 - 1.0 / 60)) < 1e-9)
        model.flows["f"]?.active = false
        clock.advance(to: 62.0 / 60, model: model)
        #expect(abs((clock.flowProgress["f"] ?? 0) - reversed) < 1e-12)
    }

    @Test func hasMotionReflectsSpinFlowAndRate() {
        #expect(spinning().hasMotion)
        #expect(!spinning(rate: 0).hasMotion)
        var model = spinning()
        model.parts["w"]?.visible = false
        #expect(!model.hasMotion)
        let flowing = ExplanationModel3D(paths: ["route": route], flows: ["f": .init(id: "f", pathID: "route", speed: 1)])
        #expect(flowing.hasMotion)
        #expect(!ExplanationModel3D.empty.hasMotion)
    }

    // MARK: Rolling and camera

    @Test func wheelsTurnInTheTravelDirection() {
        let forward = ExplanationRolling.spinRate(travel: vec(2, 0, 0), axle: .z, radius: 0.33)
        #expect(abs(forward + 2 / 0.33) < 1e-9)
        #expect(ExplanationRolling.spinRate(travel: vec(-2, 0, 0), axle: .z, radius: 0.33) > 0)
        #expect(abs(ExplanationRolling.spinRate(travel: vec(2, 0, 0), axle: .x, radius: 0.33)) < 1e-12)
        #expect(ExplanationRolling.angularVelocity(travel: vec(1, 0, 0), radius: 0) == .zero)
    }

    @Test func cameraInterpolationSweepsAnArcAtConstantRadius() {
        let a = ExplanationCamera(position: vec(0, 3, 8), target: .zero, fieldOfView: 40)
        let b = ExplanationCameraMath.apply(.init(orbit: 90), to: a)
        #expect(ExplanationCameraMath.interpolate(a, b, 0) == a && ExplanationCameraMath.interpolate(a, b, 1) == b)
        let mid = ExplanationCameraMath.interpolate(a, b, 0.5)
        let radius = ExplanationV3.length(ExplanationV3.sub(mid.position, mid.target))
        #expect(abs(radius - ExplanationV3.length(ExplanationV3.sub(a.position, a.target))) < 1e-9)
        let expected = 8 * sin(Double.pi / 4)
        #expect(abs(mid.position.x - expected) < 1e-9 && abs(mid.position.z - expected) < 1e-9)
    }
}
