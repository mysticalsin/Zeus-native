import Foundation
import Testing
@testable import ZeusCore

@Suite("Action speed trace")
struct ActionSpeedTraceTests {
    private let turn = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

    @Test func flagOffDropsEventsAndIgnoresAFilePath() {
        let home = URL(fileURLWithPath: "/tmp/zeus-home")
        let off = ActionSpeedTrace.configured(["ZEUS_ACTION_SPEED_TRACE_FILE": "/tmp/secret.jsonl"], home: home)
        #expect(!off.enabled)
        #expect(off.file == nil)
        var trace = off
        #expect(trace.beginTurn(id: turn, monoNs: 10) == nil)
        trace.mark(.sttFinal, monoNs: 20)
        #expect(trace.events.isEmpty)
    }

    @Test func flagOnWithoutAPathUsesTheSupportFile() {
        let home = URL(fileURLWithPath: "/Users/example")
        let on = ActionSpeedTrace.configured(["ZEUS_ACTION_SPEED_TRACE": "1"], home: home)
        #expect(on.enabled)
        #expect(on.file == ActionSpeedTrace.supportFile(home: home))
        #expect(on.file?.path == "/Users/example/Library/Application Support/Zeus/action-speed.jsonl")
    }

    @Test func aNonUUIDTurnIsDropped() throws {
        var trace = ActionSpeedTrace(enabled: true)
        #expect(trace.beginTurn(id: "what is the capital of australia", monoNs: 1) == nil)
        #expect(trace.events.isEmpty)
        let id = trace.beginTurn(id: turn, monoNs: 1_000)
        #expect(id == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
    }

    @Test func stagesAreMonotonicOffsetsAndTheFirstMarkWins() throws {
        var trace = ActionSpeedTrace(enabled: true)
        let id = trace.beginTurn(id: turn, monoNs: 1_000_000_000)
        #expect(id == turn)
        trace.mark(.sttFinal, monoNs: 1_450_000_000)
        trace.mark(.sttFinal, monoNs: 9_000_000_000)
        trace.mark(.requestSent, monoNs: 1_500_000_000)
        trace.mark(.firstModelToken, monoNs: 2_000_000_000)
        trace.mark(.firstToolDecision, monoNs: 2_100_000_000)
        trace.mark(.firstTtsAudio, monoNs: 2_400_000_000)
        trace.mark(.firstOverlayPaint, monoNs: 2_450_000_000)
        trace.mark(.pointerArrival, monoNs: 2_500_000_000)
        #expect(trace.offsetMs(.keyRelease, turn: turn) == 0)
        #expect(trace.offsetMs(.sttFinal, turn: turn) == 450)
        #expect(trace.offsetMs(.firstModelToken, turn: turn) == 1_000)
        #expect(trace.offsetMs(.firstTtsAudio, turn: turn) == 1_400)
        #expect(trace.offsetMs(.pointerArrival, turn: turn) == 1_500)
        let sample = trace.talkSample(turn: turn)
        #expect(sample != nil)
        #expect(sample?.sttFinalMs == 450)
        #expect(sample?.firstTokenMs == 550)
        #expect(sample?.ttsFirstMs == 400)
        #expect(sample?.firstAudioMs == 1_400)
        #expect(sample?.firstVisualMs == 1_450)
        #expect(sample?.captureReadyMs == nil)
    }

    @Test func aNegativeGapCannotShrinkTheTalkClock() throws {
        var trace = ActionSpeedTrace(enabled: true)
        #expect(trace.beginTurn(id: turn, monoNs: 5_000) == turn)
        trace.mark(.sttFinal, monoNs: 1_000)
        trace.mark(.firstModelToken, monoNs: 4_000)
        trace.mark(.firstTtsAudio, monoNs: 6_000)
        let sample = trace.talkSample(turn: turn)
        #expect(sample?.sttFinalMs == 0)
        #expect((sample?.firstAudioMs ?? -1) >= 0)
    }

    @Test func theJSONLineHasNoTranscriptAndOnlyThreeKeys() throws {
        var trace = ActionSpeedTrace(enabled: true)
        _ = trace.beginTurn(id: turn, monoNs: 10)
        let line = trace.events.first?.jsonLine() ?? ""
        #expect(line == "{\"turn\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\",\"stage\":\"keyRelease\",\"monoNs\":10}")
        let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        #expect(Set(object.keys) == Set(["turn", "stage", "monoNs"]))
        #expect(!line.lowercased().contains("transcript"))
        #expect(!line.lowercased().contains("capital"))
    }

    @Test func enabledTraceAppendsJSONLAndDisabledTraceDoesNotCreateTheFile() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("zeus-speed-\(UUID().uuidString)")
        let file = root.appendingPathComponent("action-speed.jsonl")
        var off = ActionSpeedTrace(enabled: false, file: file)
        _ = off.beginTurn(id: turn, monoNs: 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        var on = ActionSpeedTrace(enabled: true, file: file)
        _ = on.beginTurn(id: turn, monoNs: 42)
        on.mark(.firstTtsAudio, monoNs: 2_000_000_042)
        let text = try String(contentsOf: file, encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].contains("\"stage\":\"keyRelease\""))
        #expect(lines[1].contains("\"stage\":\"firstTtsAudio\""))
        #expect(!text.lowercased().contains("transcript"))
        let values = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((values[.posixPermissions] as? NSNumber)?.uint16Value == 0o600)
        try? FileManager.default.removeItem(at: root)
    }

    @Test func mergedLatencyConstantsStayPut() {
        #expect(TalkLatencyBudget.firstAudioTargetMs == 1_200)
        #expect(TalkLatencyBudget.sttFinalCapMs == 450)
    }
}
