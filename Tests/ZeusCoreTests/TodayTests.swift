import Foundation
import Testing
@testable import ZeusCore

@Suite struct TodayTests {
    @Test func voiceAddsSeveral() {
        #expect(TodoVoice.parse("Add these to-dos: call Ana tomorrow, send the invoice Friday and book the dentist")
            == .add(["call Ana tomorrow", "send the invoice Friday", "book the dentist"]))
        #expect(TodoVoice.parse("remind me to water the plants") == .add(["water the plants"]))
        #expect(TodoVoice.parse("ajoute ces tâches : appeler Marie et payer le loyer") == .add(["appeler Marie", "payer le loyer"]))
        #expect(TodoVoice.parse("adiciona comprar pão e ligar para o João") == .add(["comprar pão", "ligar para o João"]))
        #expect(TodoVoice.parse("what do I have today?") == .today)
        #expect(TodoVoice.parse("give me my daily brief") == .brief)
        #expect(TodoVoice.parse("open Safari") == nil)
        #expect(TodoVoice.parse("todoist is great") == nil)
    }

    @Test func scansVaultForToday() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("brain-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vault) }
        let fm = FileManager.default
        for dir in ["Daily", "Meetings/prep", "_brain_index", "Projects"] {
            try fm.createDirectory(at: vault.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try #"{"folder":"Daily","format":"YYYY-MM-DD"}"#.write(to: vault.appendingPathComponent(".obsidian/daily-notes.json"), atomically: true, encoding: .utf8)
        try "# Today\n- [ ] Morning run\n- [x] Done thing\n".write(to: vault.appendingPathComponent("Daily/2026-10-31.md"), atomically: true, encoding: .utf8)
        try "- [ ] Ship deck 📅 2026-10-31\n- [ ] Old thing [due:: 2026-10-20]\n- [ ] Later 📅 2026-12-01\n".write(to: vault.appendingPathComponent("Projects/work.md"), atomically: true, encoding: .utf8)
        try "- [ ] Hidden 📅 2026-10-31\n".write(to: vault.appendingPathComponent("_brain_index/x.md"), atomically: true, encoding: .utf8)
        try "Agenda".write(to: vault.appendingPathComponent("Meetings/prep/2026-10-31 Acme.md"), atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9))!
        let summary = TodayScanner.scan(vault: vault, now: now, calendar: calendar)
        #expect(summary.dailyNote == "Daily/2026-10-31.md")
        #expect(Set(summary.tasks.map(\.title)) == ["Morning run", "Ship deck", "Old thing"])
        #expect(summary.tasks.first?.title == "Old thing")
        #expect(summary.tasks.first?.overdue == true)
        #expect(summary.meetings.map(\.title) == ["2026-10-31 Acme"])

        let brief = DailyBrief.text(summary: summary, events: [("Standup", "10:00")], zeusTodos: [TodoItem(title: "Call Ana", due: "2026-10-31")])
        #expect(brief.contains("1 event today: Standup at 10:00"))
        #expect(brief.contains("4 to-dos, 1 overdue"))
    }

    @Test func inboxIsTheOnlyWritablePlace() throws {
        let vault = URL(fileURLWithPath: "/tmp/v")
        #expect(BrainInbox.url(vault: vault, name: "brief.md")?.path == "/tmp/v/00_Inbox/from-zeus/brief.md")
        #expect(BrainInbox.url(vault: vault, name: "../../etc.md")?.path.hasPrefix("/tmp/v/00_Inbox/from-zeus/") == true)
    }
}
