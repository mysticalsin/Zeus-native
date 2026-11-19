import Foundation
import Testing
@testable import ZeusCore

@Suite("Meeting brief")
struct MeetingBriefTests {
    @Test func aSharedOrPresentingScreenShowsOnlyNameAndTime() {
        let full = MeetingBrief.card(name: "Ada", time: "3:00", role: "Counsel", company: "North", summary: "Met last quarter.",
                                     shared: false, presenting: false, captureKnown: true, expanded: false, contactsAllowed: true)
        #expect(full.summary == "Met last quarter.")
        let shared = MeetingBrief.card(name: "Ada", time: "3:00", role: "Counsel", company: "North", summary: "Met last quarter.",
                                       shared: true, presenting: false, captureKnown: true, expanded: true, contactsAllowed: true)
        #expect(shared.collapsed)
        #expect(shared.summary == nil)
        #expect(shared.role == nil)
        let unknown = MeetingBrief.card(name: "Ada", time: "3:00", role: "Counsel", company: "North", summary: "Met last quarter.",
                                        shared: false, presenting: false, captureKnown: false, expanded: false, contactsAllowed: true)
        #expect(unknown.collapsed && unknown.summary == nil)
        let opened = MeetingBrief.card(name: "Ada", time: "3:00", role: "Counsel", company: "North", summary: "Met last quarter.",
                                       shared: false, presenting: false, captureKnown: false, expanded: true, contactsAllowed: true)
        #expect(opened.summary == "Met last quarter.")
        #expect(MeetingBriefWindow.sharingType == "none")
    }

    @Test func contactsAreAskedOnlyForOneEmailWhenBriefsAreOn() {
        #expect(!MeetingBriefContacts.shouldRequest(featureOn: false, alreadyKnown: false))
        #expect(MeetingBriefContacts.shouldRequest(featureOn: true, alreadyKnown: false))
        #expect(!MeetingBriefContacts.shouldRequest(featureOn: true, alreadyKnown: true))
        let denied = MeetingBriefContacts.lookup(email: "ada@north.example", allowed: false, found: ("Counsel", "North"))
        #expect(denied.role == nil && denied.company == nil)
        let allowed = MeetingBriefContacts.lookup(email: "ada@north.example", allowed: true, found: ("Counsel", "North"))
        #expect(allowed.role == "Counsel" && allowed.company == "North")
    }

    @Test func historyKeepsAHashDateAndTitleAndDropsOldRows() throws {
        let record = MeetingBrief.historyRecord(email: "ada@north.example", date: Date(timeIntervalSince1970: 1_000), title: "Design review\nnotes body")
        #expect(!record.emailHash.contains("@"))
        #expect(!record.title.contains("notes"))
        let now = Date(timeIntervalSince1970: 1_000)
        let old = MeetingBrief.HistoryRecord(emailHash: "abc", date: now.addingTimeInterval(-(MeetingBrief.retention + 5)), title: "Old")
        #expect(MeetingBrief.keeping([record, old], now: now) == [record])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brief-\(UUID().uuidString)", isDirectory: true)
        let store = MeetingBriefStore(directory: root)
        try store.save([record], now: now)
        let folder = try FileManager.default.attributesOfItem(atPath: root.path)
        #expect((folder[.posixPermissions] as? NSNumber)?.uint16Value == MeetingBriefStore.directoryMode)
        let file = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("history.json").path)
        #expect((file[.posixPermissions] as? NSNumber)?.uint16Value == MeetingBriefStore.fileMode)
        let loaded = try store.load(now: now)
        #expect(loaded == [record])
        try store.clear()
        #expect(try store.load(now: now).isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    @Test func noteTextIsPlainAndShort() {
        let raw = "See <b>Ada</b> [site](https://north.example/a) and https://north.example/b for the plan."
        let plain = MeetingBrief.plain(raw, limit: 40)
        #expect(!plain.contains("<"))
        #expect(!plain.contains("http"))
        #expect(!plain.contains("]("))
        #expect(plain.count <= 40)
        #expect(plain.contains("Ada"))
    }

    @Test func externalIsAnExactDomainAndOneOutsiderCounts() {
        #expect(MeetingBrief.needsDomainSetup([]))
        #expect(MeetingBrief.isExternal(email: "ada@north.example", domains: []))
        #expect(!MeetingBrief.isExternal(email: "ada@north.example", domains: ["North.Example"]))
        #expect(MeetingBrief.isExternal(email: "ada@north.example", domains: ["example"]))
        #expect(MeetingBrief.meetingIsExternal(emails: ["a@north.example", "b@other.test"], domains: ["north.example"]))
        #expect(!MeetingBrief.meetingIsExternal(emails: ["a@north.example"], domains: ["north.example"]))
    }

    @Test func logsCarryNoAddressOrNote() {
        let line = MeetingBriefLog.line(recordCount: 2)
        #expect(line == "meeting brief 2")
        #expect(!line.contains("@"))
        #expect(MeetingBriefOffDevice.enabled == false)
        #expect(MeetingBriefOffDevice.sentFields.isEmpty)
    }
}
