import Testing
@testable import ZeusCore

@Suite struct HandsActTests {
    @Test func clickMenuTypeScrollDragWaitAndFailure() {
        var world = HandsWorld.fixture()
        let front = world.frontPid
        let pointer = world.cursor

        let save = world.perform(.click("Save", kind: "click"))
        #expect(save.ok)
        #expect(save.changed == "Save pressed")
        #expect(save.cue?.label == "Save")
        #expect(save.delivery == .accessibility)

        let menu = world.perform(.menu(["File", "Export"]))
        #expect(menu.ok)
        #expect(menu.changed == "File > Export")

        let typed = world.perform(.type("hello", into: "Search"))
        #expect(typed.ok)
        #expect(world.element("Search")?.value == "hello")

        let secret = world.perform(.type("nope", into: "Password"))
        #expect(!secret.ok)
        #expect(!secret.line.contains("hunter2"))
        #expect(secret.before == "Password secret")
        #expect(world.element("Password")?.value == "hunter2")

        let missing = world.perform(.click("Missing", kind: "click"))
        #expect(!missing.ok)
        #expect(missing.changed == "failed")
        #expect(missing.failure == "couldn't find Missing")

        let scrolled = world.perform(.scroll(-3))
        #expect(scrolled.ok)
        #expect(scrolled.delivery == .postToPid)
        #expect(world.scroll == -3)

        let dragged = world.perform(.drag("Handle", to: "Drop"))
        #expect(dragged.ok)
        #expect(world.element("Handle")?.frame.x == 100)
        #expect(world.element("Handle")?.frame.y == 40)

        let waited = world.perform(.wait(0.2))
        #expect(waited.ok)
        #expect(waited.changed == "waited 0.2s")

        let double = world.perform(.click("Save", kind: "double-click"))
        #expect(double.verb == "double-click Save")

        #expect(world.frontPid == front)
        #expect(world.cursor == pointer)
        #expect(world.deliveries.allSatisfy { $0 == .accessibility || $0 == .postToPid })
    }

    @Test func ownedEditsDoNotOverwriteSomeoneElsesText() {
        var world = HandsWorld.fixture()
        let title = world.perform(.type("mine", into: "Title"))
        #expect(!title.ok)
        #expect(world.element("Title")?.value == "theirs")
        _ = world.perform(.type("hello", into: "Search"))
        let again = world.perform(.type("hello there", into: "Search"))
        #expect(again.ok)
        #expect(world.element("Search")?.value == "hello there")
    }

    @Test func workBehindTypesWithoutTakingFocusAndStopsThePreview() {
        var world = HandsWorld.fixture()
        let front = world.frontPid
        let pointer = world.cursor
        let receipt = world.typeBehind("covered", into: "Note")
        #expect(receipt.ok)
        #expect(receipt.delivery == .postToPid)
        #expect(world.frontPid == front)
        #expect(world.cursor == pointer)
        #expect(world.element("Note")?.value == "covered")
        #expect(world.preview.streaming)
        #expect(world.preview.frames.count == 1)
        let opened = world.openPreview()
        #expect(opened)
        #expect(world.frontPid == 200)
        #expect(!world.preview.streaming)
        world = HandsWorld.fixture()
        _ = world.typeBehind("covered", into: "Note")
        world.endBehind()
        #expect(!world.preview.streaming)
        #expect(world.preview.frames.isEmpty)
        #expect(world.frontPid == front)
    }

    @Test func acceptanceReportPasses() {
        let report = HandsAcceptance.report()
        #expect(report.passed)
        #expect(report.text.contains("PASS"))
        #expect(!report.text.contains("hunter2"))
        #expect(report.log.contains("blocked"))
    }

    @Test func sendButtonClickWaits() {
        let intent = HandsGate.intent(clicking: "Send")
        guard case .send = intent else { Issue.record("send click"); return }
        guard case .approve = HandsGate.judge(intent!) else { Issue.record("card"); return }
        #expect(HandsGate.intent(clicking: "Save") == nil)
    }
}
