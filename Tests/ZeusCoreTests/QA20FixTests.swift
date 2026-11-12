import Foundation
import Testing
@testable import ZeusCore

@Suite("QA20 clock")
struct QA20ClockTests {
    private var saoPaulo: TimeZone { TimeZone(identifier: "America/Sao_Paulo")! }

    private func at(hour: Int, minute: Int, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour, minute: minute))!
    }

    @Test func wallClockUsesTheInjectedZone() {
        let night = at(hour: 0, minute: 39, timeZone: saoPaulo)
        #expect(LocalClock.spoken(now: night, timeZone: saoPaulo) == "It's 12:39 AM.")
        #expect(LocalClock.spoken(now: night, timeZone: TimeZone(identifier: "UTC")!) == "It's 3:39 AM.")
        #expect(LocalClock.answer(for: "what time is it", now: night, timeZone: saoPaulo) == "It's 12:39 AM.")
        #expect(LocalClock.answer(for: "what time is it right now", now: night, timeZone: saoPaulo) == "It's 12:39 AM.")
        #expect(LocalClock.answer(for: "Hey Zeus, what time is it?", now: night, timeZone: saoPaulo) == "It's 12:39 AM.")
    }

    @Test func midnightNoonAndTwelveHourEdges() {
        #expect(LocalClock.spoken(now: at(hour: 0, minute: 0, timeZone: saoPaulo), timeZone: saoPaulo) == "It's 12:00 AM.")
        #expect(LocalClock.spoken(now: at(hour: 0, minute: 39, timeZone: saoPaulo), timeZone: saoPaulo) == "It's 12:39 AM.")
        #expect(LocalClock.spoken(now: at(hour: 12, minute: 0, timeZone: saoPaulo), timeZone: saoPaulo) == "It's 12:00 PM.")
        #expect(LocalClock.spoken(now: at(hour: 12, minute: 1, timeZone: saoPaulo), timeZone: saoPaulo) == "It's 12:01 PM.")
        #expect(LocalClock.spoken(now: at(hour: 14, minute: 47, timeZone: saoPaulo), timeZone: saoPaulo) == "It's 2:47 PM.")
        #expect(LocalClock.spoken(now: at(hour: 23, minute: 59, timeZone: saoPaulo), timeZone: saoPaulo) == "It's 11:59 PM.")
    }

    @Test func otherQuestionsStayOnTheBrain() {
        #expect(LocalClock.answer(for: "what time is the meeting") == nil)
        #expect(LocalClock.answer(for: "open Spotify") == nil)
        let answer = PersonaQueries.localAnswer(for: "what time is it", personality: .ultron)
        #expect(answer?.contains("AM.") == true || answer?.contains("PM.") == true)
    }

    @Test func instantPathUsesTheInjectedClock() {
        let night = at(hour: 0, minute: 39, timeZone: saoPaulo)
        #expect(InstantTable.timeAnswer(now: night, timeZone: saoPaulo) == "12:39 AM.")
        #expect(InstantTable.timeAnswer(now: night, timeZone: TimeZone(identifier: "UTC")!) == "3:39 AM.")
        #expect(InstantTable.spokenAnswer(for: "what time is it", now: night, timeZone: saoPaulo) == "12:39 AM.")
        #expect(InstantTable.route("what time is it", now: night, timeZone: saoPaulo) == .spoken("12:39 AM."))
        #expect(InstantTable.timeAnswer(now: at(hour: 0, minute: 0, timeZone: saoPaulo), timeZone: saoPaulo) == "12:00 AM.")
        #expect(InstantTable.timeAnswer(now: at(hour: 12, minute: 0, timeZone: saoPaulo), timeZone: saoPaulo) == "12:00 PM.")
        #expect(InstantTable.timeAnswer(now: at(hour: 12, minute: 1, timeZone: saoPaulo), timeZone: saoPaulo) == "12:01 PM.")
        #expect(InstantTable.timeAnswer(now: at(hour: 14, minute: 47, timeZone: saoPaulo), timeZone: saoPaulo) == "2:47 PM.")
        #expect(InstantTable.timeAnswer(now: at(hour: 23, minute: 59, timeZone: saoPaulo), timeZone: saoPaulo) == "11:59 PM.")
    }
}

@Suite("QA20 todo dates")
struct QA20TodoDateTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }

    /// Wednesday 4 Nov 2026, 00:39 in Sao Paulo. Friday is 6 Nov.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 0, minute: 39))!
    }

    @Test func noDateWordsMeansNoDueDate() {
        #expect(TodoQuickAdd.parse("buy milk", now: now, calendar: calendar) == ("buy milk", nil))
        #expect(TodoQuickAdd.parse("add a to-do: buy milk", now: now, calendar: calendar).due == nil)
        #expect(TodoQuickAdd.parse("buy 2 milk", now: now, calendar: calendar) == ("buy 2 milk", nil))
        #expect(TodoQuickAdd.parse("buy 12 eggs", now: now, calendar: calendar).due == nil)
    }

    @Test func tomorrowAndFridayStayNearNow() {
        #expect(TodoQuickAdd.parse("buy milk tomorrow", now: now, calendar: calendar) == ("buy milk", "2026-11-05"))
        #expect(TodoQuickAdd.parse("buy milk on Friday", now: now, calendar: calendar) == ("buy milk", "2026-11-06"))
        let friday = TodoQuickAdd.parse("on Friday", now: now, calendar: calendar)
        #expect(friday.due == "2026-11-06")
    }

    @Test func aFarYearIsNotADueDate() {
        let bogus = TodoQuickAdd.parse("ship it due 0784-06-02", now: now, calendar: calendar)
        #expect(bogus.due == nil)
        #expect(TodoQuickAdd.parse("due 1405-08-13", now: now, calendar: calendar).due == nil)
        #expect(!TodoQuickAdd.yearIsNear("0784-06-02", now: now, timeZone: calendar.timeZone))
        #expect(TodoQuickAdd.yearIsNear("2026-11-06", now: now, timeZone: calendar.timeZone))
    }

    @Test func persianCalendarStillStoresAGregorianDay() {
        var persian = Calendar(identifier: .persian)
        persian.timeZone = calendar.timeZone
        #expect(persian.component(.year, from: now) != 2026)
        #expect(TodoQuickAdd.dayString(now, calendar: persian) == "2026-11-04")
        #expect(TodoQuickAdd.parse("buy milk tomorrow", now: now, calendar: persian) == ("buy milk", "2026-11-05"))
        #expect(TodoQuickAdd.parse("buy milk", now: now, calendar: persian).due == nil)
    }

    @Test func poisonedLearningOffsetCannotBecomeYear784() {
        var learning = TodoLearning()
        learning.patterns = [
            .init(key: TodoLearning.key(for: "buy milk"), sampleTitle: "buy milk", timesSeen: 7,
                  dueOffsets: [-453781], lastSeen: now),
        ]
        #expect(learning.suggestDue(for: "buy milk", now: now, calendar: calendar) == nil)

        learning.patterns = [
            .init(key: TodoLearning.key(for: "buy milk"), sampleTitle: "buy milk", timesSeen: 7,
                  dueOffsets: [1, -226888, -453781], lastSeen: now),
        ]
        let suggestion = learning.suggestDue(for: "buy milk", now: now, calendar: calendar)
        #expect(suggestion?.due == "2026-11-05")

        learning.patterns = [
            .init(key: "buy", sampleTitle: "buy", timesSeen: 4, dueOffsets: [1], lastSeen: now),
        ]
        #expect(learning.suggestDue(for: "buy milk", now: now, calendar: calendar) == nil)
    }
}

@Suite("QA20 screenshot")
struct QA20ScreenshotTests {
    @Test func retinaBitmapIsTheWholeWindow() {
        let pixels = ScreenshotCapturePlan.pixelSize(pointWidth: 1080, pointHeight: 780, backingScale: 2)
        #expect(pixels == (2160, 1560))
        let scale = ScreenshotCapturePlan.contextScale(contextIsPointSpace: true, backingScale: 2)
        #expect(scale == 1)
        let visible = ScreenshotCapturePlan.visiblePointSize(pointWidth: 1080, pointHeight: 780, contextScale: scale)
        #expect(visible.width == 1080 && visible.height == 780)
        let cropped = ScreenshotCapturePlan.visiblePointSize(pointWidth: 1080, pointHeight: 780, contextScale: 2)
        #expect(cropped.width == 540 && cropped.height == 390)
        let oneX = ScreenshotCapturePlan.pixelSize(pointWidth: 1080, pointHeight: 780, backingScale: 1)
        #expect(oneX == (1080, 780))
    }

    @Test func aNamedPngIsWrittenExactlyThere() {
        #expect(ScreenshotCapturePlan.outputPath(base: "/tmp/x.png", windowName: "settings", filter: "settings") == "/tmp/x.png")
        #expect(ScreenshotCapturePlan.outputPath(base: "/tmp/x.png", windowName: "onboarding", filter: "onboarding") == "/tmp/x.png")
        #expect(ScreenshotCapturePlan.outputPath(base: "/tmp/qa7/s", windowName: "settings", filter: "settings") == "/tmp/qa7/s-settings.png")
        #expect(ScreenshotCapturePlan.outputPath(base: "/tmp/x.png", windowName: "settings", filter: nil) == "/tmp/x.png-settings.png")
        #expect(ScreenshotCapturePlan.outputPath(base: "/tmp/x.png", windowName: "settings", filter: "all") == "/tmp/x.png-settings.png")
    }
}

@Suite("QA20 ultron voice")
struct QA20VoiceTests {
    @Test func defaultPresetIsTheLocalEngineFirst() {
        #expect(UltronVoicePlan.presetTitle == "Ultron voice (default)")
        #expect(UltronVoicePlan.preferred(kokoroReady: true, elevenLabsKeyValid: true) == .elevenLabs)
        #expect(UltronVoicePlan.preferred(kokoroReady: true, elevenLabsKeyValid: false) == .kokoro)
        #expect(UltronVoicePlan.preferred(kokoroReady: false, elevenLabsKeyValid: true) == .elevenLabs)
        #expect(UltronVoicePlan.preferred(kokoroReady: false, elevenLabsKeyValid: false) == .system)
        #expect(UltronVoicePlan.engineLabel(.kokoro, kokoroVoice: "am_michael") == "Kokoro am_michael")
    }

    @Test func aRejectedKeyFallsBackAndLogsTheEngine() {
        #expect(UltronVoicePlan.afterRejection(status: 401, kokoroReady: true) == .kokoro)
        #expect(UltronVoicePlan.afterRejection(status: 401, kokoroReady: false) == .system)
        #expect(UltronVoicePlan.afterRejection(status: 402, kokoroReady: true) == .kokoro)
        #expect(UltronVoicePlan.afterRejection(status: 429, kokoroReady: true) == nil)
        #expect(UltronVoicePlan.afterRejection(status: 200, kokoroReady: true) == nil)
        let line = UltronVoicePlan.logLine(engine: "kokoro", voice: "am_michael")
        #expect(line == "engine=kokoro voice=am_michael")
        #expect(line.contains("engine=") && line.contains("voice="))
    }

    @Test func previewStaysSilentWithoutAudibleOK() {
        #expect(!UltronVoicePlan.previewPlaysAudio(audibleOK: nil))
        #expect(!UltronVoicePlan.previewPlaysAudio(audibleOK: ""))
        #expect(!UltronVoicePlan.previewPlaysAudio(audibleOK: "0"))
        #expect(UltronVoicePlan.previewPlaysAudio(audibleOK: "1"))
    }
}
