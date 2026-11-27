import Testing
@testable import ZeusCore

struct ShellBlockDrawTests {
    @Test func aBlockedShellNamesTheCommand() throws {
        let cases = [
            ("rm is blocked", "rm"),
            ("sudo is blocked", "sudo"),
            ("dd is blocked", "dd"),
            ("diskutil is blocked", "diskutil"),
            ("shutdown is blocked", "shutdown"),
            ("git push is blocked", "git push"),
        ]
        for (line, command) in cases {
            let plan = try #require(ShellBlockDraw.from(line: line))
            func cards(_ plan: ShellBlockDraw) -> [String] {
                plan.draw.marks.compactMap { mark in
                    if case .card(_, let text) = mark.shape { return text }
                    return nil
                }
            }
            #expect(cards(plan) == ["Blocked", command])
            #expect(plan.boltCaption(at: 0) == "Blocked")
            #expect(plan.boltCaption(at: 100) == command)
            #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
            #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        }
    }

    @Test func aDeclinedCommandAndOtherLinesAreNotBlocked() {
        #expect(ShellBlockDraw.from(line: "") == nil)
        #expect(ShellBlockDraw.from(line: "Okay, I won't run it.") == nil)
        #expect(ShellBlockDraw.from(line: "I couldn't put that tour together.") == nil)
        #expect(ShellBlockDraw.from(line: "rm is blocked now") == nil)
        #expect(ShellBlockDraw.from(line: "git pull is blocked") == nil)
    }
}
