import Foundation
import Testing
@testable import ZeusCore

enum ModelFixtures {
    static let session = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    static let sceneID = UUID(uuidString: "20000000-0000-4000-8000-000000000003")!
    static let turn = UUID(uuidString: "30000000-0000-4000-8000-000000000009")!
    static func scene(revision: Int = 0) -> ExplanationScene { .init(sessionID: session, sceneID: sceneID, revision: revision) }
    static func box(_ id: String, parent: String? = nil, shell: Bool = false) -> ExplanationPart {
        .init(id: id, parentID: parent, kind: .box, size: .init(x: 1, y: 1, z: 1), isShell: shell, accessibleDescription: "Box \(id)")
    }
    static func group(_ id: String, parent: String? = nil) -> ExplanationPart {
        .init(id: id, parentID: parent, kind: .group, accessibleDescription: "Group \(id)")
    }
    static func recipe(_ id: String, _ recipe: ExplanationPartRecipe, shell: Bool = false,
                       repeats: ExplanationPartRepeat? = nil, spin: Double? = nil) -> ExplanationPart {
        .init(id: id, kind: .recipe, recipe: recipe, isShell: shell, repeats: repeats,
              spin: spin.map { ExplanationPartSpin(radiansPerSecond: $0) }, accessibleDescription: "Recipe \(id)")
    }
    static func apply(_ operations: [ExplanationModelOperation], to scene: ExplanationScene) throws -> ExplanationScene {
        try ExplanationSceneReducer.applyingOperations(operations.map { ExplanationOperation.model($0) }, to: scene,
                                                       resultingRevision: scene.revision + 1)
    }
    static func line(_ operations: String, sequence: Int = 0) -> Data {
        Data("""
        {"version":1,"sessionID":"\(session)","turnID":"\(turn)","sceneID":"\(sceneID)","sequence":\(sequence),\
        "baseRevision":\(sequence),"revision":\(sequence + 1),"beatID":"b\(sequence)","speech":{"chunkID":"s\(sequence)",\
        "text":"Hello."},"cues":[{"id":"c0","anchor":{"kind":"start"},"operations":[\(operations)]}],"isFinal":true}
        """.utf8)
    }
}

@Suite struct ExplanationModelSchemaTests {
    private let good = """
    {"op":"part","part":{"id":"shell","kind":"recipe","recipe":"carShell","shell":true,"material":{"opacity":0.5},"accessibleDescription":"Car body"}},\
    {"op":"part","part":{"id":"wheels","kind":"recipe","recipe":"wheel","transform":{"position":{"x":0,"y":0.3,"z":-0.8},\
    "rotation":{"x":0,"y":0,"z":0},"scale":{"x":1,"y":1,"z":1}},"repeat":{"count":2,"offset":{"x":0,"y":0,"z":1.6}},\
    "spin":{"radiansPerSecond":-6},"accessibleDescription":"Wheels"}},\
    {"op":"path","path":{"id":"route","points":[{"x":0,"y":0,"z":0},{"x":1,"y":0,"z":0}]}},\
    {"op":"flow","flow":{"id":"energy","pathID":"route","speed":1}},\
    {"op":"callout","callout":{"id":"tag","text":"Shell","partID":"shell","anchor":{"x":0,"y":1,"z":0}}},\
    {"op":"view","preset":"side","orbit":30,"zoom":0.8},\
    {"op":"cutaway","expectedRevision":0,"style":"transparent","partIDs":["shell"],"opacity":0.1},\
    {"op":"model","caption":"Generic demo","animationRate":0.5},\
    {"op":"edit","id":"wheels","expectedRevision":0,"change":{"opacity":0.3,"spin":-3}}
    """

    @Test func goodPayloadDecodesAndRoundTrips() throws {
        let event = try ExplanationWire.decode(ModelFixtures.line(good))
        #expect(event.cues[0].operations.count == 9)
        let encoded = try ExplanationWire.encode(event)
        let again = try ExplanationWire.decode(encoded)
        #expect(again == event)
    }

    private func part(_ fields: String) -> String {
        #"{"op":"part","part":{"id":"p","accessibleDescription":"A part",\#(fields)}}"#
    }
    private let identityTransform = #"{"position":{"x":0,"y":0,"z":0},"rotation":{"x":0,"y":0,"z":0},"scale":{"x":SX,"y":1,"z":1}}"#

    @Test func badPayloadsAreRejected() {
        let longText = String(repeating: "a", count: 61)
        let manyIDs = (0..<25).map { "\"p\($0)\"" }.joined(separator: ",")
        let badScale = identityTransform.replacingOccurrences(of: "SX", with: "0")
        let farPosition = identityTransform.replacingOccurrences(of: "SX", with: "1")
            .replacingOccurrences(of: "\"x\":0,\"y\":0,\"z\":0},\"rotation", with: "\"x\":99999,\"y\":0,\"z\":0},\"rotation")
        let bad: [String] = [
            part(#""kind":"box""#),
            part(#""kind":"box","size":{"x":1,"y":1,"z":1},"url":"https://example.com""#),
            part(#""kind":"cylinder","radius":-1,"depth":1"#),
            part(#""kind":"cylinder","radius":1"#),
            part(#""kind":"sphere","radius":0"#),
            part(#""kind":"sphere","radius":1,"material":{"opacity":2}"#),
            part(#""kind":"sphere","radius":1,"material":{"metalness":-0.1}"#),
            part(#""kind":"sphere","radius":1,"transform":\#(badScale)"#),
            part(#""kind":"sphere","radius":1,"transform":\#(farPosition)"#),
            part(#""kind":"recipe","recipe":"wheel","repeat":{"count":17,"offset":{"x":0,"y":0,"z":1}}"#),
            part(#""kind":"recipe","recipe":"wheel","repeat":{"count":0,"offset":{"x":0,"y":0,"z":1}}"#),
            part(#""kind":"recipe","recipe":"wheel","spin":{"radiansPerSecond":61}"#),
            part(#""kind":"sphere","radius":1,"spin":{"radiansPerSecond":1}"#),
            part(#""kind":"group","size":{"x":1,"y":1,"z":1}"#),
            part(#""kind":"recipe""#),
            part(#""kind":"recipe","recipe":"teapot""#),
            part(#""kind":"teleporter""#),
            #"{"op":"part","part":{"id":"has space","kind":"group","accessibleDescription":"A"}}"#,
            #"{"op":"path","path":{"id":"r","points":[{"x":0,"y":0,"z":0}]}}"#,
            #"{"op":"path","path":{"id":"r","points":[{"x":1,"y":0,"z":0},{"x":1,"y":0,"z":0}]}}"#,
            #"{"op":"flow","flow":{"id":"f","pathID":"r","speed":1,"count":25}}"#,
            #"{"op":"flow","flow":{"id":"f","pathID":"r","speed":21}}"#,
            #"{"op":"flow","flow":{"id":"f","pathID":"r","speed":-1}}"#,
            #"{"op":"flow","flow":{"id":"f","pathID":"r","speed":1,"markerSize":0.9}}"#,
            #"{"op":"flow","flow":{"id":"f","pathID":"r","speed":1,"direction":"sideways"}}"#,
            #"{"op":"callout","callout":{"id":"c","text":""}}"#,
            #"{"op":"callout","callout":{"id":"c","text":"\#(longText)"}}"#,
            #"{"op":"view"}"#, #"{"op":"view","zoom":6}"#, #"{"op":"view","orbit":900}"#,
            #"{"op":"view","preset":"underneath"}"#, #"{"op":"view","orbit":1,"orbit":2}"#,
            #"{"op":"model"}"#, #"{"op":"model","animationRate":5}"#, #"{"op":"model","animationRate":0.01}"#,
            #"{"op":"model","caption":""}"#,
            #"{"op":"cutaway","expectedRevision":0,"style":"hide","partIDs":[]}"#,
            #"{"op":"cutaway","expectedRevision":-1,"style":"hide","partIDs":["a"]}"#,
            #"{"op":"cutaway","expectedRevision":0,"style":"hide","partIDs":[\#(manyIDs)]}"#,
            #"{"op":"edit","id":"x","expectedRevision":0,"change":{}}"#,
            #"{"op":"edit","id":"x","change":{"opacity":0.5}}"#,
            #"{"op":"edit","id":"x","expectedRevision":0,"change":{"opacity":1.5}}"#,
            #"{"op":"edit","id":"x","expectedRevision":0,"change":{"mass":3}}"#,
            #"{"op":"edit","id":"x","expectedRevision":0,"change":{"scale":{"x":0,"y":1,"z":1}}}"#,
            #"{"op":"teleport","id":"x"}"#, #"{"op":"part"}"#
        ]
        for operations in bad {
            #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(ModelFixtures.line(operations)) }
        }
    }

    @Test func oversizedPayloadIsRejectedBeforeParsing() {
        let huge = part(#""kind":"group","accessibleDescription2":"x""#)
            + String(repeating: " ", count: 70_000)
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(ModelFixtures.line(huge)) }
    }

    @Test func excessiveObjectCountsAreRejected() throws {
        let ninetySix = (0..<96).map { ExplanationModelOperation.part(ModelFixtures.box("b\($0)")) }
        let full = try ModelFixtures.apply(ninetySix, to: ModelFixtures.scene())
        #expect(full.model?.parts.count == 96)
        let tooMany = (0..<97).map { ExplanationModelOperation.part(ModelFixtures.box("b\($0)")) }
        #expect(throws: ExplanationFailure.self) { try ModelFixtures.apply(tooMany, to: ModelFixtures.scene()) }

        let sixteen = ExplanationPartRepeat(count: 16, offset: .init(x: 0, y: 0, z: 1))
        func gears(_ count: Int) -> [ExplanationModelOperation] {
            (0..<count).map { .part(ModelFixtures.recipe("g\($0)", .reductionGear, repeats: sixteen)) }
        }
        let twoGears = try ModelFixtures.apply(gears(2), to: ModelFixtures.scene())
        #expect(twoGears.model?.parts.count == 2)
        #expect(throws: ExplanationFailure.self) { try ModelFixtures.apply(gears(3), to: ModelFixtures.scene()) }

        func boxes(_ count: Int) -> [ExplanationModelOperation] {
            (0..<count).map { var part = ModelFixtures.box("r\($0)"); part.repeats = sixteen; return .part(part) }
        }
        let tenRepeated = try ModelFixtures.apply(boxes(10), to: ModelFixtures.scene())
        #expect(tenRepeated.model?.parts.count == 10)
        #expect(throws: ExplanationFailure.self) { try ModelFixtures.apply(boxes(11), to: ModelFixtures.scene()) }

        var flowOps: [ExplanationModelOperation] = [.path(.init(id: "route", points: [.zero, .init(x: 1, y: 0, z: 0)]))]
        for index in 0..<5 { flowOps.append(.flow(.init(id: "f\(index)", pathID: "route", speed: 1, count: 24))) }
        #expect(throws: ExplanationFailure.self) { try ModelFixtures.apply(flowOps, to: ModelFixtures.scene()) }
        flowOps.removeLast()
        let fine = try ModelFixtures.apply(flowOps, to: ModelFixtures.scene())
        #expect(fine.model?.flows.count == 4)
    }

    @Test func graphRulesRejectBrokenReferences() throws {
        let scene = ModelFixtures.scene()
        let clash: [ExplanationModelOperation] = [.part(ModelFixtures.box("x")), .callout(.init(id: "x", text: "Label"))]
        #expect(throws: ExplanationFailure.self) { try ModelFixtures.apply(clash, to: scene) }
        let noShell: [ExplanationModelOperation] = [.part(ModelFixtures.box("body")),
            .cutaway(.init(expectedRevision: 0, style: .hide, partIDs: ["body"]))]
        #expect(throws: ExplanationFailure.self) { try ModelFixtures.apply(noShell, to: scene) }
        #expect(throws: ExplanationFailure.self) {
            try ModelFixtures.apply([.flow(.init(id: "f", pathID: "nowhere", speed: 1))], to: scene)
        }
        #expect(throws: ExplanationFailure.self) {
            try ModelFixtures.apply([.part(ModelFixtures.box("a")), .part(ModelFixtures.box("b", parent: "a"))], to: scene)
        }
        let cycle: [ExplanationModelOperation] = [.part(ModelFixtures.group("g1", parent: "g2")), .part(ModelFixtures.group("g2", parent: "g1"))]
        #expect(throws: ExplanationFailure.self) { try ModelFixtures.apply(cycle, to: scene) }
        var spinning = ModelFixtures.box("spinner")
        spinning.spin = .init(radiansPerSecond: 1)
        #expect(throws: ExplanationFailure.self) { try ModelFixtures.apply([.part(spinning)], to: scene) }
        let nested: [ExplanationModelOperation] = [.part(ModelFixtures.group("g")), .part(ModelFixtures.box("child", parent: "g"))]
        let ok = try ModelFixtures.apply(nested, to: scene)
        #expect(ok.model?.parts["child"]?.parentID == "g")
    }

    @Test func sceneStaysCompatibleWithSavedScenesWithoutAModel() throws {
        let plain = ModelFixtures.scene()
        let data = try JSONEncoder().encode(plain)
        #expect(try JSONDecoder().decode(ExplanationScene.self, from: data) == plain)
        let withModel = try ModelFixtures.apply([.part(ModelFixtures.box("b"))], to: plain)
        let saved = try JSONEncoder().encode(withModel)
        #expect(try JSONDecoder().decode(ExplanationScene.self, from: saved) == withModel)
        #expect(withModel.hasModel3D)
        #expect(!plain.hasModel3D)
    }
}
