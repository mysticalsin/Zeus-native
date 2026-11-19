import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplanationReducerTests {
    @Test func invalidTransactionsAreAtomicAndCannotConcealInvalidObjects() throws {
        let scene = ExplanationProtocolFixtures.scene()
        let operations: [ExplanationOperation] = [.create(ExplanationProtocolFixtures.point()), .move(id: "missing", position: .zero)]
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.applyingOperations(operations, to: scene, resultingRevision: 1) }
        #expect(scene.objects.isEmpty && scene.revision == 0)
        var invalid = ExplanationProtocolFixtures.point(); invalid.geometry.radius = -1
        #expect(throws: ExplanationFailure.self) {
            try ExplanationSceneReducer.applyingOperations([.create(invalid), .clear], to: scene, resultingRevision: 1)
        }
        var unapproved = ExplanationProtocolFixtures.point(); unapproved.sourceIDs = ["private-source"]
        #expect(throws: ExplanationFailure.self) {
            try ExplanationSceneReducer.applyingOperations([.create(unapproved), .clear], to: scene, resultingRevision: 1)
        }
    }

    @Test func stableIDsReferencesAndParentCyclesAreValidated() throws {
        let point = ExplanationProtocolFixtures.point()
        let other = ExplanationProtocolFixtures.point("other")
        let connector = ExplanationObject(id: "link", geometry: .init(kind: .connector, fromID: point.id, toID: other.id), accessibleDescription: "Connection")
        let scene = try ExplanationSceneReducer.applyingOperations([.connect(connector), .create(point), .create(other)], to: ExplanationProtocolFixtures.scene(), resultingRevision: 1)
        #expect(scene.objects.count == 3)
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.applyingOperations([.create(point)], to: scene, resultingRevision: 2) }
        let removed = try ExplanationSceneReducer.applyingOperations([.remove(id: point.id)], to: scene, resultingRevision: 2)
        #expect(removed.objects.keys.sorted() == [other.id])
        let a = ExplanationObject(id: "a", parentID: "b", geometry: .init(kind: .group), accessibleDescription: "Group A")
        let b = ExplanationObject(id: "b", parentID: "a", geometry: .init(kind: .group), accessibleDescription: "Group B")
        #expect(throws: ExplanationFailure.self) {
            try ExplanationSceneReducer.applyingOperations([.create(a), .create(b)], to: ExplanationProtocolFixtures.scene(), resultingRevision: 1)
        }
        var missing = point; missing.parentID = "missing"
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.applyingOperations([.create(missing)], to: ExplanationProtocolFixtures.scene(), resultingRevision: 1) }
    }

    @Test func manualRevisionAndSessionIdentityRejectLateModelEdits() throws {
        let event = ExplanationProtocolFixtures.event()
        let initial = ExplanationProtocolFixtures.scene()
        let committed = try ExplanationSceneReducer.applying(event, to: initial, activeTurn: event.turnID)
        let manual = try ExplanationSceneReducer.applyingOperations([.move(id: "point", position: .init(x: 4, y: 5))], to: committed, resultingRevision: 2)
        #expect(throws: ExplanationFailure.revisionConflict) { try ExplanationSceneReducer.applying(event, to: manual, activeTurn: event.turnID) }
        #expect(throws: ExplanationFailure.staleIdentity) { try ExplanationSceneReducer.applying(event, to: initial, activeTurn: UUID()) }
        var stale = event; stale.sessionID = UUID()
        #expect(throws: ExplanationFailure.staleIdentity) { try ExplanationSceneReducer.applying(stale, to: initial, activeTurn: event.turnID) }
        #expect(manual.objects["point"]?.transform.position == .init(x: 4, y: 5))
        let undone = try ExplanationSceneReducer.restoring(committed, over: manual)
        #expect(undone.revision == 3 && undone.objects["point"]?.transform.position == .zero)
        #expect(throws: ExplanationFailure.revisionConflict) { try ExplanationSceneReducer.restoring(manual, atRevision: 0) }
    }

    @Test func cueSubsetsAndSpokenOnlyBeatsHaveExplicitRevisionAdmission() throws {
        let initial = ExplanationProtocolFixtures.scene()
        let first = try ExplanationSceneReducer.applyingOperations([.create(ExplanationProtocolFixtures.point())], to: initial, resultingRevision: 1)
        let next = try ExplanationSceneReducer.applyingOperations([.recolor(id: "point", color: .green)], to: first, resultingRevision: 1)
        #expect(next.revision == 1 && next.objects["point"]?.style.fill == .green)
        #expect(first.objects["point"]?.style.fill == .blue)
        var spoken = ExplanationProtocolFixtures.event(); spoken.cues = []
        let empty = try ExplanationSceneReducer.applying(spoken, to: initial, activeTurn: spoken.turnID)
        #expect(empty.objects.isEmpty && empty.revision == 1)
    }

    @Test func assetRegistryAndCaptureIdentityAreNeverInferredFromModelObjects() throws {
        let asset = ExplanationObject(id: "photo", geometry: .init(kind: .image, size: .init(x: 20, y: 20)),
                                      accessibleDescription: "User supplied reference photo", assetID: "approved-photo",
                                      sourceIDs: ["approved-source"], provenance: .userProvided)
        let initial = ExplanationProtocolFixtures.scene()
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.applyingOperations([.create(asset)], to: initial, resultingRevision: 1) }
        let registry = ExplanationRegistry(assetIDs: ["approved-photo"], sourceIDs: ["approved-source"])
        let withAsset = try ExplanationSceneReducer.applyingOperations([.create(asset)], to: initial, resultingRevision: 1, registry: registry)
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.restoring(withAsset, atRevision: 2) }
        var captured = initial; captured.captureID = UUID()
        var point = ExplanationProtocolFixtures.point(); point.space = .capture; point.captureID = captured.captureID
        _ = try ExplanationSceneReducer.applyingOperations([.create(point)], to: captured, resultingRevision: 1)
        point.captureID = UUID()
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.applyingOperations([.create(point)], to: captured, resultingRevision: 1) }
    }

    @Test func safe3DLabelsMeshesAndGeometryBudgetsRejectDangerousShapes() throws {
        let label = ExplanationObject(id: "world-label", space: .world, geometry: .init(kind: .label), text: "Axis", accessibleDescription: "Axis label")
        try ExplanationSceneReducer.validate(.create(label))
        let box = ExplanationObject(id: "box", space: .world, geometry: .init(kind: .box, size: .init(x: 2, y: 3, z: 4)), accessibleDescription: "Box")
        try ExplanationSceneReducer.validate(.create(box))
        var mesh = ExplanationObject(id: "mesh", space: .world,
                                     geometry: .init(kind: .mesh, vertices: [.zero, .init(x: 1, y: 0), .init(x: 0, y: 1)], indices: [0, 1, 2]), accessibleDescription: "Triangle")
        try ExplanationSceneReducer.validate(.create(mesh))
        mesh.geometry.indices = [0, 1, 99]
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(.create(mesh)) }
        mesh.geometry.indices = [0, 1, 2]; mesh.geometry.vertices?[2] = .init(x: 2, y: 0)
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(.create(mesh)) }
        var point = ExplanationProtocolFixtures.point(); point.geometry.points = [.zero, .one]
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(.create(point)) }
        let crowded = (0...ExplanationLimits.objects).map { ExplanationOperation.create(ExplanationProtocolFixtures.point("p-\($0)")) }
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.applyingOperations(crowded, to: ExplanationProtocolFixtures.scene(), resultingRevision: 1) }
        var full = ExplanationProtocolFixtures.scene()
        full.objects = Dictionary(uniqueKeysWithValues: (0..<ExplanationLimits.objects).map { ("p-\($0)", ExplanationProtocolFixtures.point("p-\($0)")) })
        try ExplanationSceneReducer.validate(full)
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.applyingOperations([.create(ExplanationProtocolFixtures.point("overflow"))], to: full, resultingRevision: 1) }
    }

    @Test func malformedPatchCannotBeHiddenByLaterClearAndAnimationsHaveFiniteEndpoints() throws {
        let scene = try ExplanationSceneReducer.applying(ExplanationProtocolFixtures.event(), to: ExplanationProtocolFixtures.scene(), activeTurn: ExplanationProtocolFixtures.turn)
        let patch = ExplanationObjectPatch(geometry: .init(kind: .sphere, radius: 2))
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.applyingOperations([.update(id: "point", patch: patch), .clear], to: scene, resultingRevision: 2) }
        let revealed = try ExplanationSceneReducer.applyingOperations([.animate(id: "point", animation: .init(property: .strokeReveal, to: .init(x: 0.5, y: 0), duration: 0))], to: scene, resultingRevision: 2)
        #expect(revealed.objects["point"]?.reveal == 0.5)
        #expect(throws: ExplanationFailure.self) {
            try ExplanationSceneReducer.applyingOperations([.move(id: "point", position: .one), .clear], to: scene, resultingRevision: 2)
        }
    }

    @Test func projectedEventsValidateEveryVisibleCueBoundary() throws {
        let connector = ExplanationObject(id: "link", geometry: .init(kind: .connector, fromID: "a", toID: "b"), accessibleDescription: "Connection")
        var event = ExplanationProtocolFixtures.event()
        event.cues = [.init(id: "early", operations: [.connect(connector)]),
                      .init(id: "late", anchor: .end, operations: [.create(ExplanationProtocolFixtures.point("a")), .create(ExplanationProtocolFixtures.point("b"))])]
        #expect(throws: ExplanationFailure.self) {
            try ExplanationSceneReducer.applying(event, to: ExplanationProtocolFixtures.scene(), activeTurn: event.turnID)
        }
        event.cues.reverse(); event.cues[0].anchor = .start; event.cues[1].anchor = .end
        let valid = try ExplanationSceneReducer.applying(event, to: ExplanationProtocolFixtures.scene(), activeTurn: event.turnID)
        #expect(valid.objects.count == 3 && valid.revision == 1)
    }

    @Test func individuallyFiniteNestedTransformsCannotOverflowNativeMatrices() throws {
        var scene = ExplanationProtocolFixtures.scene()
        var parent: String?
        for index in 0..<5 {
            let group = ExplanationObject(id: "g-\(index)", parentID: parent, space: .world,
                geometry: .init(kind: .group), transform: .init(scale: .init(x: 100, y: 100, z: 100)),
                accessibleDescription: "Nested group")
            scene.objects[group.id] = group; parent = group.id
        }
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(scene) }
        for id in scene.objects.keys { scene.objects[id]?.transform.scale = .init(x: 2, y: 2, z: 2) }
        try ExplanationSceneReducer.validate(scene)
        for id in scene.objects.keys { scene.objects[id]?.transform.scale = .init(x: 0.001, y: 0.001, z: 0.001) }
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(scene) }
    }
}
