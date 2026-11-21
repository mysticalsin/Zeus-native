import Foundation
import Testing
@testable import ZeusCore

/// The page copy, the switch, and the reader lifetime. Synthetic rows only.
@Suite("Local to-do and agenda page")
struct LocalTodoAgendaSurfaceTests {
    private let zone = TimeZone(identifier: "America/New_York")!
    private let now = LocalTodoAgendaSurfaceTests.instant(2026, 11, 21, 10, 0, zone: "America/New_York")

    private static func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, zone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func own(_ title: String, _ meta: String) -> LocalTodoAgendaOwnItem {
        LocalTodoAgendaOwnItem(title: title, meta: meta)
    }

    private func surface(_ phase: LocalTodoAgendaPhase, ownItems: [LocalTodoAgendaOwnItem] = [], reduceMotion: Bool = false) -> LocalTodoAgendaSurface {
        LocalTodoAgendaSurfaceMap.make(phase: phase, ownItems: ownItems, reduceMotion: reduceMotion)
    }

    private func populated() -> LocalTodoAgendaPhase {
        .populated(LocalTodoAgendaView(
            todos: [
                LocalTodoLine(id: "notes", title: "Send the notes", listName: "Tasks", dueLabel: "Overdue"),
                LocalTodoLine(id: "milk", title: "Buy oat milk", listName: "Tasks", dueLabel: "Today 17:00"),
                LocalTodoLine(id: "later", title: "File the receipt", listName: "Tasks", dueLabel: "2 Dec 09:00"),
                LocalTodoLine(id: "none", title: "Someday", listName: "Tasks", dueLabel: "No date"),
            ],
            agenda: [
                LocalAgendaLine(id: "offsite", title: "Offsite", calendarName: "Calendar", when: "All day · 3 days", start: now),
                LocalAgendaLine(id: "standup", title: "Standup", calendarName: "Calendar", when: "07:00–08:00 · Los Angeles", start: now.addingTimeInterval(60)),
            ]))
    }

    // MARK: Copy

    @Test func offKeepsZeussListAndTellsYouTheReadIsOff() {
        let page = surface(.off, ownItems: [own("Write the brief", "Today")])
        #expect(page.voiceOverLabel == "off, To-do and Agenda")
        #expect(page.showsOwnList)
        #expect(page.replacesImmediately)
        #expect(page.loadingBarMoves == false)
        #expect(page.left.kicker == "To-do")
        #expect(page.left.head == "Kept on this Mac")
        #expect(page.left.note == "Microsoft tasks stay off.")
        #expect(page.left.groups.map(\.rows.map(\.title)) == [["Write the brief"]])
        #expect(page.left.groups.first?.rows.first?.meta == "Today")
        #expect(page.left.grantsAccess == false)
        #expect(page.right.kicker == "Agenda")
        #expect(page.right.head == "Not reading Outlook")
        #expect(page.right.body == "Turn on Tasks and agenda from this Mac. Zeus does not sign in.")
        #expect(page.right.grantsAccess == false)
    }

    @Test func permissionIsTextAndDoesNotGrantAccess() {
        let page = surface(.permissionNeeded, ownItems: [own("Write the brief", "Today")])
        #expect(page.voiceOverLabel == "permission needed, To-do and Agenda")
        #expect(page.showsOwnList == false)
        #expect(page.left.head == "macOS will ask")
        #expect(page.left.body == "Calendars and Reminders, read only. The system sheet is the ask. This page has no control that grants it.")
        #expect(page.right.head == "Same prompt")
        #expect(page.right.body == "Outlook is read from the calendars already on this Mac.")
        #expect(page.left.grantsAccess == false)
        #expect(page.right.grantsAccess == false)
        #expect(page.left.groups.isEmpty)
        #expect(page.right.groups.isEmpty)
    }

    @Test func deniedStaysClosedAndNamesSystemSettings() {
        let access = LocalAccessPair(events: .denied, reminders: .restricted)
        let page = surface(.denied(access))
        #expect(page.voiceOverLabel == "denied, To-do and Agenda")
        #expect(page.left.head == "Reminders stays closed")
        #expect(page.left.warns)
        #expect(page.left.body == "Zeus will not ask again from here. System Settings, Privacy & Security, can allow it.")
        #expect(page.right.head == "Calendars stays closed")
        #expect(page.right.warns)
        #expect(page.right.body == "The lists already in Zeus are unchanged.")
        #expect(page.left.grantsAccess == false)
    }

    @Test func loadingNamesTheReadAndMovesOnlyWhenReduceMotionIsOff() {
        let moving = surface(.loading, reduceMotion: false)
        #expect(moving.voiceOverLabel == "loading, To-do and Agenda")
        #expect(moving.loadingBarMoves)
        #expect(moving.left.head == "Loading")
        #expect(moving.left.loading)
        #expect(moving.left.body == "Reading reminders the Mac already has.")
        #expect(moving.right.head == "Loading")
        #expect(moving.right.loading)
        #expect(moving.right.body == "Reading today's events.")
        let still = surface(.loading, reduceMotion: true)
        #expect(still.loadingBarMoves == false)
        #expect(still.left.loading)
        #expect(still.left.head == "Loading")
        let quiet = surface(.off, reduceMotion: false)
        #expect(quiet.loadingBarMoves == false)
    }

    @Test func emptySaysNothingIsDueAndNothingIsToday() {
        let page = surface(.empty)
        #expect(page.voiceOverLabel == "empty, To-do and Agenda")
        #expect(page.left.head == "Nothing due")
        #expect(page.left.body == "No open Microsoft tasks.")
        #expect(page.right.head == "Nothing today")
        #expect(page.right.body == "The Exchange calendar has no event on this day.")
        #expect(page.left.groups.isEmpty)
        #expect(page.right.groups.isEmpty)
    }

    @Test func populatedRowsKeepOrderAndPutUndatedTasksInTheirOwnGroup() {
        let page = surface(populated())
        #expect(page.voiceOverLabel == "populated, To-do and Agenda")
        #expect(page.showsOwnList == false)
        #expect(page.left.kicker == "To-do")
        #expect(page.left.head == "From Reminders")
        #expect(page.right.kicker == "Agenda")
        #expect(page.right.head == "From the Mac's calendars")
        #expect(page.left.groups.map(\.name) == ["", "No date"])
        #expect(page.left.groups[0].rows.map(\.title) == ["Send the notes", "Buy oat milk", "File the receipt"])
        #expect(page.left.groups[0].rows.map(\.meta) == ["Overdue", "Today 17:00", "2 Dec 09:00"])
        #expect(page.left.groups[0].rows.map(\.emphasized) == [true, false, false])
        #expect(page.left.groups[1].name == "No date")
        #expect(page.left.groups[1].rows.map(\.title) == ["Someday"])
        #expect(page.left.groups[1].rows.map(\.meta) == ["No date"])
        #expect(page.right.groups.map(\.name) == [""])
        #expect(page.right.groups[0].rows.map(\.title) == ["Offsite", "Standup"])
        #expect(page.right.groups[0].rows.map(\.meta) == ["All day · 3 days", "07:00–08:00 · Los Angeles"])
        #expect(page.right.groups[0].rows.allSatisfy { !$0.emphasized })
    }

    @Test func undatedTasksAreAGroupEvenWhenNothingElseIsDue() {
        let phase = LocalTodoAgendaPhase.populated(LocalTodoAgendaView(
            todos: [LocalTodoLine(id: "none", title: "Someday", listName: "Tasks", dueLabel: "No date")],
            agenda: []))
        let page = surface(phase)
        #expect(page.left.groups.map(\.name) == ["No date"])
        #expect(page.right.groups.isEmpty)
    }

    @Test func anErrorSaysTheReadFailedAndNothingChanged() {
        let page = surface(.error(.readFailed))
        #expect(page.voiceOverLabel == "error, To-do and Agenda")
        #expect(page.left.head == "Could not read")
        #expect(page.left.warns)
        #expect(page.left.body == "The reminders on this Mac could not be read. Nothing was changed.")
        #expect(page.right.head == "Could not read")
        #expect(page.right.warns)
        #expect(page.right.body == "Try again from the setting. Zeus does not sign in to try another way.")
    }

    @Test func aMissingAppHasBothReadings() {
        let absent = surface(.missingApp(.applicationsNotInstalled))
        #expect(absent.voiceOverLabel == "app missing (a), To-do and Agenda")
        #expect(absent.left.kicker == "Not installed")
        #expect(absent.left.head == "Nothing to read")
        #expect(absent.left.body == "Outlook and To Do are not on this Mac, and Calendar has no Exchange account.")
        #expect(absent.right.head == "Nothing to read")
        #expect(absent.right.body == "No Exchange or Outlook calendar source on this Mac.")
        let unlisted = surface(.missingApp(.notInMacAccounts))
        #expect(unlisted.voiceOverLabel == "app missing (b), To-do and Agenda")
        #expect(unlisted.left.kicker == "Not in the Mac's calendars")
        #expect(unlisted.left.head == "Add the account on the Mac")
        #expect(unlisted.left.body == "Outlook is on this Mac. Its calendar is not in the Mac's calendars. System Settings, Internet Accounts. Zeus does not sign in.")
        #expect(unlisted.right.head == "Not in the Mac's calendars")
        #expect(unlisted.right.body == "Zeus does not reach into Outlook.")
    }

    @Test func everyPhaseReplacesTextImmediatelyAndGrantsNothing() {
        let phases: [LocalTodoAgendaPhase] = [
            .off, .permissionNeeded, .denied(LocalAccessPair(events: .denied, reminders: .denied)),
            .loading, .missingApp(.applicationsNotInstalled), .missingApp(.notInMacAccounts),
            .empty, populated(), .error(.readFailed),
        ]
        #expect(phases.count == 9)
        for phase in phases {
            let page = surface(phase, ownItems: [own("Write the brief", "Today")])
            #expect(page.replacesImmediately)
            #expect(page.left.grantsAccess == false)
            #expect(page.right.grantsAccess == false)
            #expect(page.voiceOverLabel.hasSuffix(", To-do and Agenda"))
        }
    }

    // MARK: Reader lifetime

    @Test func switchingOffDropsTheReaderAndALateReadCannotReturn() {
        var session = LocalTodoAgendaSession()
        let asking = session.reduce(.setEnabled(true), now: now, timeZone: zone)
        session = asking.0
        #expect(asking.1 == [.requestAccess])
        #expect(session.holdsReader)
        let allowed = LocalAccessPair(events: .allowed, reminders: .allowed)
        let reading = session.reduce(.permission(allowed), now: now, timeZone: zone)
        session = reading.0
        #expect(reading.1 == [.read(generation: 1)])
        #expect(session.machine.phase == .loading)
        #expect(session.holdsReader)
        let off = session.reduce(.setEnabled(false), now: now, timeZone: zone)
        #expect(off.0.machine.phase == .off)
        #expect(off.0.machine.enabled == false)
        #expect(off.0.holdsReader == false)
        #expect(off.1 == [.dropReader])
        let late = off.0.reduce(.loaded(generation: 1, LocalMicrosoftSnapshot(
            todos: [LocalTodoRecord(id: "1", title: "Buy oat milk", listName: "Tasks", sourceName: "Exchange", sourceKind: "exchange", due: nil, isAllDay: true, timeZoneIdentifier: zone.identifier, completed: false)],
            agenda: [],
            presence: LocalAppPresence(outlookInstalled: true, toDoInstalled: true, microsoftSources: ["Exchange"]))), now: now, timeZone: zone)
        #expect(late.0.machine.phase == .off)
        #expect(late.1.isEmpty)
        let again = late.0.reduce(.setEnabled(false), now: now, timeZone: zone)
        #expect(again.1.isEmpty)
        #expect(again.0.holdsReader == false)
    }

    @Test func aReadWhileAlreadyAllowedHoldsTheReaderUntilTheSwitchGoesOff() {
        var session = LocalTodoAgendaSession()
        let allowed = LocalAccessPair(events: .allowed, reminders: .denied)
        let primed = session.reduce(.refresh(allowed), now: now, timeZone: zone)
        #expect(primed.1.isEmpty)
        #expect(primed.0.holdsReader == false)
        let reading = primed.0.reduce(.setEnabled(true), now: now, timeZone: zone)
        #expect(reading.1 == [.read(generation: 1)])
        #expect(reading.0.holdsReader)
        let off = reading.0.reduce(.setEnabled(false), now: now, timeZone: zone)
        #expect(off.1 == [.dropReader])
        #expect(off.0.holdsReader == false)
        #expect(off.0.machine.generation == 2)
    }

    // MARK: Import and logs

    @Test func anImportCannotTurnTheSwitchOn() throws {
        #expect(LocalTodoAgendaImport.blocksEnable(id: LocalTodoAgendaSetting.id, value: "true"))
        #expect(LocalTodoAgendaImport.blocksEnable(id: LocalTodoAgendaSetting.id, value: "false") == false)
        #expect(LocalTodoAgendaImport.blocksEnable(id: "tiling.enabled", value: "true") == false)
        #expect(LocalTodoAgendaImport.accepted(current: "false", imported: "true") == "false")
        #expect(LocalTodoAgendaImport.accepted(current: "true", imported: "false") == "false")
        #expect(LocalTodoAgendaImport.accepted(current: "false", imported: "false") == "false")
        let store = try repoText("Sources/Zeus/App/SettingsStore.swift")
        #expect(store.contains("\"\(LocalTodoAgendaSetting.id)\""))
        #expect(store.contains("LocalTodoAgendaImport.blocksEnable"))
        let never = try #require(store.split(separator: "\n").first { $0.contains("neverEnabledByImport") == false && $0.contains("\"\(LocalTodoAgendaSetting.id)\"") })
        #expect(never.contains("\"\(LocalTodoAgendaSetting.id)\""))
    }

    @Test func logLinesCarryNoCalendarOrSourceTitle() throws {
        let kinds: [LocalTodoAgendaLog.Kind] = [.switchedOn, .switchedOff, .readStarted, .readFinished, .readFailed, .accessAsked, .readerDropped]
        let hidden = ["Offsite", "Standup", "Exchange", "Outlook", "Calendar", "Buy oat milk", "Work"]
        var seen: Set<String> = []
        for kind in kinds {
            let line = LocalTodoAgendaLog.line(kind)
            seen.insert(line)
            #expect(line.hasPrefix("local agenda "))
            for title in hidden {
                #expect(!line.localizedCaseInsensitiveContains(title))
            }
        }
        #expect(seen.count == kinds.count)
        let source = try repoText("Sources/ZeusCore/LocalTodoAgenda/LocalTodoAgendaSurface.swift")
        let log = source.split(separator: "\n").drop { !$0.contains("enum LocalTodoAgendaLog") }
        let body = log.prefix(40).joined(separator: "\n")
        #expect(!body.contains("calendarName"))
        #expect(!body.contains("sourceName"))
        #expect(!body.contains("source.title"))
    }

    @Test func agendaDataStaysOnThisMacUnlessTheUserAsks() throws {
        #expect(LocalTodoAgendaPrivacy.staysLocal == "Agenda data is never sent to an LLM or the network unless the user explicitly asks.")
        let files = [
            "Sources/ZeusCore/LocalTodoAgenda/LocalTodoAgendaSurface.swift",
            "Sources/Zeus/LocalTodoAgenda/LocalTodoAgendaController.swift",
            "specs/010-local-todo-agenda/spec.md",
        ]
        for relative in files {
            let text = try repoText(relative)
            #expect(text.contains(LocalTodoAgendaPrivacy.staysLocal), relative)
        }
    }

    @Test func thePageSourceDoesNotScopeAccountsLogTitlesOrWrite() throws {
        let files = [
            "Sources/ZeusCore/LocalTodoAgenda/LocalTodoAgendaSurface.swift",
            "Sources/Zeus/LocalTodoAgenda/LocalTodoAgendaController.swift",
            "Sources/Zeus/LocalTodoAgenda/LocalTodoAgendaPanels.swift",
        ]
        let forbidden = [
            "account scoping", "account-scoped", "scopes to the account", "scoped to the account",
            "save(", "remove(", "commit(", "NSAppleScript", "osascript", "tell application",
            "URLSession", "MSAL", "Entra", "SecItem", "HTTPCookie", "Group Containers",
            "Library/Containers", "microsoft.graph", "print(", "Logger(", "os_log", "NSLog",
        ]
        for relative in files {
            let text = try repoText(relative)
            for token in forbidden {
                #expect(!text.contains(token), "\(relative) contains \(token)")
            }
        }
        let controller = try repoText("Sources/Zeus/LocalTodoAgenda/LocalTodoAgendaController.swift")
        #expect(controller.contains("func dropReader()"))
        #expect(controller.contains("task?.cancel()"))
        #expect(controller.contains("task = nil"))
        #expect(controller.contains("reader = nil"))
        #expect(controller.contains("store = nil"))
        #expect(controller.contains("EKEventStore()"))
        #expect(!controller.contains("= EKEventStore()"))
        let panels = try repoText("Sources/Zeus/LocalTodoAgenda/LocalTodoAgendaPanels.swift")
        #expect(panels.contains("accessibilityLabel(surface.voiceOverLabel)"))
        #expect(panels.contains("loadingBarMoves"))
        #expect(!panels.contains("Button"))
        let page = try repoText("Sources/Zeus/TopBar/TodoPage.swift")
        #expect(page.contains("LocalTodoAgendaSurfaceMap.make"))
        #expect(page.contains("showsOwnList"))
        #expect(!page.contains("account scoping"))
        let spec = try repoText("specs/010-local-todo-agenda/spec.md")
        #expect(spec.contains("not account scoping"))
        #expect(spec.contains("source-name and source-kind filter"))
    }
}

private func repoRoot() throws -> URL {
    if let given = ProcessInfo.processInfo.environment["ZEUS_REPO_ROOT"] {
        return URL(fileURLWithPath: given)
    }
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<8 {
        url.deleteLastPathComponent()
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            return url
        }
    }
    throw SurfaceRepoError.missing
}

private func repoText(_ relative: String) throws -> String {
    try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
}

private enum SurfaceRepoError: Error { case missing }
