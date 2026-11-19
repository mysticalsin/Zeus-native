import Foundation
import Testing
@testable import ZeusCore

enum ExplanationProtocolFixtures {
    static let session = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let turn = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    static let sceneID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    static func scene() -> ExplanationScene { .init(sessionID: session, sceneID: sceneID) }
    static func point(_ id: String = "point") -> ExplanationObject {
        .init(id: id, geometry: .init(kind: .point, radius: 4), accessibleDescription: "A point")
    }
    static func event(sequence: Int = 0, base: Int = 0, operations: [ExplanationOperation]? = nil,
                      final: Bool = true) -> ExplanationEvent {
        .init(sessionID: session, turnID: turn, sceneID: sceneID, sequence: sequence,
              baseRevision: base, revision: base + 1, beatID: "beat-\(sequence)",
              speech: .init(chunkID: "speech-\(sequence)", text: "Here is a point."),
              cues: [.init(id: "cue-\(sequence)", operations: operations ?? [.create(point())])], isFinal: final)
    }
    static func line(_ event: ExplanationEvent) throws -> Data {
        var result = try ExplanationWire.encode(event); result.append(10); return result
    }
}

@Suite struct ExplanationProtocolTests {
    @Test func safeWireRoundTripsAndSeparatesAppAudioMetadata() throws {
        let event = ExplanationProtocolFixtures.event()
        let encoded = try ExplanationWire.encode(event)
        #expect(try ExplanationWire.decode(encoded) == event)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("audioRef"))
        let audio = ExplanationAudioChunk(sessionID: event.sessionID, turnID: event.turnID,
                                         sceneID: event.sceneID, beatID: event.beatID,
                                         chunkID: event.speech.chunkID, duration: 1.25, sampleRate: 24_000,
                                         alignment: [.init(wordIndex: 0, start: 0, end: 0.2)])
        try ExplanationSceneReducer.validate(audio)
        #expect(try JSONDecoder().decode(ExplanationAudioChunk.self, from: JSONEncoder().encode(audio)) == audio)
    }

    @Test func rejectsUnknownFieldsAtEveryNestedBoundary() throws {
        let data = try ExplanationWire.encode(ExplanationProtocolFixtures.event())
        let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        func rejected(_ object: [String: Any]) throws {
            let bad = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(bad) }
        }
        var changed = original; changed["audioRef"] = "model-owned"; try rejected(changed)
        changed = original; changed["captureBounds"] = [0, 0, 100, 100]; try rejected(changed)
        changed = original
        var speech = try #require(changed["speech"] as? [String: Any]); speech["duration"] = 1
        changed["speech"] = speech; try rejected(changed)
        for key in ["cue", "anchor", "operation", "object", "geometry", "transform", "vector", "style"] {
            changed = original
            var cues = try #require(changed["cues"] as? [[String: Any]])
            var cue = cues[0]
            var operations = try #require(cue["operations"] as? [[String: Any]])
            var operation = operations[0]
            var object = try #require(operation["object"] as? [String: Any])
            switch key {
            case "cue": cue["timestamp"] = 3
            case "anchor":
                var anchor = try #require(cue["anchor"] as? [String: Any]); anchor["seconds"] = 2; cue["anchor"] = anchor
            case "operation": operation["callback"] = "execute()"
            case "object": object["assetURL"] = "https://invalid.example/image"
            case "geometry":
                var geometry = try #require(object["geometry"] as? [String: Any]); geometry["shader"] = "code"; object["geometry"] = geometry
            case "transform", "vector":
                var transform = try #require(object["transform"] as? [String: Any])
                if key == "transform" { transform["matrix"] = [1, 2] }
                else {
                    var vector = try #require(transform["position"] as? [String: Any]); vector["w"] = 0; transform["position"] = vector
                }
                object["transform"] = transform
            default:
                var style = try #require(object["style"] as? [String: Any]); style["textureURL"] = "file:///private"; object["style"] = style
            }
            operation["object"] = object; operations[0] = operation; cue["operations"] = operations
            cues[0] = cue; changed["cues"] = cues; try rejected(changed)
        }
    }

    @Test func rejectsDuplicateEscapedKeysUnsupportedCommandsAndTrailingData() throws {
        let encoded = String(decoding: try ExplanationWire.encode(ExplanationProtocolFixtures.event()), as: UTF8.self)
        let duplicate = "{\"version\":1,\"\\u0076ersion\":1," + encoded.dropFirst()
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(Data(duplicate.utf8)) }
        let command = encoded.replacingOccurrences(of: "\"op\":\"create\"", with: "\"op\":\"execute\"")
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(Data(command.utf8)) }
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(Data((encoded + "{}").utf8)) }
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(Data("```json\n\(encoded)\n```".utf8)) }
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(Data([0xff, 0xfe])) }
        var invalidUTF8 = Data(encoded.utf8)
        let textRange = try #require(invalidUTF8.range(of: Data("Here is a point.".utf8)))
        invalidUTF8.replaceSubrange(textRange, with: [0xc0, 0xaf])
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(invalidUTF8) }
    }

    @Test func finiteGeometryTextAndTransitionLimitsApplyToDirectConstruction() throws {
        var object = ExplanationProtocolFixtures.point()
        object.transform.position.x = .nan
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(.create(object)) }
        object = ExplanationProtocolFixtures.point(); object.geometry.radius = .infinity
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(.create(object)) }
        object = ExplanationProtocolFixtures.point(); object.accessibleDescription = String(repeating: "a", count: 513)
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(.create(object)) }
        let longAnimation = ExplanationAnimation(property: .position, to: .zero, duration: 30.001)
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(.animate(id: "point", animation: longAnimation)) }
        let zeroAnimation = ExplanationAnimation(property: .strokeReveal, to: .init(x: 1, y: 0), duration: 0)
        try ExplanationSceneReducer.validate(.animate(id: "point", animation: zeroAnimation))
        var event = ExplanationProtocolFixtures.event(); event.speech.text = String(repeating: "a", count: 1601)
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.encode(event) }
        event = ExplanationProtocolFixtures.event(); event.baseRevision = Int.max; event.revision = Int.max
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(event) }
    }

    @Test func rejectsModelAudioMetadataNonfiniteNumbersAndNestingBombs() throws {
        let encoded = String(decoding: try ExplanationWire.encode(ExplanationProtocolFixtures.event()), as: UTF8.self)
        let infinite = encoded.replacingOccurrences(of: "\"radius\":4", with: "\"radius\":1e999")
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(Data(infinite.utf8)) }
        let deep = String(repeating: "[", count: 25) + "0" + String(repeating: "]", count: 25)
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(Data(deep.utf8)) }
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(Data(repeating: 32, count: ExplanationLimits.frameBytes + 1)) }
    }

    @Test func validatesSemanticAnchorsAndActualAlignmentWithoutEstimatingSpeech() throws {
        var event = ExplanationProtocolFixtures.event()
        event.cues = [.init(id: "end", anchor: .end, operations: [.clear]), .init(id: "early", anchor: .start, operations: [.clear])]
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(event) }
        event.cues = [.init(id: "cue", anchor: .init(kind: .start, wordIndex: 0), operations: [.clear])]
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(event) }
        var audio = ExplanationAudioChunk(sessionID: event.sessionID, turnID: event.turnID, sceneID: event.sceneID,
                                         beatID: event.beatID, chunkID: event.speech.chunkID, duration: 1, sampleRate: 48_000)
        try ExplanationSceneReducer.validate(audio)
        audio.alignment = [.init(wordIndex: 0, start: 0, end: 0.7), .init(wordIndex: 1, start: 0.5, end: 0.9)]
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(audio) }
        audio.alignment = [.init(wordIndex: 0, start: 0, end: 1.1)]
        #expect(throws: ExplanationFailure.self) { try ExplanationSceneReducer.validate(audio) }
    }

    @Test func everyClosedOperationRoundTripsWithoutExecutablePayloads() throws {
        let point = ExplanationProtocolFixtures.point()
        let connector = ExplanationObject(id: "link", geometry: .init(kind: .connector, fromID: "a", toID: "b"), accessibleDescription: "Connection")
        let operations: [ExplanationOperation] = [
            .create(point), .update(id: point.id, patch: .init(style: .init(fill: .green))),
            .remove(id: point.id), .move(id: point.id, position: .init(x: 3, y: 4)),
            .recolor(id: point.id, color: .cyan), .highlight(id: point.id, highlighted: true),
            .group(id: "group", members: [point.id]), .label(id: point.id, text: "Point"),
            .connect(connector), .camera(.init()),
            .animate(id: point.id, animation: .init(property: .position, to: .zero, duration: 0.25)), .clear
        ]
        for operation in operations {
            let event = ExplanationProtocolFixtures.event(operations: [operation])
            #expect(try ExplanationWire.decode(ExplanationWire.encode(event)) == event)
        }
    }

    @Test func allRequiredEnvelopeFieldsAndVersionAreEnforced() throws {
        let original = try #require(JSONSerialization.jsonObject(with: ExplanationWire.encode(ExplanationProtocolFixtures.event())) as? [String: Any])
        for field in original.keys {
            var missing = original; missing.removeValue(forKey: field)
            #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(JSONSerialization.data(withJSONObject: missing)) }
        }
        var future = original; future["version"] = 2
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(JSONSerialization.data(withJSONObject: future)) }
    }
}
