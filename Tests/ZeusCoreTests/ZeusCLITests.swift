import Foundation
import Testing
@testable import ZeusCore

@Suite struct ZeusCLITests {
    @Test func plainWordsAreAnAsk() throws {
        let call = try ZeusCLI.parse(["open", "my", "repo"], id: "t1")
        #expect(call.command == ZeusCommand(id: "t1", op: .ask, text: "open my repo"))
        #expect(call.timeout == 150)
    }

    @Test func flags() throws {
        let call = try ZeusCLI.parse(["--deep", "--quiet", "--json", "what time is it"], id: "t2")
        #expect(call.command == ZeusCommand(id: "t2", op: .ask, text: "what time is it", deep: true, speak: false))
        #expect(call.json)
        #expect(call.timeout == 300)
    }

    @Test func subcommands() throws {
        #expect(try ZeusCLI.parse(["status"]).command?.op == .status)
        #expect(try ZeusCLI.parse(["tasks"]).command?.op == .tasks)
        #expect(try ZeusCLI.parse(["say", "hello", "there"]).command?.text == "hello there")
        #expect(try ZeusCLI.parse(["cancel", "all"]).command?.text == "all")
        let listen = try ZeusCLI.parse(["listen", "--seconds", "4"])
        #expect(listen.command?.op == .listen)
        #expect(listen.command?.seconds == 4)
        #expect(try ZeusCLI.parse(["ask", "status", "of", "my", "PR"]).command?.text == "status of my PR")
        #expect(try ZeusCLI.parse(["debug", "open-settings", "voice"]).command?.text == "open-settings voice")
        #expect(try ZeusCLI.parse(["debug", "onboarding", "--preview"]).command?.text == "onboarding --preview")
        #expect(try ZeusCLI.parse(["debug", "screenshot", "/tmp/shot.png"]).command?.text == "screenshot /tmp/shot.png")
        #expect(try ZeusCLI.parse(["debug", "tab", "agents"]).command?.text == "tab agents")
        #expect(try ZeusCLI.parse(["debug", "animate", "volume"]).command?.text == "animate volume")
        // P0 item I: `zeus debug presence on|off|state` toggles "Zeus next to the cursor".
        #expect(try ZeusCLI.parse(["debug", "presence", "on"]).command?.text == "presence on")
        #expect(try ZeusCLI.parse(["debug", "presence", "off"]).command?.text == "presence off")
        #expect(try ZeusCLI.parse(["debug", "presence"]).command?.text == "presence")
        #expect(try ZeusCLI.parse(["debug", "engine-logos", "/tmp/n7"]).command?.text == "engine-logos /tmp/n7")
    }

    @Test func debugUnknownListsLaneDAndPresentHooks() {
        let message = DebugSubcommandCatalog.unknownMessage("bogus")
        #expect(message.contains("wake-false-triggers"))
        #expect(message.contains("learn"))
        #expect(message.contains("clean-room"))
        #expect(message.contains("on-device-speech"))
        #expect(ZeusCLI.usage.contains("wake-false-triggers"))
        #expect(ZeusCLI.usage.contains("present"))
    }

    @Test func debugSubcommandDetails() throws {
        let onboardingPreview = try ZeusCLI.parse(["debug", "onboarding", "--preview"])
        #expect(onboardingPreview.command?.op == .debug)
        #expect(onboardingPreview.command?.text == "onboarding --preview")
        #expect(try ZeusCLI.parse(["debug", "open-settings"]).command?.text == "open-settings")
        #expect(onboardingPreview.timeout == 30)
        let screenshotWithWindow = try ZeusCLI.parse(["debug", "screenshot", "/tmp/qa7/s", "--window", "settings"])
        #expect(screenshotWithWindow.command?.text == "screenshot /tmp/qa7/s --window settings")
        #expect(try ZeusCLI.parse(["debug", "hud-state"]).command?.text == "hud-state")
    }

    @Test func debugReplyRenders() throws {
        let reply = ZeusCommandReply(id: "x", ok: true, text: "{\"lights\":[],\"cue\":null}")
        #expect(ZeusCLI.render(reply, op: .debug) == "{\"lights\":[],\"cue\":null}")
    }

    @Test func bareDebugIsAUsageError() {
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["debug"]) }
    }

    @Test func helpAndErrors() {
        #expect((try? ZeusCLI.parse([]))?.command == nil)
        #expect((try? ZeusCLI.parse(["--help"]))?.command == nil)
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["--bogus"]) }
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["say"]) }
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["cancel"]) }
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["debug"]) }
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["status", "now"]) }
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["listen", "--seconds", "x"]) }
    }

    @Test func commandsAreToldApartFromHookEvents() throws {
        let command = try JSONEncoder().encode(ZeusCommand(op: .status))
        let hook = try JSONEncoder().encode(HookEvent(source: .claudeCode, event: "Stop", needsDecision: false))
        #expect(ZeusCommand.isCommand(command))
        #expect(!ZeusCommand.isCommand(hook))
        #expect(!ZeusCommand.isCommand(Data("not json".utf8)))
    }

    @Test func replyRoundTripAndRender() throws {
        let reply = ZeusCommandReply(id: "abcdef1234", ok: true, text: "It's 12:40.", actions: ["browserOpen"],
                                     status: ["socket": "/tmp/z.sock", "app": "running"])
        let decoded = try JSONDecoder().decode(ZeusCommandReply.self, from: JSONEncoder().encode(reply))
        #expect(decoded == reply)
        #expect(ZeusCLI.render(reply, op: .ask) == "It's 12:40.\naction: browserOpen")
        #expect(ZeusCLI.render(reply, op: .status).hasPrefix("app: running\nsocket: /tmp/z.sock"))
    }
}

@Suite struct TalkKeyLatchTests {
    @Test func holdToTalk() {
        var latch = TalkKeyLatch()
        #expect(latch.keyDown(at: 0) == .start)
        #expect(latch.keyUp(at: 1.2) == .stop)
    }

    @Test func singleTapStopsAfterTheGap() {
        var latch = TalkKeyLatch()
        #expect(latch.keyDown(at: 0) == .start)
        #expect(latch.keyUp(at: 0.1) == .stopLater(0.4))
        #expect(latch.pendingStopFired() == .stop)
        #expect(latch.keyDown(at: 2) == .start)
    }

    @Test func doubleTapLatchesUntilTheNextTap() {
        var latch = TalkKeyLatch()
        #expect(latch.keyDown(at: 0) == .start)
        #expect(latch.keyUp(at: 0.1) == .stopLater(0.4))
        #expect(latch.keyDown(at: 0.3) == .cancelPendingStop)
        #expect(latch.keyUp(at: 0.4) == nil)
        #expect(latch.isLatched)
        #expect(latch.pendingStopFired() == nil)
        #expect(latch.keyDown(at: 5) == .stop)
        #expect(latch.keyUp(at: 5.1) == nil)
        #expect(latch.keyDown(at: 6) == .start)
    }

    @Test func tapThenHoldIsANormalHold() {
        var latch = TalkKeyLatch()
        _ = latch.keyDown(at: 0)
        _ = latch.keyUp(at: 0.1)
        #expect(latch.keyDown(at: 0.3) == .cancelPendingStop)
        #expect(latch.keyUp(at: 2) == .stop)
        #expect(!latch.isLatched)
    }

    @Test func escapeCancelsHoldOrLatch() {
        var latch = TalkKeyLatch()
        _ = latch.keyDown(at: 0)
        #expect(latch.cancelFromEsc() == true)
        #expect(latch.keyUp(at: 1) == nil)
        _ = latch.keyDown(at: 2)
        _ = latch.keyUp(at: 2.1)
        _ = latch.keyDown(at: 2.3)
        _ = latch.keyUp(at: 2.4)
        #expect(latch.isLatched)
        #expect(latch.cancelFromEsc() == true)
        #expect(!latch.isLatched)
    }
}

@Suite("zeus todo")
struct ZeusTodoCLITests {
    @Test func parsesTodo() throws {
        let add = try ZeusCLI.parse(["todo", "add", "call", "Anna", "tomorrow"])
        #expect(add.command?.op == .todo)
        #expect(add.command?.text == "add call Anna tomorrow")
        #expect(try ZeusCLI.parse(["todo", "list"]).command?.text == "list")
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["todo"]) }
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["todo", "add"]) }
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["todo", "nuke"]) }
    }
}
