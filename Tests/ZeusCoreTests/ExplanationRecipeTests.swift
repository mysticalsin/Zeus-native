import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplanationRecipeTests {
    private func extent(_ recipe: ExplanationPartRecipe) -> ExplanationVector3 {
        let b = ExplanationRecipes.bounds(recipe)
        return .init(x: b.max.x - b.min.x, y: b.max.y - b.min.y, z: b.max.z - b.min.z)
    }

    @Test func everyRecipeHasTheExpectedPartCount() {
        let expected: [ExplanationPartRecipe: Int] = [.batteryPack: 14, .inverterBox: 10, .motor: 14,
                                                      .reductionGear: 33, .halfShafts: 8, .wheel: 8, .carShell: 5]
        for recipe in ExplanationPartRecipe.allCases {
            #expect(ExplanationRecipes.primitives(recipe).count == expected[recipe])
        }
    }

    @Test func primitivesAreWellFormed() {
        for recipe in ExplanationPartRecipe.allCases {
            let solids = ExplanationRecipes.primitives(recipe)
            #expect(Set(solids.map(\.name)).count == solids.count)
            for solid in solids {
                #expect((0...1).contains(solid.metalness) && (0...1).contains(solid.roughness))
                #expect(solid.opacity > 0 && solid.opacity <= 1)
                let b = solid.bounds
                #expect(b.max.x > b.min.x && b.max.y > b.min.y && b.max.z > b.min.z)
                if case .cylinder = solid.shape { #expect(solid.roll == 0) }
                if let spin = solid.spin { #expect(spin.factor.isFinite && spin.factor != 0) }
            }
        }
    }

    @Test func dimensionsArePhysicallyPlausible() {
        let wheel = extent(.wheel)
        #expect(abs(wheel.x - 0.66) < 1e-9 && abs(wheel.y - 0.66) < 1e-9 && abs(wheel.z - 0.22) < 1e-9)
        let car = extent(.carShell)
        #expect(abs(car.x - 4.7) < 1e-9 && abs(car.z - 1.6) < 1e-9 && car.y > 1.0 && car.y < 1.4)
        let pack = extent(.batteryPack)
        #expect(pack.x > 1.8 && pack.x < 2.2 && pack.z > 1.2 && pack.z < 1.6 && pack.y < 0.2)
        let motor = extent(.motor)
        #expect(motor.x < 0.5 && motor.y < 0.5 && motor.z < 0.7)
        let inverter = extent(.inverterBox)
        #expect(inverter.x < 0.7 && inverter.y < 0.3 && inverter.z < 0.4)
        let shafts = extent(.halfShafts)
        #expect(shafts.z > 1.4 && shafts.z < 1.8 && shafts.x < 0.12)
    }

    @Test func drivetrainPartsFitInsideTheCarBody() {
        let car = ExplanationRecipes.bounds(.carShell)
        let pack = ExplanationRecipes.bounds(.batteryPack)
        #expect(pack.max.x - pack.min.x < car.max.x - car.min.x)
        #expect(pack.max.z - pack.min.z < car.max.z - car.min.z)
    }

    @Test func reductionGearRatioMatchesTheToothCounts() {
        let solids = ExplanationRecipes.primitives(.reductionGear)
        #expect(solids.filter { $0.name.hasPrefix("input-tooth") }.count == 8)
        #expect(solids.filter { $0.name.hasPrefix("output-tooth") }.count == 20)
        #expect(abs(ExplanationRecipes.reductionOutputFactor + 0.4) < 1e-12)
        func radius(_ name: String) -> Double? {
            for solid in solids where solid.name == name {
                if case .cylinder(let r, _, _) = solid.shape { return r }
            }
            return nil
        }
        let input = (radius("input-gear") ?? 0) + 0.012, output = (radius("output-gear") ?? 1) + 0.012
        #expect(abs(input / output - 0.4) < 1e-9)
        let outputGear = solids.first { $0.name == "output-gear" }
        #expect(outputGear?.spin?.factor == ExplanationRecipes.reductionOutputFactor)
    }

    @Test func onlyTheMovingSolidsRotate() {
        #expect(ExplanationRecipes.primitives(.wheel).allSatisfy { $0.spin != nil })
        #expect(ExplanationRecipes.primitives(.carShell).allSatisfy { $0.spin == nil })
        let motor = ExplanationRecipes.primitives(.motor)
        #expect(motor.filter { $0.name.hasPrefix("stator") || $0.name == "housing" }.allSatisfy { $0.spin == nil })
        #expect(motor.filter { $0.name == "rotor" || $0.name == "shaft" }.allSatisfy { $0.spin != nil })
    }

    @Test func primitiveCountIncludesRepeats() {
        let two = ExplanationPartRepeat(count: 2, offset: .init(x: 0, y: 0, z: 1))
        #expect(ExplanationRecipes.primitiveCount(of: ModelFixtures.recipe("w", .wheel, repeats: two)) == 16)
        #expect(ExplanationRecipes.primitiveCount(of: ModelFixtures.box("b")) == 1)
        #expect(ExplanationRecipes.primitiveCount(of: ModelFixtures.group("g")) == 0)
    }
}
