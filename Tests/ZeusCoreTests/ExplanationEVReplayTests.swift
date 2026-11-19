import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplanationEVReplayTests {
    private func lines() throws -> [ExplanationEvent] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("docs/examples/visual-explanation/ev-drivetrain.ndjson"))
        return try data.split(separator: 10).map { try ExplanationWire.decode(Data($0)) }
    }

    /// Replays one turn event by event, the way playback admits cues, and returns the scene after each beat.
    private func replay(_ events: [ExplanationEvent], from start: ExplanationScene) throws -> [ExplanationScene] {
        var scene = start, result: [ExplanationScene] = []
        for event in events {
            scene = try ExplanationSceneReducer.applying(event, to: scene, activeTurn: event.turnID)
            result.append(scene)
        }
        return result
    }

    @Test func theFixtureDecodesIntoTheBuildTurnAndFourFollowUps() throws {
        let events = try lines()
        #expect(events.count == 9)
        #expect(Set(events.map(\.turnID)).count == 5)
        #expect(events.prefix(5).map(\.sequence) == [0, 1, 2, 3, 4])
        #expect(events[4].isFinal && events.dropFirst(5).allSatisfy { $0.sequence == 0 && $0.isFinal })
        #expect(events.allSatisfy { !$0.speech.text.contains("\u{2014}") })
    }

    @Test func eachBeatLeavesTheExpectedScene() throws {
        let events = try lines()
        let start = ExplanationScene(sessionID: events[0].sessionID, sceneID: events[0].sceneID)
        let scenes = try replay(Array(events.prefix(5)), from: start)
        #expect(scenes.map(\.revision) == [1, 2, 3, 4, 5])
        func parts(_ i: Int) -> [String] { scenes[i].model?.parts.keys.sorted() ?? [] }
        #expect(parts(0) == ["battery", "shell"])
        #expect(parts(1) == ["battery", "inverter", "shell"])
        #expect(parts(2) == ["battery", "inverter", "motor", "reduction", "shell"])
        #expect(parts(3) == ["battery", "half-shafts", "inverter", "motor", "reduction", "shell", "wheels-front", "wheels-rear"])
        #expect(parts(4) == parts(3))
        #expect(scenes[0].model?.caption == "Generic EV, explanatory animation, not an engineering simulation")
        #expect(scenes[1].model?.flows.isEmpty == true && scenes[2].model?.flows.count == 1)
        #expect(scenes[0].camera.position == ExplanationVector3(x: 4.6, y: 2.4, z: 5.6))
        // Propulsion, then regeneration reverses the same flow in place.
        #expect(scenes[3].model?.flows["energy"]?.direction == .forward)
        #expect(scenes[4].model?.flows["energy"]?.direction == .reverse)
        #expect(scenes[4].model?.flows["energy"]?.color == .green)
        #expect(scenes[4].model?.flows.count == 1)
        #expect(scenes[4].model?.callouts["battery-label"]?.text == "Battery pack (charging)")
        #expect(scenes[4].model?.callouts.count == scenes[3].model?.callouts.count)
    }

    @Test func spinsAreConsistentWithAGeneratorMotorAndRollingWheels() throws {
        let events = try lines()
        let start = ExplanationScene(sessionID: events[0].sessionID, sceneID: events[0].sceneID)
        let model = try #require(try replay(Array(events.prefix(5)), from: start).last?.model)
        let wheel = try #require(model.parts["wheels-rear"]?.spin?.radiansPerSecond)
        let rolling = ExplanationRolling.spinRate(travel: .init(x: 2, y: 0, z: 0), axle: .z, radius: 0.33)
        #expect(wheel < 0 && rolling < 0)
        #expect(model.parts["half-shafts"]?.spin?.radiansPerSecond == wheel)
        let motor = try #require(model.parts["motor"]?.spin?.radiansPerSecond)
        let gear = try #require(model.parts["reduction"]?.spin?.radiansPerSecond)
        #expect(motor == gear)
        #expect(abs(gear * ExplanationRecipes.reductionOutputFactor - wheel) < 1e-9)
    }

    @Test func followUpsEditTheSameSceneByIdAndNeverDuplicate() throws {
        let events = try lines()
        let start = ExplanationScene(sessionID: events[0].sessionID, sceneID: events[0].sceneID)
        var scene = try #require(try replay(Array(events.prefix(5)), from: start).last)
        let built = scene
        var checkpoints: [ExplanationScene] = []
        for event in events.dropFirst(5) {
            // The app reserves a new revision before each follow-up turn.
            let reserved = try ExplanationSceneReducer.restoring(scene, atRevision: scene.revision + 1)
            #expect(event.baseRevision == reserved.revision)
            scene = try ExplanationSceneReducer.applying(event, to: reserved, activeTurn: event.turnID)
            checkpoints.append(scene)
        }
        #expect(checkpoints.map(\.revision) == [7, 9, 11, 13])
        #expect(checkpoints.allSatisfy { $0.model?.parts.count == built.model?.parts.count })
        #expect(checkpoints.allSatisfy { $0.model?.flows.count == 1 && $0.model?.callouts.count == built.model?.callouts.count })
        #expect(checkpoints[0].camera != built.camera && checkpoints[0].model == built.model)
        #expect(checkpoints[1].model?.cutaway.style == .transparent && checkpoints[1].model?.cutaway.partIDs == ["shell"])
        #expect(checkpoints[2].model?.parts["wheels-rear"]?.material.opacity == 0.25)
        #expect(checkpoints[2].model?.parts["wheels-front"]?.material.opacity == 1)
        #expect(checkpoints[3].model?.animationRate == 0.4)
        #expect(checkpoints[3].model?.parts == checkpoints[2].model?.parts)
    }

    @Test func aStaleFollowUpAgainstTheBuiltSceneIsRejected() throws {
        let events = try lines()
        let start = ExplanationScene(sessionID: events[0].sessionID, sceneID: events[0].sceneID)
        let built = try #require(try replay(Array(events.prefix(5)), from: start).last)
        let reserved = try ExplanationSceneReducer.restoring(built, atRevision: built.revision + 1)
        // The transparency follow-up was written for revision 10, so it is stale at revision 6.
        var failure: ExplanationFailure?
        do {
            var late = events[7]
            late.baseRevision = reserved.revision; late.revision = reserved.revision + 1
            _ = try ExplanationSceneReducer.applying(late, to: reserved, activeTurn: late.turnID)
        } catch let error as ExplanationFailure { failure = error } catch { Issue.record("unexpected \(error)") }
        #expect(failure == .editRejected(.staleRevision(expected: 10, actual: 6)))
    }

    @Test func theFixtureStaysInsideTheSceneBudgets() throws {
        let events = try lines()
        let start = ExplanationScene(sessionID: events[0].sessionID, sceneID: events[0].sceneID)
        let model = try #require(try replay(Array(events.prefix(5)), from: start).last?.model)
        let solids = model.parts.values.reduce(0) { $0 + ExplanationRecipes.primitiveCount(of: $1) }
        #expect(solids == 116 && solids < ExplanationModelLimits.primitives)
        for event in events { #expect(try ExplanationWire.encode(event).count < ExplanationLimits.frameBytes / 8) }
    }
}
