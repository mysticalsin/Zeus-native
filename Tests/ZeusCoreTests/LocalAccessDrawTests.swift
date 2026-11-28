import Testing
@testable import ZeusCore

struct LocalAccessDrawTests {
    private func cards(_ plan: LocalAccessDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func placeDiskAndKeysFollowLocal() {
        let usual = LocalAccessDraw.plan(place: "Off", disk: "Off", keys: "Not allowed")
        #expect(cards(usual) == ["Local", "Place: Off", "Disk: Off", "Keys: Not allowed"])
        #expect(LocalAccessAsk.line(place: "Off", disk: "Off", keys: "Not allowed") == "Location is off, Full Disk Access is off, and keys are not allowed.")
        #expect(usual.boltCaption(at: 0) == "Local")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Keys: Not allowed")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(LocalAccessAsk.line(place: "Allowed", disk: "Allowed", keys: "Accessibility") == "Location is allowed, Full Disk Access is allowed, and keys are seen through Accessibility.")
        #expect(LocalAccessAsk.line(place: "Off", disk: "Off", keys: "Input Monitoring") == "Location is off, Full Disk Access is off, and keys are seen through Input Monitoring.")
        #expect(cards(LocalAccessDraw.plan(place: "Allowed", disk: "Off", keys: "Accessibility")) == ["Local", "Place: Allowed", "Disk: Off", "Keys: Accessibility"])
        #expect(cards(LocalAccessDraw.plan(place: "Denied", disk: "Off", keys: "Not allowed")) == ["Local", "Can't"])
        #expect(LocalAccessAsk.line(place: "Off", disk: "Off", keys: "Camera") == "I can't read location, disk, or key access.")
    }

    @Test func theOtherGrantsStayOffThisAsk() {
        #expect(LocalAccessAsk.matches("how's location set"))
        #expect(LocalAccessAsk.matches("Hey Zeus, is full disk access on?"))
        #expect(LocalAccessAsk.matches("local permission settings"))
        #expect(!LocalAccessAsk.matches("which other permissions"))
        #expect(!LocalAccessAsk.matches("is accessibility on"))
        #expect(!LocalAccessAsk.matches("which default agent"))
        #expect(!LocalAccessAsk.matches("how many notifications"))
    }
}
