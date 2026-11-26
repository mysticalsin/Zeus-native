import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing teaching follow-up")
struct PointingTeachingFollowUpTests {
    private typealias Follow = PointingTeachingFollowUp

    private func scene(parts: [String] = ["battery", "motor", "inverter", "shell"],
                       details: [String]? = nil,
                       x: Double? = -1.4, y: Double? = 0.33, z: Double? = -0.3) -> Follow.Scene {
        .init(partIDs: parts, detailIDs: details, motorX: x, motorY: y, motorZ: z)
    }

    private func call(_ utterance: String, scene: Follow.Scene? = nil) -> Follow.Outcome {
        Follow.decide(utterance: utterance, scene: scene ?? self.scene())
    }

    private func ready(_ outcome: Follow.Outcome) -> Follow.Plan? {
        if case .ready(let plan) = outcome { return plan }
        return nil
    }

    private func padded(_ count: Int, prefix: String = "d") -> [String] {
        (0..<count).map { n in
            let text = String(n)
            return prefix + String(repeating: "0", count: max(0, 2 - text.count)) + text
        }
    }

    private func aimed(x: Double, y: Double, z: Double) -> Follow.Camera {
        .init(targetID: Follow.motorID, targetX: x, targetY: y, targetZ: z,
              offsetX: Follow.cameraOffsetX, offsetY: Follow.cameraOffsetY, offsetZ: Follow.cameraOffsetZ)
    }

    @Test func showTheMotorAimsTheCameraAtThatPartAndHighlightsIt() {
        let plan = ready(call("show the motor"))
        let camera = aimed(x: -1.4, y: 0.33, z: -0.3)
        #expect(plan?.kind == .showMotor)
        #expect(plan?.speech == nil)
        #expect(plan?.steps == [.camera(camera), .highlight(id: "motor", on: true)])
        #expect(plan?.keptIDs == ["battery", "inverter", "motor", "shell"])
    }

    @Test func showTheMotorKeepsEveryExistingId() {
        let plan = ready(call("show the motor", scene: scene(parts: ["motor", "motor", "battery", "shell"])))
        let onlyAim = plan?.steps.allSatisfy { step in
            switch step {
            case .camera, .highlight: true
            case .rotate, .remove: false
            }
        }
        #expect(onlyAim == true)
        #expect(plan?.keptIDs == ["battery", "motor", "shell"])
        #expect(plan?.steps.count == 2)
    }

    @Test func showTheMotorRefusesWhenThatIdIsAbsent() {
        #expect(call("show the motor", scene: scene(parts: ["battery", "shell"])) == .refused(.missingMotor))
        #expect(call("show the motor", scene: scene(parts: [])) == .refused(.missingMotor))
        #expect(call("show the motor", scene: scene(parts: ["Motor"])) == .refused(.missingMotor))
    }

    @Test func showTheMotorRefusesAPositionItCannotUse() {
        let edge = ready(call("show the motor", scene: scene(x: 16_384, y: -16_384, z: 0)))
        #expect(edge?.steps == [.camera(aimed(x: 16_384, y: -16_384, z: 0)), .highlight(id: "motor", on: true)])
        #expect(call("show the motor", scene: scene(x: 16_384.1, y: 0, z: 0)) == .refused(.position))
        #expect(call("show the motor", scene: scene(x: nil, y: 0, z: 0)) == .refused(.position))
        #expect(call("show the motor", scene: scene(x: .nan, y: 0, z: 0)) == .refused(.position))
        #expect(call("show the motor", scene: scene(x: .infinity, y: 0, z: 0)) == .refused(.position))
    }

    @Test func rotateItTurnsTheMotorAndIgnoresTheCameraPosition() {
        let step = Follow.Step.rotate(id: "motor", radians: Follow.motorRotationRadians, axis: .z, seconds: Follow.rotationSeconds)
        let plan = ready(call("rotate it", scene: scene(parts: ["battery", "motor"], x: .nan)))
        #expect(plan?.kind == .rotateMotor)
        #expect(plan?.speech == nil)
        #expect(plan?.steps == [step])
        #expect(plan?.keptIDs == ["battery", "motor"])
        guard let step = plan?.steps.first else {
            #expect(Bool(false))
            return
        }
        if case .rotate(_, let radians, _, let seconds) = step {
            #expect(radians.isFinite && radians != 0)
            #expect(seconds > 0 && seconds <= 30)
        } else {
            #expect(Bool(false))
        }
    }

    @Test func rotateItRefusesWhenTheMotorIsAbsent() {
        #expect(call("rotate it", scene: scene(parts: ["battery"])) == .refused(.missingMotor))
    }

    @Test func simplerSpeaksAndRemovesTheDetailIds() {
        let plan = ready(call("simpler"))
        #expect(plan?.kind == .simpler)
        #expect(plan?.speech == Follow.simplerSpeech)
        #expect((plan?.speech?.utf8.count ?? 0) > 0)
        #expect((plan?.speech?.utf8.count ?? 9_999) <= Follow.speechByteLimit)
        #expect(plan?.speech?.contains("Tesla") == false)
        #expect(plan?.speech?.unicodeScalars.contains { $0.value == 0x2014 } == false)
        #expect(plan?.steps == [.remove(id: "inverter"), .remove(id: "shell")])
        #expect(plan?.keptIDs == ["battery", "motor"])
    }

    @Test func simplerKeepsMotorAndBatteryEvenIfNamedAsDetail() {
        let named = scene(details: ["shell", "motor", "battery", "missing", "shell", "not a part"])
        let plan = ready(call("simpler", scene: named))
        #expect(plan?.steps == [.remove(id: "shell")])
        #expect(plan?.keptIDs == ["battery", "inverter", "motor"])
        let hyphen = scene(parts: ["battery", "motor", "ok-1_b"], details: ["ok-1_b"])
        #expect(ready(call("simpler", scene: hyphen))?.steps == [.remove(id: "ok-1_b")])
    }

    @Test func simplerWithAnEmptyDetailListOnlySpeaks() {
        let plan = ready(call("simpler", scene: scene(details: [])))
        #expect(plan?.speech == Follow.simplerSpeech)
        #expect(plan?.steps == [])
        #expect(plan?.keptIDs == ["battery", "inverter", "motor", "shell"])
    }

    @Test func simplerRefusesARemovalBudgetItCannotKeep() {
        let thirtyTwo = padded(32)
        let within = scene(parts: ["battery", "motor"] + thirtyTwo)
        let plan = ready(call("simpler", scene: within))
        #expect(plan?.steps == thirtyTwo.map { Follow.Step.remove(id: $0) })
        #expect(plan?.keptIDs == ["battery", "motor"])
        let thirtyThree = scene(parts: ["battery", "motor"] + padded(33))
        #expect(call("simpler", scene: thirtyThree) == .refused(.budget))
        let junk = Array(repeating: "nope", count: 257)
        #expect(call("simpler", scene: scene(details: junk)) == .refused(.budget))
    }

    @Test func highlightTheBatteryIsAHighlightAndNothingElse() {
        let plan = ready(call("highlight the battery", scene: scene(x: .nan)))
        #expect(plan?.kind == .highlightBattery)
        #expect(plan?.speech == nil)
        #expect(plan?.steps == [.highlight(id: "battery", on: true)])
        #expect(plan?.keptIDs == ["battery", "inverter", "motor", "shell"])
        var capped = (0..<255).map { "p\($0)" }
        capped.append("battery")
        let atCap = ready(call("highlight the battery", scene: scene(parts: capped, x: nil, y: nil, z: nil)))
        #expect(atCap?.steps == [.highlight(id: "battery", on: true)])
        #expect(atCap?.keptIDs.count == 256)
    }

    @Test func highlightTheBatteryRefusesWhenThatIdIsAbsent() {
        #expect(call("highlight the battery", scene: scene(parts: ["motor"])) == .refused(.missingBattery))
        var over = (0..<256).map { "p\($0)" }
        over.append("battery")
        #expect(call("highlight the battery", scene: scene(parts: over)) == .refused(.scene))
    }

    @Test func anUnrecognisedPhraseIsRefused() {
        let phrases = ["", "   ", "how does the car work", "rotate the motor", "show the motors",
                       "highlight the batteries", "please please show the motor", "make it simpler"]
        for phrase in phrases {
            #expect(call(phrase) == .refused(.phrase))
        }
    }

    @Test func aMixedCommandIsRefused() {
        #expect(call("show the motor highlight the battery") == .refused(.phrase))
        #expect(call("do not highlight the battery") == .refused(.phrase))
        #expect(call("show the motor,") == .refused(.phrase))
    }

    @Test func anOverlongLinkOrControlUtteranceIsRefused() {
        #expect(call(String(repeating: "a", count: 256)) == .refused(.phrase))
        #expect(call(String(repeating: "a", count: 257)) == .refused(.utterance))
        let link = "show the motor " + ":" + "//" + "x"
        #expect(call(link) == .refused(.utterance))
        #expect(call("show the motor\u{1}") == .refused(.utterance))
        #expect(call("show the motor\u{7f}") == .refused(.utterance))
    }

    @Test func politeCapitalisedAndWrappedPhrasesMatch() {
        let shown = ready(call("Please show the motor."))
        #expect(shown?.kind == .showMotor)
        #expect(shown?.steps.count == 2)
        #expect(shown == ready(call("  SHOW   THE  MOTOR  ")))
        #expect(shown == ready(call("show\nthe motor")))
        let turned = ready(call("PLEASE ROTATE IT!"))
        #expect(turned?.kind == .rotateMotor)
        #expect(turned == ready(call("rotate it")))
        let shorter = ready(call("explain that more simply"))
        #expect(shorter?.kind == .simpler)
        #expect(shorter?.speech == Follow.simplerSpeech)
        #expect(shorter == ready(call("please explain that more simply.")))
        #expect(shorter == ready(call("simpler")))
        let marked = ready(call("Highlight the battery?"))
        #expect(marked?.kind == .highlightBattery)
        #expect(marked?.steps == [.highlight(id: "battery", on: true)])
        #expect(marked == ready(call("highlight the battery")))
    }

    @Test func aSceneWithAnIllegalIdIsRefused() {
        #expect(call("show the motor", scene: scene(parts: ["motor", "bad id"])) == .refused(.scene))
        #expect(call("simpler", scene: scene(parts: ["battery", ""])) == .refused(.scene))
        #expect(call("rotate it", scene: scene(parts: ["motor", "a/b"])) == .refused(.scene))
        let fitted = String(repeating: "a", count: 64)
        let plan = ready(call("simpler", scene: scene(parts: ["battery", "motor", fitted], details: [fitted])))
        #expect(plan?.steps == [.remove(id: fitted)])
        let overflow = String(repeating: "a", count: 65)
        #expect(call("simpler", scene: scene(parts: ["battery", overflow])) == .refused(.scene))
    }

    @Test func anEmptySceneCanSpeakTheShorterLine() {
        let plan = ready(call("explain that more simply", scene: scene(parts: [], x: nil, y: nil, z: nil)))
        #expect(plan?.kind == .simpler)
        #expect(plan?.speech == Follow.simplerSpeech)
        #expect(plan?.steps == [])
        #expect(plan?.keptIDs == [])
    }
}
