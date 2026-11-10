import CoreGraphics
import Testing
@testable import ZeusCore

@Suite struct DrawingSceneTests {
    @Test func schemaRoundTripsAndRejectsAnEmptyOrHugeScene() {
        let scene = DrawingScene.pythagorean()
        let decoded = DrawingScene.decode(scene.encode())
        #expect(decoded == scene)
        #expect(DrawingScene(steps: []) == nil)
        let tooMany = Array(repeating: DrawingStep(marks: [.line(from: UnitPoint(x: 0, y: 0), to: UnitPoint(x: 1, y: 1))]), count: 13)
        #expect(DrawingScene(steps: tooMany) == nil)
        let crowded = DrawingStep(marks: Array(repeating: .label(text: "x", at: UnitPoint(x: 0.1, y: 0.1)), count: 41))
        #expect(DrawingScene(steps: [crowded]) == nil)
    }

    @Test func pythagoreanIsThreeCumulativeStepsAndLabelsMissTheArrows() {
        let scene = DrawingScene.pythagorean()
        #expect(scene.steps.count == 3)
        #expect(scene.cumulative(through: 0).count == 3)
        #expect(scene.cumulative(through: 2).count == 7)
        let placed = DrawingLayout.place(scene.cumulative(through: 2))
        #expect(DrawingLayout.labelsOverlapStrokes(placed) == false)
        let math = MathTypeset.render("a^2+b^2=c^2")
        #expect(math.spoken == "a²+b²=c²")
        #expect(!math.spoken.contains("$"))
        #expect(math.hasSuperscript)
        let fraction = MathTypeset.render("$\\frac{a}{b}$")
        #expect(fraction.numerator == "a")
        #expect(fraction.denominator == "b")
        #expect(!fraction.spoken.contains("$"))
        #expect(!fraction.spoken.contains("frac"))
    }

    @Test func unitPointsLandOn1080pAnd4KOverlays() {
        let scene = DrawingScene.pythagorean()
        let hd = DisplayMap(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1)
        let fourK = DisplayMap(id: 4, frame: CGRect(x: 1920, y: 0, width: 3840, height: 2160), scale: 1)
        let point = UnitPoint(x: 0.5, y: 0.25)
        let onHD = scene.overlay(point, on: hd)
        let on4K = scene.overlay(point, on: fourK)
        #expect(abs(onHD.x - 960) < 0.001)
        #expect(abs(onHD.y - 270) < 0.001)
        #expect(abs(on4K.x - 1920) < 0.001)
        #expect(abs(on4K.y - 540) < 0.001)
    }
}
