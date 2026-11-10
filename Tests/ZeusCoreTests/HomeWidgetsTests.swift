import Foundation
import Testing
@testable import ZeusCore

@Suite struct HomeWidgetsTests {
    @Test func slotsDefaultToTodaysFour() {
        #expect(HomeSlots([]).kinds == [.music, .focus, .weather, .calendar])
        #expect(HomeSlots([nil, "", "nonsense", nil]).kinds == HomeSlots.defaults)
    }

    @Test func slotsReadIdsAndTitlesAndKeepUnknownAtDefault() {
        let slots = HomeSlots(["worldClock", "Clock", "future-widget", "Agenda"])
        #expect(slots.kinds == [.worldClock, .clock, .weather, .agenda])
        #expect(slots[1] == .worldClock && slots[4] == .agenda)
        #expect(slots.setting(2, to: .note)[2] == .note)
        #expect(slots.setting(2, to: .note)[1] == .worldClock)
    }

    @Test func settingIDsAreStable() {
        #expect(HomeSlots.settingIDs == (1...4).map { "home.widget.\($0)" })
        #expect(HomeWidgetKind.clock.variantSettingID == "home.variant.clock")
        #expect(HomeWidgetKind.allCases.count == 12)
    }

    @Test func variantsMatchGlance() {
        #expect(HomeWidgetKind.clock.variants.map(\.id) == ["analog", "digital", "elastic", "halo"])
        #expect(HomeWidgetKind.music.variants.map(\.id) == ["art", "disc", "cassette", "wave", "lyrics"])
        #expect(HomeWidgetKind.weather.variants.map(\.id) == ["summary", "hourly", "days", "feels", "wind"])
        #expect(HomeWidgetKind.calendar.variants.map(\.id) == ["next", "month", "week", "agenda"])
        #expect(HomeWidgetKind.focus.variants.isEmpty)
        #expect(HomeWidgetKind.weather.resolveVariant("Days") == "days")
        #expect(HomeWidgetKind.weather.resolveVariant("wind") == "wind")
        #expect(HomeWidgetKind.weather.resolveVariant("bogus") == "summary")
        #expect(HomeWidgetKind.clock.resolveVariant(nil) == "analog")
        #expect(HomeWidgetKind.note.resolveVariant("x") == "")
    }

    @Test func backdropsResolveAndAnimateOnlyWhenAllowed() {
        #expect(HomeBackdrop.allCases.count == 13) // off plus twelve
        #expect(HomeBackdrop.resolve("Fluted glass") == .flutedGlass)
        #expect(HomeBackdrop.resolve("lowPoly") == .lowPoly)
        #expect(HomeBackdrop.resolve("None") == .off)
        #expect(HomeBackdrop.resolve("zzz") == .off)
        #expect(HomeBackdrop.resolve(nil) == .off)
        #expect(HomeBackdrop.animates(.aurora, visible: true, reduceMotion: false))
        #expect(!HomeBackdrop.animates(.aurora, visible: true, reduceMotion: true))
        #expect(!HomeBackdrop.animates(.aurora, visible: false, reduceMotion: false))
        #expect(!HomeBackdrop.animates(.terrazzo, visible: true, reduceMotion: false))
        #expect(!HomeBackdrop.animates(.off, visible: true, reduceMotion: false))
    }
}

@Suite struct TabEditorTests {
    @Test func editorListsEveryCaseGenerically() {
        let layout = TopBarLayout(tabs: [.home, .chat])
        #expect(layout.editorEntries.map(\.tab) == TopBarTab.allCases)
        #expect(layout.editorEntries.filter(\.isOn).map(\.tab) == [.home, .chat])
        #expect(layout.removedTabs.count == TopBarTab.allCases.count - 2)
    }

    @Test func reorderTakesTheTargetsPlaceBothWays() {
        var layout = TopBarLayout(tabs: [.home, .chat, .todo, .shelf])
        layout.reorder(.chat, onto: .shelf)
        #expect(layout.tabs == [.home, .todo, .shelf, .chat])
        layout.reorder(.chat, onto: .todo)
        #expect(layout.tabs == [.home, .chat, .todo, .shelf])
        layout.reorder(.home, onto: .shelf)
        layout.reorder(.todo, onto: .home)
        #expect(layout.tabs.first == .home)
        #expect(layout.tabs.count == 4)
    }

    @Test func addRemoveAndTheRowLimit() {
        var layout = TopBarLayout(tabs: [.home, .chat])
        layout.append(.music)
        layout.append(.music)
        #expect(layout.tabs == [.home, .chat, .music])
        layout.remove(.chat)
        layout.remove(.home)
        #expect(layout.tabs == [.home, .music])
        var full = TopBarLayout(tabs: Array(TopBarTab.allCases.prefix(GlanceTopBar.maxTabs)))
        let extra = TopBarTab.allCases[GlanceTopBar.maxTabs]
        full.append(extra)
        #expect(!full.contains(extra))
        #expect(TopBarLayout.standard.trimmedToRow().tabs.count == GlanceTopBar.maxTabs)
    }

    @Test func editsSurviveEncodeDecodeAndUnknownFutureCasesAreDropped() {
        var layout = TopBarLayout(tabs: [.home, .chat, .todo])
        layout.reorder(.todo, onto: .chat)
        layout.append(.weather)
        let saved = layout.encoded()
        #expect(TopBarLayout.decode(saved).tabs == [.home, .todo, .chat, .weather])
        // A layout written by a later build that has a tab this one does not know.
        let future = #"["home","todo","waves-from-the-future","chat"]"#
        let decoded = TopBarLayout.decode(future)
        #expect(decoded.tabs == [.home, .todo, .chat])
        var edited = decoded
        edited.append(.music)
        #expect(TopBarLayout.decode(edited.encoded()).tabs == [.home, .todo, .chat, .music])
        #expect(TopBarLayout.decode(future, known: TopBarLayout.knownEncoded()).contains(.todo))
    }
}

@Suite struct CalendarQuickAddTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    /// Monday 2 Nov 2026, 10:30 UTC.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10, minute: 30))! }

    private func parse(_ text: String) -> CalendarQuickAdd.Parsed? { CalendarQuickAdd.parse(text, now: now, calendar: cal) }
    private func parts(_ date: Date) -> [Int] {
        let c = cal.dateComponents([.month, .day, .hour, .minute], from: date)
        return [c.month!, c.day!, c.hour!, c.minute!]
    }

    @Test func english() throws {
        let e = try #require(parse("lunch with Ana tomorrow at 1 pm"))
        #expect(e.title == "Lunch with Ana")
        #expect(parts(e.start) == [11, 3, 13, 0])
        #expect(e.end.timeIntervalSince(e.start) == 3600)
        #expect(!e.isAllDay && e.hadDate)
        #expect(parts(try #require(parse("Dentist on friday at 9:30am")).start) == [11, 6, 9, 30])
        #expect(parts(try #require(parse("Standup today at 3pm for 30 minutes")).start) == [11, 2, 15, 0])
        #expect(try #require(parse("Standup today at 3pm for 30 minutes")).end.timeIntervalSince(try #require(parse("Standup today at 3pm for 30 minutes")).start) == 1800)
    }

    @Test func noonTodayWhenStillAhead() throws {
        #expect(parts(try #require(parse("Call Sam at noon")).start) == [11, 2, 12, 0])
    }

    @Test func dayAloneIsAllDayAndTimeAloneRollsForward() throws {
        let all = try #require(parse("Ana's birthday on november 20"))
        #expect(all.isAllDay)
        #expect(parts(all.start)[0...1] == [11, 20])
        #expect(try #require(parse("Gym at 7 am")).start > now)
        let plain = try #require(parse("Write report"))
        #expect(!plain.hadDate)
        #expect(parts(plain.start) == [11, 2, 11, 0])
    }

    @Test func french() throws {
        let e = try #require(parse("déjeuner avec Ana demain à 13h"))
        #expect(e.title == "Déjeuner avec Ana")
        #expect(parts(e.start) == [11, 3, 13, 0])
        #expect(parts(try #require(parse("réunion vendredi à 9h30")).start) == [11, 6, 9, 30])
        #expect(try #require(parse("Dîner après-demain à 20h")).hadDate)
    }

    @Test func portuguese() throws {
        let e = try #require(parse("almoço com a Ana amanhã às 13h"))
        #expect(e.title == "Almoço com a Ana")
        #expect(parts(e.start) == [11, 3, 13, 0])
        #expect(parts(try #require(parse("dentista sexta às 15h30")).start) == [11, 6, 15, 30])
        #expect(parts(try #require(parse("jantar dia 20 de novembro às 20h")).start)[0...1] == [11, 20])
    }

    @Test func commandWordsAndCalendarPhrasesAreStripped() throws {
        #expect(try #require(parse("add lunch with Ana tomorrow at 1 pm to my calendar")).title == "Lunch with Ana")
        #expect(try #require(parse("schedule a meeting called Roadmap on friday at 2 pm")).title == "Roadmap")
        #expect(try #require(parse("agenda almoço amanhã às 13h na minha agenda")).title == "Almoço")
        #expect(parse("tomorrow at 1 pm") == nil)
        #expect(parse("   ") == nil)
    }
}

@Suite struct EventIntentTests {
    private func parse(_ text: String) -> FastIntent? { FastIntent.parse(text) }

    @Test func eventRuleFires() {
        #expect(parse("Hey Zeus, add lunch with Ana tomorrow at 1 pm") == .addEvent("add lunch with Ana tomorrow at 1 pm"))
        for phrase in ["schedule a meeting with Sam on friday at 2 pm", "create an event dentist tomorrow at 9am",
                       "add team sync to my calendar tomorrow at 10", "book lunch with Ana friday at noon",
                       "ajoute déjeuner avec Ana demain à 13h", "agenda almoço com a Ana amanhã às 13h",
                       "adiciona reunião segunda às 10h", "planifie une réunion vendredi à 14h"] {
            if case .addEvent = parse(phrase) {} else { Issue.record("not an event: \(phrase) -> \(String(describing: parse(phrase)))") }
        }
        #expect(parse("add lunch with Ana tomorrow at 1 pm")?.intentLabel == "calendar.add")
    }

    @Test func negativesStayWhereTheyWere() {
        #expect(parse("add milk tomorrow to my to-do list") == .addTodos(["milk tomorrow"]))
        #expect(parse("add milk to my list") == .addTodos(["milk"]))
        #expect(parse("remind me to call Mom on Friday") == .addTodos(["call Mom on Friday"]))
        for phrase in ["add lunch with Ana", "schedule", "what's on my calendar tomorrow", "book me a flight tomorrow at 9",
                       "add it tomorrow at 5", "create a project called zeus tomorrow", "add a todo tomorrow at 5",
                       "set a timer for 5 minutes", "add 5 minutes", "open calendar"] {
            if case .addEvent = parse(phrase) { Issue.record("wrongly an event: \(phrase)") }
        }
        #expect(parse("set a timer for 5 minutes") == .timer(seconds: 300))
    }
}
