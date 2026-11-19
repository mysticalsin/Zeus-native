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

/// The talk key gestures, hold to talk or double-tap to latch listening on until the next tap, now driven through the
/// voice key machine (docs/VOICE-KEY-MACHINE-PLAN.md part 5) with `confirm` 0. Each test keeps its old timeline:
/// `stop` reads `.send`, `stopLater(0.4)` reads `.wake(after: 0.4)`, `cancelPendingStop` reads no effect, `cancelFromEsc`
/// reads `abandon`. The `.wake(after: 0.25)` beside a start is the machine's own look at the live modifiers.
@Suite struct TalkKeyLatchTests {
    typealias Rig = VoiceKeyMachineTests.Rig
    private static let ctrl = VoiceKeyMachineTests.ctrl, opt = VoiceKeyMachineTests.opt
    private func makeRig() -> Rig { Rig(VoiceKeyMachineTests.talk()) }

    @Test func holdToTalk() {
        var rig = makeRig()
        #expect(rig.press(Self.ctrl, Self.opt, at: 0) == [.start, .wake(after: 0.25)])
        #expect(rig.release(Self.opt, Self.ctrl, at: 1.2) == [.send])
    }

    @Test func singleTapStopsAfterTheGap() {
        var rig = makeRig()
        #expect(rig.press(Self.ctrl, Self.opt, at: 0) == [.start, .wake(after: 0.25)])
        #expect(rig.release(Self.opt, Self.ctrl, at: 0.1) == [.wake(after: 0.4)])
        #expect(rig.tick(at: 0.5) == [.send])
        #expect(rig.press(Self.ctrl, Self.opt, at: 2) == [.start, .wake(after: 0.25)])
    }

    @Test func doubleTapLatchesUntilTheNextTap() {
        var rig = makeRig()
        #expect(rig.press(Self.ctrl, Self.opt, at: 0) == [.start, .wake(after: 0.25)])
        #expect(rig.release(Self.opt, Self.ctrl, at: 0.1) == [.wake(after: 0.4)])
        #expect(rig.press(Self.ctrl, Self.opt, at: 0.3) == [.wake(after: 0.25)], "the pending stop is dropped by the phase, not by an effect")
        #expect(rig.release(Self.opt, Self.ctrl, at: 0.4) == [])
        #expect(rig.machine.isLatched)
        #expect(rig.tick(at: 0.5) == [], "the gap wake of the first tap finds the turn latched")
        #expect(rig.press(Self.ctrl, Self.opt, at: 5) == [.send])
        #expect(rig.release(Self.opt, Self.ctrl, at: 5.1) == [])
        #expect(rig.press(Self.ctrl, Self.opt, at: 6) == [.start, .wake(after: 0.25)])
    }

    @Test func tapThenHoldIsANormalHold() {
        var rig = makeRig()
        rig.press(Self.ctrl, Self.opt, at: 0)
        rig.release(Self.opt, Self.ctrl, at: 0.1)
        #expect(rig.press(Self.ctrl, Self.opt, at: 0.3) == [.wake(after: 0.25)])
        #expect(rig.release(Self.opt, Self.ctrl, at: 2) == [.send])
        #expect(!rig.machine.isLatched)
    }

    @Test func escapeCancelsHoldOrLatch() {
        var rig = makeRig()
        rig.press(Self.ctrl, Self.opt, at: 0)
        #expect(rig.machine.phase != .idle)
        #expect(rig.abandon() == [])
        #expect(rig.machine.phase == .idle)
        #expect(rig.release(Self.opt, Self.ctrl, at: 1) == [], "the key-up after the cancel sends nothing")
        rig.tap([Self.ctrl, Self.opt], at: 2, length: 0.1)
        rig.tap([Self.ctrl, Self.opt], at: 2.3, length: 0.1)
        #expect(rig.machine.isLatched)
        #expect(rig.abandon() == [])
        #expect(!rig.machine.isLatched)
        #expect(rig.machine.phase == .idle)
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
