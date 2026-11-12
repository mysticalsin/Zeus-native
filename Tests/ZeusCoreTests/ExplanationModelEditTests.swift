import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplanationModelEditTests {
    private func base() throws -> ExplanationScene {
        let ops: [ExplanationModelOperation] = [
            .part(ModelFixtures.recipe("shell", .carShell, shell: true)),
            .part(ModelFixtures.recipe("battery", .batteryPack)),
            .part(ModelFixtures.recipe("wheels", .wheel, repeats: .init(count: 2, offset: .init(x: 0, y: 0, z: 1.6)), spin: -6)),
            .part(ModelFixtures.box("plain")),
            .path(.init(id: "route", points: [.zero, .init(x: 2, y: 0, z: 0)])),
            .flow(.init(id: "energy", pathID: "route", speed: 1)),
            .callout(.init(id: "tag", text: "Battery", partID: "battery", anchor: .init(x: 0, y: 0.5, z: 0)))
        ]
        return try ModelFixtures.apply(ops, to: ModelFixtures.scene())
    }
    private func edit(_ id: String, _ revision: Int, _ change: ExplanationPartChange) -> ExplanationModelOperation {
        .edit(.init(id: id, expectedRevision: revision, change: change))
    }

    @Test func editChangesTheSamePartAndNeverStacksADuplicate() throws {
        let scene = try base()
        let edited = try ModelFixtures.apply([edit("battery", scene.revision, .init(opacity: 0.3, color: .green))], to: scene)
        #expect(edited.model?.parts.count == scene.model?.parts.count)
        #expect(edited.model?.parts["battery"]?.material.opacity == 0.3)
        #expect(edited.model?.parts["battery"]?.material.color == .green)
        #expect(edited.revision == scene.revision + 1)
        #expect(scene.model?.parts["battery"]?.material.opacity == 1)
        #expect(throws: ExplanationFailure.self) {
            try ModelFixtures.apply([.part(ModelFixtures.recipe("battery", .batteryPack))], to: scene)
        }
    }

    @Test func missingTargetIsRejectedAndTheLastValidSceneIsKept() throws {
        let scene = try base()
        let before = scene
        let expected = ExplanationFailure.editRejected(.missingTarget("ghost"))
        #expect(throws: expected) { try ModelFixtures.apply([edit("ghost", scene.revision, .init(opacity: 0.5))], to: scene) }
        #expect(scene == before)
        let mixed: [ExplanationModelOperation] = [edit("battery", scene.revision, .init(opacity: 0.3)),
                                                  edit("ghost", scene.revision, .init(opacity: 0.5))]
        #expect(throws: expected) { try ModelFixtures.apply(mixed, to: scene) }
        #expect(scene.model?.parts["battery"]?.material.opacity == 1)
        let later = try ModelFixtures.apply([edit("battery", scene.revision, .init(opacity: 0.4))], to: scene)
        #expect(later.model?.parts["battery"]?.material.opacity == 0.4)
        #expect(throws: ExplanationFailure.editRejected(.missingTarget("nowhere"))) {
            try ModelFixtures.apply([.cutaway(.init(expectedRevision: scene.revision, style: .hide, partIDs: ["nowhere"]))], to: scene)
        }
    }

    @Test func staleRevisionIsRejectedAndTheLastValidSceneIsKept() throws {
        let scene = try base()
        let before = scene
        let stale = ExplanationFailure.editRejected(.staleRevision(expected: scene.revision - 1, actual: scene.revision))
        #expect(throws: stale) { try ModelFixtures.apply([edit("battery", scene.revision - 1, .init(opacity: 0.5))], to: scene) }
        #expect(scene == before)
        let future = ExplanationFailure.editRejected(.staleRevision(expected: scene.revision + 5, actual: scene.revision))
        #expect(throws: future) {
            try ModelFixtures.apply([.cutaway(.init(expectedRevision: scene.revision + 5, style: .hide, partIDs: ["shell"]))], to: scene)
        }
        #expect(ExplanationFailure.editRejected(.missingTarget("x")).errorDescription != nil)
    }

    @Test func staleEditInsideAnEventFailsTheWholeProjection() throws {
        let scene = try base()
        func event(expected: Int) -> ExplanationEvent {
            .init(sessionID: scene.sessionID, turnID: ModelFixtures.turn, sceneID: scene.sceneID, sequence: 0,
                  baseRevision: scene.revision, revision: scene.revision + 1, beatID: "b0",
                  speech: .init(chunkID: "s0", text: "Change the battery."),
                  cues: [.init(id: "c0", operations: [.model(edit("battery", expected, .init(opacity: 0.2)))])], isFinal: true)
        }
        let applied = try ExplanationSceneReducer.applying(event(expected: scene.revision), to: scene, activeTurn: ModelFixtures.turn)
        #expect(applied.model?.parts["battery"]?.material.opacity == 0.2)
        let stale = ExplanationFailure.editRejected(.staleRevision(expected: 0, actual: scene.revision))
        #expect(throws: stale) { try ExplanationSceneReducer.applying(event(expected: 0), to: scene, activeTurn: ModelFixtures.turn) }
        var presentation = try ExplanationPresentation(scene: scene)
        let staleEvent = event(expected: 0)
        try presentation.begin(staleEvent)
        var failure: ExplanationFailure?
        do { try presentation.apply(.init(event: staleEvent, cueIndex: 0, presentationTime: 0, remainingMediaDuration: 2)) }
        catch let error as ExplanationFailure { failure = error }
        catch { Issue.record("unexpected error \(error)") }
        #expect(failure == stale)
        #expect(presentation.targetScene.model?.parts["battery"]?.material.opacity == 1)
    }

    @Test func changesThatDoNotApplyToTheTargetKindAreRejected() throws {
        let scene = try base()
        func rejected(_ id: String, _ change: ExplanationPartChange, field: String) {
            #expect(throws: ExplanationFailure.editRejected(.inapplicableChange(field))) {
                try ModelFixtures.apply([edit(id, scene.revision, change)], to: scene)
            }
        }
        rejected("battery", .init(speed: 2), field: "speed")
        rejected("battery", .init(direction: .reverse), field: "direction")
        rejected("plain", .init(spin: 1), field: "spin")
        rejected("energy", .init(opacity: 0.5), field: "opacity")
        rejected("tag", .init(color: .red), field: "color")
    }

    @Test func flowAndCalloutEditsKeepTheirIdentity() throws {
        let scene = try base()
        let ops = [edit("energy", scene.revision, .init(color: .green, speed: 2, direction: .reverse, active: false)),
                   edit("tag", scene.revision, .init(visible: false, text: "Battery (charging)")),
                   edit("wheels", scene.revision, .init(spin: -2))]
        let result = try ModelFixtures.apply(ops, to: scene)
        #expect(result.model?.flows["energy"]?.direction == .reverse)
        #expect(result.model?.flows["energy"]?.speed == 2 && result.model?.flows["energy"]?.active == false)
        #expect(result.model?.callouts["tag"]?.text == "Battery (charging)" && result.model?.callouts["tag"]?.visible == false)
        #expect(result.model?.parts["wheels"]?.spin?.radiansPerSecond == -2)
        #expect(result.model?.flows.count == 1 && result.model?.callouts.count == 1)
    }

    @Test func cutawayHidesOrFadesOnlyTheNamedShell() throws {
        let scene = try base()
        let faded = try ModelFixtures.apply([.cutaway(.init(expectedRevision: scene.revision, style: .transparent,
                                                            partIDs: ["shell"], opacity: 0.1))], to: scene)
        let model = try #require(faded.model)
        let shell = try #require(ExplanationModelAppearance.appearance(of: "shell", in: model))
        #expect(shell.visible && shell.opacity <= 0.1)
        #expect(ExplanationModelAppearance.appearance(of: "battery", in: model) == .init(visible: true, opacity: 1))
        let hidden = try ModelFixtures.apply([.cutaway(.init(expectedRevision: faded.revision, style: .hide, partIDs: ["shell"]))], to: faded)
        #expect(hidden.model.flatMap { ExplanationModelAppearance.appearance(of: "shell", in: $0) }?.visible == false)
        let restored = try ModelFixtures.apply([.cutaway(.init(expectedRevision: hidden.revision, style: .none, partIDs: []))], to: hidden)
        #expect(restored.model.flatMap { ExplanationModelAppearance.appearance(of: "shell", in: $0) } == .init(visible: true, opacity: 1))
    }

    @Test func groupsPassVisibilityAndOpacityToChildren() throws {
        let ops: [ExplanationModelOperation] = [.part(ModelFixtures.group("g")), .part(ModelFixtures.box("child", parent: "g"))]
        let scene = try ModelFixtures.apply(ops, to: ModelFixtures.scene())
        let hidden = try ModelFixtures.apply([edit("g", scene.revision, .init(visible: false))], to: scene)
        #expect(hidden.model.flatMap { ExplanationModelAppearance.appearance(of: "child", in: $0) }?.visible == false)
        let faint = try ModelFixtures.apply([edit("g", scene.revision, .init(opacity: 0.5))], to: scene)
        #expect(faint.model.flatMap { ExplanationModelAppearance.appearance(of: "child", in: $0) }?.opacity == 0.5)
    }

    @Test func viewOperationOrbitsPresetsAndZoomsTheCamera() throws {
        let scene = ModelFixtures.scene()
        let start = scene.camera
        func distance(_ c: ExplanationCamera) -> Double { ExplanationV3.length(ExplanationV3.sub(c.position, c.target)) }
        let quarter = try ModelFixtures.apply([.view(.init(orbit: 90))], to: scene)
        #expect(abs(quarter.camera.position.x - 8) < 1e-9 && abs(quarter.camera.position.z) < 1e-9)
        #expect(abs(quarter.camera.position.y - start.position.y) < 1e-9)
        let full = try ModelFixtures.apply([.view(.init(orbit: 360))], to: scene)
        #expect(abs(full.camera.position.x - start.position.x) < 1e-9 && abs(full.camera.position.z - start.position.z) < 1e-9)
        let side = try ModelFixtures.apply([.view(.init(preset: .side))], to: scene)
        #expect(abs(distance(side.camera) - distance(start)) < 1e-9 && side.camera.position.z > 7)
        let closer = try ModelFixtures.apply([.view(.init(zoom: 0.5))], to: scene)
        #expect(abs(distance(closer.camera) - distance(start) / 2) < 1e-9)
        let inside = try ModelFixtures.apply([.view(.init(preset: .inside))], to: scene)
        #expect(distance(inside.camera) < distance(start))
    }

    @Test func slowingDownChangesOnlyTheRateAndClearRemovesTheModel() throws {
        let scene = try base()
        let slow = try ModelFixtures.apply([.settings(.init(animationRate: 0.4))], to: scene)
        #expect(slow.model?.animationRate == 0.4)
        #expect(slow.model?.parts == scene.model?.parts && slow.model?.flows == scene.model?.flows)
        #expect(throws: ExplanationFailure.self) { try ModelFixtures.apply([.settings(.init(animationRate: 9))], to: scene) }
        let cleared = try ExplanationSceneReducer.applyingOperations([.clear], to: scene, resultingRevision: scene.revision + 1)
        #expect(cleared.model == nil)
    }
}
