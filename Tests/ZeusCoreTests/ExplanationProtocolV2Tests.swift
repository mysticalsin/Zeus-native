import Foundation
import Testing
@testable import ZeusCore

@Suite("Explanation protocol v2 (pointing targetID) and the scene resolver")
struct ExplanationProtocolV2Tests {
    private let session = UUID(), turn = UUID(), scene = UUID(), capture = UUID()

    private func line(version: Int, extraObjectField: String = "", target: String? = "t0", beat: String = "b0",
                      sequence: Int = 0) -> Data {
        let targetField = target.map { ",\"targetID\":\"\($0)\"" } ?? ""
        let json = """
        {"version":\(version),"sessionID":"\(session)","turnID":"\(turn)","sceneID":"\(scene)","sequence":\(sequence),\
        "baseRevision":\(sequence),"revision":\(sequence + 1),"beatID":"\(beat)",\
        "speech":{"chunkID":"\(beat)-s","text":"That is Share."},"cues":[{"id":"c0","anchor":{"kind":"start"},"operations":[\
        {"op":"create","object":{"id":"ring","space":"capture","captureID":"\(capture)"\(targetField)\(extraObjectField),\
        "geometry":{"kind":"ring","radius":20},"accessibleDescription":"Ring"}}]}],"isFinal":true}
        """
        return Data(json.utf8)
    }

    private let candidates: ExplanationWireProfile = .v2(candidateIDs: ["t0", "t1"])

    @Test func v1StillDecodesUnderBothProfiles() throws {
        let plain = line(version: 1, target: nil)
        #expect(try ExplanationWire.decode(plain).version == 1)
        #expect(try ExplanationWire.decode(plain, profile: candidates).version == 1)
    }

    @Test func v2TargetIDIsAcceptedOnlyWithAMatchingCandidate() throws {
        let event = try ExplanationWire.decode(line(version: 2), profile: candidates)
        guard case .create(let object) = event.cues[0].operations[0] else { Issue.record("expected create"); return }
        #expect(object.targetID == "t0")
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(line(version: 2, target: "t5"), profile: candidates) }
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(line(version: 2, target: "x0"), profile: candidates) }
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(line(version: 2, target: "t100"), profile: candidates) }
    }

    @Test func targetIDIsRejectedOutsideAV2PointingTurn() {
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(line(version: 2)) }
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(line(version: 1), profile: candidates) }
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(line(version: 3, target: nil), profile: candidates) }
    }

    @Test func unknownFieldsAreStillRejectedInV2() {
        #expect(throws: ExplanationFailure.self) {
            try ExplanationWire.decode(line(version: 2, extraObjectField: ",\"url\":\"https://example.com\""), profile: candidates)
        }
    }

    @Test func aTargetOnANonCaptureObjectIsRejected() {
        let json = String(decoding: line(version: 2), as: UTF8.self)
            .replacingOccurrences(of: "\"space\":\"capture\",\"captureID\":\"\(capture)\"", with: "\"space\":\"canvas\"")
        #expect(throws: ExplanationFailure.self) { try ExplanationWire.decode(Data(json.utf8), profile: candidates) }
    }

    @Test func aPartialLineIsNeverRenderedAtAnyByteBoundary() throws {
        let full = line(version: 2) + Data([10])
        for cut in stride(from: 1, to: full.count - 1, by: 7) {
            var stream = try ExplanationEventStream(sessionID: session, turnID: turn, sceneID: scene, baseRevision: 0, profile: candidates)
            #expect(try stream.append(full.prefix(cut)).isEmpty)
            let rest = try stream.append(full.suffix(from: cut))
            #expect(rest.count == 1)
        }
    }

    @Test func malformedV2NeverReachesTheStreamConsumer() throws {
        var stream = try ExplanationEventStream(sessionID: session, turnID: turn, sceneID: scene, baseRevision: 0, profile: candidates)
        #expect(throws: ExplanationFailure.self) { try stream.append(line(version: 2, target: "t9") + Data([10])) }
        #expect(throws: ExplanationFailure.self) { try stream.append(line(version: 2) + Data([10])) } // Failed streams stay failed.
    }

    // MARK: resolver

    private func context(rect: ExplanationRect? = .init(x: 100, y: 50, width: 200, height: 40)) -> PointingContext {
        PointingContext(captureID: capture, imageSize: .init(width: 1440, height: 900),
                        dwellImagePoints: [.init(x: 900, y: 600)],
                        candidates: [.init(id: "t0", role: "AXButton", label: "Share", imageRect: rect)])
    }

    private func object(_ id: String, _ kind: ExplanationGeometry.Kind, target: String? = nil, at: (Double, Double) = (0, 0),
                        text: String? = nil) -> ExplanationObject {
        var geometry = ExplanationGeometry(kind: kind)
        if kind == .ring { geometry.radius = 20 }
        if kind == .badge { geometry.radius = 10 }
        return ExplanationObject(id: id, space: .capture, captureID: capture, geometry: geometry,
                                 transform: .init(position: .init(x: at.0, y: at.1)), text: text,
                                 accessibleDescription: "d", targetID: target)
    }

    private func event(_ operations: [ExplanationOperation]) -> ExplanationEvent {
        ExplanationEvent(version: 2, sessionID: session, turnID: turn, sceneID: scene, sequence: 0, baseRevision: 0, revision: 1,
                         beatID: "b0", speech: .init(chunkID: "b0-s", text: "Hi."),
                         cues: [.init(id: "c0", operations: operations)], isFinal: true)
    }

    @Test func aTargetedRingAndLabelUseTheCandidateRectNotModelGeometry() throws {
        let resolution = PointingSceneResolver.resolve(event([
            .create(object("ring", .ring, target: "t0", at: (999, 999))),
            .create(object("label", .label, target: "t0", text: "Share")),
        ]), context: context())
        #expect(resolution.droppedObjects == 0)
        #expect(resolution.event.version == 1)
        try ExplanationSceneReducer.validate(resolution.event)
        guard case .create(let ring) = resolution.event.cues[0].operations[0],
              case .create(let label) = resolution.event.cues[0].operations[1] else { Issue.record("shape"); return }
        #expect(ring.transform.position == .init(x: 200, y: 70))
        #expect(ring.geometry.radius == 106) // max(200, 40) / 2 + 6
        #expect(label.transform.position == .init(x: 306, y: 70)) // ring's outer edge
        #expect(ring.targetID == nil && label.targetID == nil)
    }

    @Test func aMarkWithNoTargetAndNoNearbyEvidenceIsDroppedWithItsFollowUps() {
        let resolution = PointingSceneResolver.resolve(event([
            .create(object("stray", .ring, at: (1300, 800))),
            .recolor(id: "stray", color: .red),
            .create(object("near", .ring, at: (200, 70))),           // inside the candidate rect
            .create(object("dwell", .ring, at: (930, 620))),         // within 48 px of the dwell
        ]), context: context())
        #expect(resolution.droppedObjects == 1)
        #expect(resolution.notGrounded)
        #expect(resolution.event.cues[0].operations.count == 2)
    }

    @Test func aTargetWithoutARectOrWithAnotherCaptureIsDropped() {
        let noRect = PointingSceneResolver.resolve(event([.create(object("r", .ring, target: "t0"))]), context: context(rect: nil))
        #expect(noRect.droppedObjects == 1 && noRect.event.cues.isEmpty)
        var other = context(); other.captureID = UUID()
        #expect(PointingSceneResolver.resolve(event([.create(object("r", .ring, target: "t0"))]), context: other).droppedObjects == 1)
    }

    @Test func geometryEditsToAPlacedObjectAreIgnoredButStyleEditsKeep() {
        let resolution = PointingSceneResolver.resolve(event([
            .create(object("ring", .ring, target: "t0")),
            .move(id: "ring", position: .init(x: 5, y: 5)),
            .update(id: "ring", patch: .init(geometry: .init(kind: .ring, radius: 300))),
            .recolor(id: "ring", color: .green),
        ]), context: context())
        #expect(resolution.event.cues[0].operations.count == 2)
    }

    @Test func speechIsNeverChangedByResolution() {
        let source = event([.create(object("stray", .ring, at: (1300, 800)))])
        let resolution = PointingSceneResolver.resolve(source, context: context())
        #expect(resolution.event.speech == source.speech && resolution.event.cues.isEmpty)
    }

    @Test func v1HistoryRoundTripsWithoutATargetIDKey() throws {
        let data = try JSONEncoder().encode(object("a", .ring, at: (1, 1)))
        #expect(!String(decoding: data, as: UTF8.self).contains("targetID"))
    }
}
