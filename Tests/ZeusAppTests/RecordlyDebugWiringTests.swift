import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Exercises the record debug reply with injected handlers and the parser/catalog it uses.
/// No CommandCenter, VoiceTurnController, RecordlyController, capture or source enumeration.
@MainActor
@Suite("Recordly debug wiring")
struct RecordlyDebugWiringTests {
    private final class Captured: @unchecked Sendable { var argument: String? }

    @Test func unwiredHandlerFailsClosed() async {
        let reply = await CommandCenter.recordReply(id: "a", argument: "--seconds 5", handler: nil)
        #expect(!reply.ok)
        #expect(reply.id == "a")
        #expect(reply.text == "record handler not wired.")
    }

    @Test func handlerReceivesTheRawArgumentAndOkReplyPasses() async {
        let captured = Captured()
        let reply = await CommandCenter.recordReply(id: "b", argument: "--seconds 5 --no-mic") { argument in
            captured.argument = argument
            return "ok=true mp4=/tmp/x.mp4"
        }
        #expect(captured.argument == "--seconds 5 --no-mic")
        #expect(reply.ok)
        #expect(reply.text == "ok=true mp4=/tmp/x.mp4")
    }

    @Test func blockedAndErrorRepliesAreNotOk() async {
        for text in ["BLOCKED-ON-TONY Screen Recording permission needed (preflight false).",
                     "ok=false error=Explicit current source selection required.", "ERROR boom", ""] {
            let reply = await CommandCenter.recordReply(id: "c", argument: "") { _ in text }
            #expect(!reply.ok)
            #expect(reply.text == text)
        }
    }

    @Test func argumentParsesIntoThePlanTheHandlerWouldRun() {
        let plan = RecordlyDebugPlanParser.parse("--seconds 5 --window settings --no-mic --export mp4")
        #expect(plan.seconds == 5)
        #expect(plan.windowName == "settings")
        #expect(plan.noMic)
        #expect(plan.exportFormats == [.mp4])
        #expect(RecordlyDebugPlanParser.parse("") == RecordlyDebugPlan())
    }

    @Test func recordIsInTheCatalogAndTheUnknownReply() {
        #expect(DebugSubcommandCatalog.names.contains("record"))
        #expect(DebugSubcommandCatalog.unknownMessage("nope").contains("record"))
        #expect(ZeusCLI.usage.contains("record"))
    }
}
