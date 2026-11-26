import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplanationProceduralEVAssetsTests {
    private typealias Assets = ExplanationProceduralEVAssets

    @Test func batteryIsAGridOfBoxesInAGroup() {
        let battery = part(.propulsion, Assets.batteryID)
        #expect(battery?.kind == .group)
        #expect(battery?.label == nil)
        #expect(Assets.batteryColumns == 4)
        #expect(Assets.batteryRows == 2)
        let solids = battery?.solids ?? []
        #expect(solids.count == Assets.batteryColumns * Assets.batteryRows)
        #expect(solids.allSatisfy { solid in
            if case .box = solid.shape { return solid.spin == nil }
            return false
        })
        #expect(Set(solids.map(\.name)).count == solids.count)
        #expect(Set(solids.map(\.x)).count == Assets.batteryColumns)
        #expect(Set(solids.map(\.z)).count == Assets.batteryRows)
        #expect(Set(solids.map(\.y)) == [0])
        for column in 0..<Assets.batteryColumns {
            for row in 0..<Assets.batteryRows {
                let name = "cell-\(column)-\(row)"
                let solid = solids.first { $0.name == name }
                #expect(solid?.x == (Double(column) - 1.5) * Assets.batteryPitchX)
                #expect(solid?.y == 0)
                #expect(solid?.z == (Double(row) - 0.5) * Assets.batteryPitchZ)
                let size = box(solid)
                #expect(size?.width == Assets.cellWidth)
                #expect(size?.height == Assets.cellHeight)
                #expect(size?.depth == Assets.cellDepth)
                #expect((size?.width ?? 0) > 0)
                #expect((size?.height ?? 0) > 0)
                #expect((size?.depth ?? 0) > 0)
            }
        }
    }

    @Test func inverterIsABoxWithALabel() {
        let inverter = part(.propulsion, Assets.inverterID)
        #expect(inverter?.kind == .part)
        #expect(inverter?.solids.count == 1)
        let housing = inverter?.solids.first
        #expect(housing?.name == "housing")
        #expect(housing?.spin == nil)
        #expect(housing?.x == 0)
        #expect(housing?.y == 0)
        #expect(housing?.z == 0)
        let size = box(housing)
        #expect(size?.width == Assets.inverterWidth)
        #expect(size?.height == Assets.inverterHeight)
        #expect(size?.depth == Assets.inverterDepth)
        #expect((size?.width ?? 0) > 0 && (size?.height ?? 0) > 0 && (size?.depth ?? 0) > 0)
        let label = inverter?.label
        #expect(label?.text == "Inverter")
        #expect(label?.text == Assets.inverterLabel)
        #expect(label?.x == 0)
        #expect(label?.z == 0)
        let top = (housing?.y ?? 0) + (size?.height ?? 0) / 2
        #expect((label?.y ?? 0) == top + Assets.labelLift)
        #expect((label?.y ?? 0) > top)
        let text = label?.text ?? ""
        #expect(!text.isEmpty)
        #expect(text.utf8.count <= Assets.labelByteBudget)
        #expect(text.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 })
        #expect(!text.contains("—"))
        #expect(!text.contains("://"))
        #expect(!text.lowercased().contains("www."))
        #expect(!text.lowercased().contains("http"))
    }

    @Test func motorIsStatorAndRotorCylinders() {
        let motor = part(.propulsion, Assets.motorID)
        #expect(motor?.kind == .part)
        #expect(motor?.label == nil)
        #expect(motor?.solids.count == 2)
        #expect(motor?.solids.allSatisfy { cylinder($0) != nil } == true)
        let stator = motor?.solids.first { $0.name == "stator" }
        let rotor = motor?.solids.first { $0.name == "rotor" }
        #expect(stator?.spin == nil)
        #expect(rotor?.spin == Assets.rotorSpin)
        #expect(rotor?.spin == 1)
        #expect(stator?.x == rotor?.x)
        #expect(stator?.y == rotor?.y)
        #expect(stator?.z == rotor?.z)
        #expect(stator?.x == 0 && stator?.y == 0 && stator?.z == 0)
        let statorShape = cylinder(stator)
        let rotorShape = cylinder(rotor)
        #expect(statorShape?.axis == .z)
        #expect(rotorShape?.axis == .z)
        #expect(statorShape?.radius == Assets.statorRadius)
        #expect(statorShape?.length == Assets.statorLength)
        #expect(rotorShape?.radius == Assets.rotorRadius)
        #expect(rotorShape?.length == Assets.rotorLength)
        #expect((rotorShape?.radius ?? 1) < (statorShape?.radius ?? 0))
        #expect((rotorShape?.length ?? 1) < (statorShape?.length ?? 0))
    }

    @Test func drivetrainIsGearCylindersPlusAnAxle() {
        let drive = part(.propulsion, Assets.drivetrainID)
        #expect(drive?.kind == .part)
        #expect(drive?.label == nil)
        #expect(drive?.solids.count == 3)
        #expect(drive?.solids.allSatisfy { cylinder($0) != nil } == true)
        let input = drive?.solids.first { $0.name == "input-gear" }
        let output = drive?.solids.first { $0.name == "output-gear" }
        let axle = drive?.solids.first { $0.name == "axle" }
        let inputShape = cylinder(input)
        let outputShape = cylinder(output)
        let axleShape = cylinder(axle)
        #expect(inputShape?.axis == .z)
        #expect(outputShape?.axis == .z)
        #expect(axleShape?.axis == .z)
        #expect(inputShape?.radius == Assets.inputGearRadius)
        #expect(outputShape?.radius == Assets.outputGearRadius)
        #expect(inputShape?.length == Assets.gearLength)
        #expect(outputShape?.length == Assets.gearLength)
        #expect(axleShape?.radius == Assets.axleRadius)
        #expect(axleShape?.length == Assets.axleLength)
        #expect((outputShape?.radius ?? 0) > (inputShape?.radius ?? 1))
        #expect((axleShape?.radius ?? 1) < (inputShape?.radius ?? 0))
        #expect((axleShape?.radius ?? 1) < (outputShape?.radius ?? 0))
        #expect((axleShape?.length ?? 0) > (inputShape?.length ?? 1))
        #expect((axleShape?.length ?? 0) > (outputShape?.length ?? 1))
        #expect(input?.x == Assets.inputGearX)
        #expect(output?.x == Assets.outputGearX)
        #expect(input?.y == output?.y)
        #expect(input?.z == output?.z)
        #expect(input?.y == 0 && input?.z == 0)
        #expect(axle?.x == output?.x)
        #expect(axle?.y == output?.y)
        #expect(axle?.z == output?.z)
        let dx = (output?.x ?? 0) - (input?.x ?? 0)
        let dy = (output?.y ?? 0) - (input?.y ?? 0)
        let dz = (output?.z ?? 0) - (input?.z ?? 0)
        let gap = (inputShape?.radius ?? 0) + (outputShape?.radius ?? 0)
        #expect(dx * dx + dy * dy + dz * dz == gap * gap)
        #expect(input?.spin == Assets.inputGearSpin)
        #expect(output?.spin == Assets.outputGearSpin)
        #expect(input?.spin == 1)
        #expect(output?.spin == -((inputShape?.radius ?? 0) / (outputShape?.radius ?? 1)))
        #expect((input?.spin ?? 0) * (output?.spin ?? 0) < 0)
        let inputTangential = abs(input?.spin ?? 0) * (inputShape?.radius ?? 0)
        let outputTangential = abs(output?.spin ?? 0) * (outputShape?.radius ?? 0)
        #expect(inputTangential == outputTangential)
        #expect(axle?.spin == output?.spin)
    }

    @Test func wheelsAreCylinders() {
        let wheels = part(.propulsion, Assets.wheelsID)
        #expect(wheels?.kind == .part)
        #expect(wheels?.label == nil)
        #expect(wheels?.solids.count == 2)
        #expect(wheels?.solids.allSatisfy { cylinder($0) != nil } == true)
        let left = wheels?.solids.first { $0.name == "wheel-left" }
        let right = wheels?.solids.first { $0.name == "wheel-right" }
        let leftShape = cylinder(left)
        let rightShape = cylinder(right)
        #expect(leftShape?.axis == .z)
        #expect(rightShape?.axis == .z)
        #expect(leftShape?.radius == Assets.wheelRadius)
        #expect(rightShape?.radius == Assets.wheelRadius)
        #expect(leftShape?.length == Assets.wheelLength)
        #expect(rightShape?.length == Assets.wheelLength)
        #expect((leftShape?.radius ?? 0) > 0)
        #expect((leftShape?.length ?? 0) > 0)
        #expect(leftShape?.radius == rightShape?.radius)
        #expect(leftShape?.length == rightShape?.length)
        #expect(left?.x == right?.x)
        #expect(left?.y == right?.y)
        #expect(left?.x == 0 && left?.y == 0)
        #expect(left?.z == Assets.wheelZ)
        #expect(right?.z == -Assets.wheelZ)
        #expect(left?.z == -(right?.z ?? 0))
        #expect((left?.z ?? 0) > 0)
        #expect(left?.spin == Assets.wheelSpin)
        #expect(right?.spin == Assets.wheelSpin)
        #expect(left?.spin == right?.spin)
        #expect((left?.spin ?? 0) != 0)
    }

    @Test func propulsionFlowsForwardFromBatteryToWheels() {
        let assembly = Assets.assembly(for: .propulsion)
        #expect(Assets.batteryID == "battery")
        #expect(Assets.inverterID == "inverter")
        #expect(Assets.motorID == "motor")
        #expect(Assets.drivetrainID == "drivetrain")
        #expect(Assets.wheelsID == "wheels")
        #expect(assembly.parts.map(\.id) == ["battery", "inverter", "motor", "drivetrain", "wheels"])
        #expect(assembly.flow.direction == .forward)
        #expect(assembly.flow.partIDs == ["battery", "inverter", "motor", "wheels"])
        #expect(assembly.flow.partIDs == Assets.flowPartIDs)
        #expect(!assembly.flow.partIDs.contains("drivetrain"))
        #expect(!assembly.flow.partIDs.contains(Assets.drivetrainID))
        #expect(assembly.flow.partIDs.allSatisfy { id in assembly.parts.contains { $0.id == id } })
    }

    @Test func regenerationRunsTheSamePathInReverse() {
        let forward = Assets.assembly(for: .propulsion)
        let reverse = Assets.assembly(for: .regeneration)
        #expect(reverse.flow.direction == .reverse)
        #expect(reverse.flow.partIDs == ["battery", "inverter", "motor", "wheels"])
        #expect(reverse.flow.partIDs == forward.flow.partIDs)
        #expect(reverse.flow.partIDs != Array(reverse.flow.partIDs.reversed()))
        #expect(!reverse.flow.partIDs.contains(Assets.drivetrainID))
        #expect(reverse.parts == forward.parts)
        #expect(reverse.flow != forward.flow)
        #expect(reverse.flow.partIDs.allSatisfy { id in reverse.parts.contains { $0.id == id } })
    }

    @Test func theCatalogStaysInsideTheExplanationBudgets() {
        #expect(Assets.objectBudget == 256)
        #expect(Assets.coordinateLimit == 16_384)
        #expect(Assets.labelByteBudget == 1_024)
        for energy in [Assets.Energy.propulsion, .regeneration] {
            let assembly = Assets.assembly(for: energy)
            let solids = assembly.parts.flatMap(\.solids)
            let labels = assembly.parts.compactMap(\.label)
            #expect(solids.count == 16)
            #expect(labels.count == 1)
            #expect(solids.count <= Assets.objectBudget)
            #expect(assembly.parts.count == 5)
            #expect(Set(assembly.parts.map(\.id)).count == assembly.parts.count)
            for part in assembly.parts {
                #expect(validID(part.id))
                #expect(Set(part.solids.map(\.name)).count == part.solids.count)
                for solid in part.solids {
                    #expect(validID(solid.name))
                    #expect(placed(solid.x) && placed(solid.y) && placed(solid.z))
                    if let spin = solid.spin {
                        #expect(spin.isFinite && spin != 0)
                    }
                    switch solid.shape {
                    case .box(let width, let height, let depth):
                        #expect(width > 0 && height > 0 && depth > 0)
                        #expect(width.isFinite && height.isFinite && depth.isFinite)
                    case .cylinder(let radius, let length, _):
                        #expect(radius > 0 && length > 0)
                        #expect(radius.isFinite && length.isFinite)
                    }
                }
                if let label = part.label {
                    #expect(label.text.utf8.count <= Assets.labelByteBudget)
                    #expect(placed(label.x) && placed(label.y) && placed(label.z))
                    #expect(!label.text.contains("://"))
                    #expect(!label.text.lowercased().contains("www."))
                }
            }
        }
    }

    private func part(_ energy: Assets.Energy, _ id: String) -> Assets.Part? {
        Assets.assembly(for: energy).parts.first { $0.id == id }
    }

    private func box(_ solid: Assets.Solid?) -> (width: Double, height: Double, depth: Double)? {
        guard let solid, case .box(let width, let height, let depth) = solid.shape else { return nil }
        return (width, height, depth)
    }

    private func cylinder(_ solid: Assets.Solid?) -> (radius: Double, length: Double, axis: Assets.Axis)? {
        guard let solid, case .cylinder(let radius, let length, let axis) = solid.shape else { return nil }
        return (radius, length, axis)
    }

    private func placed(_ value: Double) -> Bool {
        value.isFinite && abs(value) <= Assets.coordinateLimit
    }

    /// Identifier shape from `ExplanationSceneReducer.identifier`: 1...64 bytes of
    /// letters, digits, hyphen, and underscore.
    private func validID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard (1...64).contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
        }
    }
}
