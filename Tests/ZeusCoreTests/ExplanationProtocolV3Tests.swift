import Foundation
import Testing
@testable import ZeusCore

@Suite("Explanation protocol v3: additive chart axis spec")
struct ExplanationProtocolV3Tests {
    private let session = UUID(), turn = UUID(), scene = UUID(), capture = UUID()
    private let v3: ExplanationWireProfile = .v3(candidateIDs: ["t0"])
    private static let goodAxis = "{\"scale\":\"linear\",\"source\":\"userProvided\",\"units\":\"USD\",\"tickHint\":5,\"domain\":{\"lower\":0,\"upper\":10}}"

    private func chartLine(version: Int = 3, axis: String? = ExplanationProtocolV3Tests.goodAxis, kind: String = "chart", values: String = "[3,5,8]",
                           labels: String = "[\"a\",\"b\",\"c\"]", sequence: Int = 0) -> Data {
        let axisField = axis.map { ",\"axis\":\($0)" } ?? ""
        let json = """
        {"version":\(version),"sessionID":"\(session)","turnID":"\(turn)","sceneID":"\(scene)","sequence":\(sequence),\
        "baseRevision":\(sequence),"revision":\(sequence + 1),"beatID":"b0","speech":{"chunkID":"b0-s","text":"Sales rose."},\
        "cues":[{"id":"c0","anchor":{"kind":"start"},"operations":[{"op":"create","object":{"id":"chart","space":"canvas",\
        "geometry":{"kind":"\(kind)","size":{"x":400,"y":240,"z":0},"values":\(values),"labels":\(labels)\(axisField)},\
        "accessibleDescription":"Chart"}}]}],"isFinal":true}
        """
        return Data(json.utf8)
    }

    private func targetLine(version: Int) -> Data {
        let json = """
        {"version":\(version),"sessionID":"\(session)","turnID":"\(turn)","sceneID":"\(scene)","sequence":0,\
        "baseRevision":0,"revision":1,"beatID":"b0","speech":{"chunkID":"b0-s","text":"That is Share."},\
        "cues":[{"id":"c0","anchor":{"kind":"start"},"operations":[{"op":"create","object":{"id":"ring","space":"capture",\
        "captureID":"\(capture)","targetID":"t0","geometry":{"kind":"ring","radius":20},"accessibleDescription":"Ring"}}]}],"isFinal":true}
        """
        return Data(json.utf8)
    }

    private func axis(of event: ExplanationEvent) -> ExplanationChartAxis? {
        guard case .create(let object) = event.cues[0].operations[0] else { return nil }
        return object.geometry.axis
    }

    private func rejected(_ data: Data, profile: ExplanationWireProfile? = nil) -> Bool {
        do { _ = try ExplanationWire.decode(data, profile: profile ?? v3); return false } catch { return error is ExplanationFailure }
    }

    // MARK: accepted

    @Test func wireV3AcceptsAChartAxisOnAVersionThreeEvent() throws {
        let event = try ExplanationWire.decode(chartLine(), profile: v3)
        let expected = ExplanationChartAxis(scale: .linear, domain: .init(lower: 0, upper: 10), units: "USD", tickHint: 5, source: .userProvided)
        #expect(axis(of: event) == expected)
        #expect(event.version == 3)
    }

    @Test func wireV3ChartWithoutAnAxisStillDecodesUnderEveryProfile() throws {
        let plain = chartLine(version: 1, axis: nil)
        #expect(try ExplanationWire.decode(plain).version == 1)
        #expect(try ExplanationWire.decode(plain, profile: .v2(candidateIDs: [])).version == 1)
        let event = try ExplanationWire.decode(plain, profile: v3)
        #expect(axis(of: event) == nil)
        #expect(try ExplanationWire.decode(chartLine(version: 3, axis: nil), profile: v3).version == 3)
    }

    @Test func wireV3AcceptsATruncatedBarAxisAndTimelineSpacings() throws {
        let truncated = "{\"scale\":\"linear\",\"source\":\"example\",\"includeZero\":false}"
        let event = try ExplanationWire.decode(chartLine(axis: truncated, values: "[100,120]", labels: "[\"a\",\"b\"]"), profile: v3)
        #expect(axis(of: event)?.includeZero == false)
        let time = "{\"scale\":\"time\",\"source\":\"onScreen\",\"units\":\"year\"}"
        #expect(!rejected(chartLine(axis: time, kind: "timeline", values: "[2000,2010]", labels: "[\"a\",\"b\"]")))
        let even = "{\"scale\":\"categorical\",\"source\":\"userProvided\"}"
        #expect(!rejected(chartLine(axis: even, kind: "timeline", values: "[2000,2010]", labels: "[\"a\",\"b\"]")))
    }

    @Test func wireV3TargetIDStillWorksOnAVersionThreeOrTwoPointingEvent() throws {
        #expect(try ExplanationWire.decode(targetLine(version: 3), profile: v3).version == 3)
        #expect(try ExplanationWire.decode(targetLine(version: 2), profile: v3).version == 2)
        #expect(rejected(targetLine(version: 1), profile: v3))
        #expect(rejected(targetLine(version: 3), profile: .v2(candidateIDs: ["t0"])))
    }

    // MARK: rejected

    @Test func wireV3AxisIsRejectedOutsideTheVersionThreeProfileAndNumber() {
        #expect(rejected(chartLine(), profile: .v1))
        #expect(rejected(chartLine(), profile: .v2(candidateIDs: ["t0"])))
        #expect(rejected(chartLine(version: 1)))
        #expect(rejected(chartLine(version: 2)))
        #expect(rejected(chartLine(version: 4)))
    }

    @Test func wireV3UnknownAndMissingAxisFieldsAreRejected() {
        #expect(rejected(chartLine(axis: "{\"scale\":\"linear\",\"source\":\"example\",\"smooth\":true}")))
        #expect(rejected(chartLine(axis: "{\"scale\":\"linear\"}")))
        #expect(rejected(chartLine(axis: "{\"source\":\"example\"}")))
        #expect(rejected(chartLine(axis: "{\"scale\":\"log\",\"source\":\"example\"}")))
        #expect(rejected(chartLine(axis: "{\"scale\":\"linear\",\"source\":\"guess\"}")))
        #expect(rejected(chartLine(axis: "{\"scale\":\"linear\",\"source\":\"example\",\"domain\":{\"lower\":0}}")))
        #expect(rejected(chartLine(axis: "{\"scale\":\"linear\",\"source\":\"example\",\"domain\":{\"lower\":0,\"upper\":9,\"step\":1}}")))
        #expect(rejected(chartLine(axis: "{\"scale\":\"linear\",\"source\":\"example\",\"url\":\"https://example.com\"}")))
    }

    @Test func wireV3DuplicateAxisKeysAreRejected() {
        #expect(rejected(chartLine(axis: "{\"scale\":\"linear\",\"source\":\"example\",\"source\":\"live\"}")))
    }

    @Test func wireV3AxisRangesAreChecked() {
        func linear(_ tail: String) -> String { "{\"scale\":\"linear\",\"source\":\"example\"\(tail)}" }
        #expect(rejected(chartLine(axis: linear(",\"tickHint\":1"))))
        #expect(rejected(chartLine(axis: linear(",\"tickHint\":13"))))
        #expect(!rejected(chartLine(axis: linear(",\"tickHint\":12"))))
        #expect(rejected(chartLine(axis: linear(",\"units\":\"\""))))
        #expect(rejected(chartLine(axis: linear(",\"units\":\"\(String(repeating: "u", count: 25))\""))))
        #expect(rejected(chartLine(axis: linear(",\"domain\":{\"lower\":5,\"upper\":5}"))))
        #expect(rejected(chartLine(axis: linear(",\"domain\":{\"lower\":9,\"upper\":1}"))))
        #expect(rejected(chartLine(axis: linear(",\"domain\":{\"lower\":0,\"upper\":7}"))))
        #expect(rejected(chartLine(axis: linear(",\"domain\":{\"lower\":0,\"upper\":2000000}"))))
    }

    @Test func wireV3AxisKindMustMatchTheGeometry() {
        let even = "{\"scale\":\"categorical\",\"source\":\"example\"}"
        let time = "{\"scale\":\"time\",\"source\":\"example\"}"
        #expect(rejected(chartLine(axis: even)))
        #expect(rejected(chartLine(axis: time)))
        #expect(rejected(chartLine(axis: "{\"scale\":\"linear\",\"source\":\"example\"}", kind: "timeline", values: "[1,2]", labels: "[\"a\",\"b\"]")))
        #expect(rejected(chartLine(axis: "{\"scale\":\"time\",\"source\":\"example\",\"includeZero\":true}", kind: "timeline",
                                   values: "[1,2]", labels: "[\"a\",\"b\"]")))
        #expect(rejected(chartLine(axis: "{\"scale\":\"categorical\",\"source\":\"example\",\"units\":\"s\"}", kind: "timeline",
                                   values: "[1,2]", labels: "[\"a\",\"b\"]")))
    }

    @Test func wireV3AxisIsRejectedOnGeometryThatIsNotAChart() {
        let json = String(decoding: chartLine(), as: UTF8.self)
            .replacingOccurrences(of: "\"kind\":\"chart\",\"size\":{\"x\":400,\"y\":240,\"z\":0},\"values\":[3,5,8],\"labels\":[\"a\",\"b\",\"c\"]",
                                  with: "\"kind\":\"ring\",\"radius\":20")
        #expect(json.contains("\"kind\":\"ring\""))
        #expect(rejected(Data(json.utf8)))
    }

    @Test func wireV3LiveDataNeedsAnISOAsOfAndOtherSourcesForbidIt() throws {
        func spec(_ source: String, _ asOf: String?) -> String {
            "{\"scale\":\"linear\",\"source\":\"\(source)\"" + (asOf.map { ",\"asOf\":\"\($0)\"" } ?? "") + "}"
        }
        let live = try ExplanationWire.decode(chartLine(axis: spec("live", "2026-11-11T10:00:00Z")), profile: v3)
        #expect(axis(of: live)?.asOf == "2026-11-11T10:00:00Z")
        #expect(rejected(chartLine(axis: spec("live", nil))))
        #expect(rejected(chartLine(axis: spec("live", "yesterday"))))
        #expect(rejected(chartLine(axis: spec("example", "2026-11-11T10:00:00Z"))))
        #expect(rejected(chartLine(axis: spec("userProvided", "2026-11-11T10:00:00Z"))))
        #expect(!rejected(chartLine(axis: spec("onScreen", nil))))
    }

    @Test func wireV3NonFiniteChartValuesNeverPassValidation() {
        for bad in [Double.nan, .infinity, -.infinity, 2_000_000] {
            let geometry = ExplanationGeometry(kind: .chart, size: .init(x: 400, y: 240), values: [bad], labels: ["a"])
            #expect((try? ExplanationSceneReducer.validate(.create(.init(id: "c", geometry: geometry, accessibleDescription: "d")))) == nil)
        }
    }

    // MARK: round trips and the rest of the pipeline

    @Test func wireV3GeometryRoundTripsAndOmitsAnAbsentAxis() throws {
        let spec = ExplanationChartAxis(scale: .linear, domain: .init(lower: 0, upper: 9), units: "ms", tickHint: 4,
                                        includeZero: false, source: .live, asOf: "2026-11-11T10:00:00Z")
        let withAxis = ExplanationGeometry(kind: .chart, size: .init(x: 400, y: 240), values: [1], labels: ["a"], axis: spec)
        let data = try JSONEncoder().encode(withAxis)
        #expect(try JSONDecoder().decode(ExplanationGeometry.self, from: data) == withAxis)
        let plain = ExplanationGeometry(kind: .chart, size: .init(x: 400, y: 240), values: [1], labels: ["a"])
        #expect(!String(decoding: try JSONEncoder().encode(plain), as: UTF8.self).contains("axis"))
        let legacy = Data("{\"kind\":\"chart\",\"size\":{\"x\":400,\"y\":240,\"z\":0},\"values\":[1],\"labels\":[\"a\"]}".utf8)
        #expect(try JSONDecoder().decode(ExplanationGeometry.self, from: legacy).axis == nil)
    }

    @Test func wireV3ResolverKeepsTheAxisAndStillHandsBackAVersionOneEvent() throws {
        let event = try ExplanationWire.decode(chartLine(), profile: v3)
        let context = PointingContext(captureID: capture, imageSize: .init(width: 1440, height: 900))
        let resolution = PointingSceneResolver.resolve(event, context: context)
        #expect(resolution.event.version == 1 && resolution.droppedObjects == 0)
        #expect(axis(of: resolution.event) == axis(of: event))
        try ExplanationSceneReducer.validate(resolution.event)
    }

    @Test func wireV3AdmittedAxisSurvivesSceneValidationAndAReducerRoundTrip() throws {
        let event = try ExplanationWire.decode(chartLine(), profile: v3)
        var resolved = event
        resolved.version = 1
        let base = ExplanationScene(sessionID: session, sceneID: scene)
        let next = try ExplanationSceneReducer.applying(resolved, to: base, activeTurn: turn)
        let chart = try #require(next.objects["chart"])
        #expect(chart.geometry.axis?.units == "USD")
        try ExplanationSceneReducer.validate(next)
        let data = try JSONEncoder().encode(next)
        #expect(try JSONDecoder().decode(ExplanationScene.self, from: data) == next)
    }

    @Test func wireV3PartialLinesNeverEmitAtAnyByteBoundary() throws {
        let full = chartLine() + Data([10])
        for cut in stride(from: 1, to: full.count - 1, by: 11) {
            var stream = try ExplanationEventStream(sessionID: session, turnID: turn, sceneID: scene, baseRevision: 0, profile: v3)
            let head = try stream.append(full.prefix(cut))
            #expect(head.isEmpty)
            let rest = try stream.append(full.suffix(from: cut))
            #expect(rest.count == 1)
        }
    }

    @Test func wireV3ChatInstructionsStayUnchangedAndPointingInstructionsCarryTheAxisRules() {
        #expect(!ExplanationWire.modelInstructions.contains("axis"))
        #expect(PointingPrompt.instructions.contains(ExplanationWire.chartAxisInstructions))
        #expect(!ExplanationWire.chartAxisInstructions.contains("\u{2014}"))
        #expect(ExplanationWire.chartAxisInstructions.contains("example"))
        #expect(ExplanationWire.chartAxisInstructions.contains("asOf"))
    }
}
