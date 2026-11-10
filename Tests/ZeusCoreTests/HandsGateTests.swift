import Foundation
import Testing
@testable import ZeusCore

@Suite struct HandsGateTests {
    private let blocked = [
        "rm file", "rm -rf build", "rm -r dir", "rm -f x", "/bin/rm file", "/usr/bin/rm -rf x",
        "env rm x", "env -i rm x", "command rm x", "command -p rm x", "nice rm x", "nohup rm x", "exec rm x",
        "sudo ls", "sudo -n true", "sudo rm x", "/usr/bin/sudo ls",
        "dd if=/dev/zero of=disk", "dd if=a of=b",
        "diskutil eraseDisk x", "diskutil list",
        "shutdown -h now", "shutdown",
        "git push", "git push origin", "git push --force", "git push -f", "git -C /tmp push",
        "git -C /tmp push origin main", "git --no-pager push", "/usr/bin/git push", "env git push",
        "git status && git push", "echo hi; rm x", "ls | rm", "FOO=1 rm x",
    ]

    private let allowed = [
        "ls", "echo rm", "echo 'rm -rf /'", "echo \"git push\"", "git status", "git log", "git diff",
        "git commit -m hi", "git pull", "git fetch", "cat file", "echo hi; git status",
    ]

    @Test func blocklistRefusesTheDeniedCommands() {
        for command in blocked {
            let reason = HandsBlocklist.reason(command)
            #expect(reason != nil)
            if command.contains("git push") || command.hasSuffix("git push") || command.contains("git push ") || command.contains("git -C") || command.contains("git --no-pager") {
                #expect(reason == "git push is blocked")
            }
        }
        #expect(HandsBlocklist.reason("rm -rf build") == "rm is blocked")
        #expect(HandsBlocklist.reason("sudo ls") == "sudo is blocked")
        #expect(HandsBlocklist.reason("dd if=/dev/zero of=disk") == "dd is blocked")
        #expect(HandsBlocklist.reason("diskutil list") == "diskutil is blocked")
        #expect(HandsBlocklist.reason("shutdown -h now") == "shutdown is blocked")
        #expect(HandsBlocklist.reason("git push origin main") == "git push is blocked")
    }

    @Test func quotedAndReadOnlyCommandsAreNotBlocked() {
        for command in allowed {
            #expect(HandsBlocklist.reason(command) == nil)
        }
    }

    @Test func deleteSendAndBuyWaitAndDoNothingUntilAllowed() {
        var session = HandsGateSession(taskID: "t")
        var log = HandsCommandLog()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let send = session.propose(.send(to: "ada@example.com", text: "Thursday works"), log: &log, at: date)
        guard case .approve(let preview) = send else { Issue.record("send"); return }
        #expect(preview.card == "Send\nTo ada@example.com\nThursday works")
        #expect(session.effects == 0)
        let denied = session.decide(allow: false, log: &log, at: date)
        #expect(denied == false)
        #expect(session.effects == 0)

        _ = session.propose(.delete(files: ["Notes.txt", "Draft.txt"]), log: &log, at: date)
        #expect(session.effects == 0)
        let plan = HandsGate.trash(["Notes.txt", "Draft.txt"])
        #expect(plan.command == "trash")
        #expect(!plan.usesRemove)
        let trashed = session.decide(allow: true, log: &log, at: date)
        #expect(trashed)
        #expect(session.effects == 1)

        _ = session.propose(.buy(item: "USB cable", price: "$12"), log: &log, at: date)
        #expect(session.effects == 1)
        guard case .approve(let buy) = HandsGate.judge(.buy(item: "USB cable", price: "$12")) else { Issue.record("buy"); return }
        #expect(buy.lines == ["USB cable", "$12"])
        let bought = session.decide(allow: true, forTask: true, log: &log, at: date)
        #expect(bought)
        #expect(session.effects == 2)
        let again = session.propose(.buy(item: "USB cable", price: "$12"), log: &log, at: date)
        #expect(again == .allow)
        #expect(session.effects == 3)

        var next = HandsGateSession(taskID: "other")
        let fresh = next.propose(.buy(item: "USB cable", price: "$12"), log: &log, at: date)
        guard case .approve = fresh else { Issue.record("task scope"); return }
        #expect(next.effects == 0)
    }

    @Test func blockedCommandsStayBlockedAfterAllow() {
        var session = HandsGateSession(taskID: "t")
        var log = HandsCommandLog()
        for command in ["rm -rf /", "sudo true", "dd if=a of=b", "diskutil eraseDisk", "shutdown", "git push"] {
            let verdict = session.propose(.shell(command), log: &log)
            guard case .block = verdict else { Issue.record("blocked command was allowed"); continue }
            let revived = session.decide(allow: true, forTask: true, log: &log)
            #expect(revived == false)
            #expect(session.effects == 0)
            #expect(log.contains(command: command))
        }
        #expect(session.propose(.shell("ls"), log: &log) == .allow)
        #expect(session.effects == 1)
    }

    @Test func changeFileWaitsWithThePathAndTheSummary() {
        guard case .approve(let preview) = HandsGate.judge(.changeFile(path: "Notes.txt", summary: "shorter")) else {
            Issue.record("change"); return
        }
        #expect(preview.card == "Change\nNotes.txt\nshorter")
    }

    @Test func logRoundTripNamesEveryVerdict() throws {
        var log = HandsCommandLog()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        log.record(command: "rm x", verdict: "blocked", outcome: "rm is blocked", at: date)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-hands-log-\(UUID().uuidString).log")
        try log.write(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("rm x\tblocked\trm is blocked"))
        try? FileManager.default.removeItem(at: url)
    }
}
