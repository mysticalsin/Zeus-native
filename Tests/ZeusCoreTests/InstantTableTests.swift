import Foundation
import Testing
@testable import ZeusCore

@Suite("Instant answers")
struct InstantTableTests {
    private var zone: TimeZone { TimeZone(secondsFromGMT: 0)! }
    private var sample: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 15, minute: 4))!
    }

    @Test func capabilityAndArithmeticStayLocal() {
        #expect(InstantTable.route("what can you do") == .spoken("Voice, dictation, agents, your day in the notch, and whatever you point at on screen."))
        #expect(InstantTable.route("what do you do") != .brain)
        #expect(InstantTable.spokenAnswer(for: "what is 17 times 23") == "391.")
        #expect(InstantTable.spokenAnswer(for: "what is 10 plus 2") == "12.")
        #expect(InstantTable.spokenAnswer(for: "what is 10 minus 2") == "8.")
        #expect(InstantTable.route("open Spotify") == .fastCommand)
    }

    @Test func timeAndDateUseTheClock() {
        let time = InstantTable.spokenAnswer(for: "what time is it", now: sample, timeZone: zone)
        let date = InstantTable.spokenAnswer(for: "what is the date", now: sample, timeZone: zone)
        #expect(time == "3:04 PM.")
        #expect(date == "Tuesday, 3 November 2026.")
        #expect(InstantTable.route("what's today's date", now: sample, timeZone: zone) == .spoken("Tuesday, 3 November 2026."))
    }

    @Test func everyInstantIntentStaysUnderTheBudget() {
        let phrases = [
            "what can you do", "what do you do", "what is 17 times 23", "what time is it",
            "what is the date", "what day is it", "open Safari", "play some music",
            "put on some music", "play a song", "play something", "play some tunes",
            "start playing music", "queue up a song", "play some jazz on spotify",
            "find my notes about the Tokyo trip", "summarize this article in three bullets",
            "search the web for solid state batteries", "open Notes and summarize this",
        ]
        let start = ContinuousClock.now
        for phrase in phrases {
            _ = InstantTable.route(phrase, now: sample, timeZone: zone)
        }
        let duration = ContinuousClock.now - start
        let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        #expect(ms < Double(InstantTable.latencyBudgetMs))
    }

    @Test func filesPageAndWebDoNotUseAScreenshot() {
        #expect(InstantTable.route("find my notes about the Tokyo trip") == .files(query: "tokyo trip"))
        #expect(InstantTable.route("summarize this article in three bullets") == .page)
        #expect(InstantTable.route("search the web for solid state batteries") == .web(query: "solid state batteries"))
        #expect(!InstantTable.allowsScreenshots(.page))
        #expect(!InstantTable.allowsScreenshots(.web(query: "x")))
        #expect(InstantTable.allowsScreenshots(.brain))
        #expect(InstantTable.describe("what can you do") == "instant spoken")
        #expect(InstantTable.describe("why is the sky blue") == "brain")
    }

    @Test func mixedAskKeepsTheCommandAndTheRest() {
        #expect(InstantTable.route("open Notes and summarize this") == .mixed(command: "open Notes", rest: "summarize this"))
        #expect(InstantTable.route("open Spotify and play Daft Punk") == .fastCommand)
    }

    @Test func spotlightPicksTheNamedFileAndPageTextDropsTags() {
        let expression = SpotlightQuery.expression(for: "Tokyo trip")
        #expect(expression.contains("Tokyo"))
        #expect(expression.contains("kMDItemDisplayName"))
        #expect(expression.contains("kMDItemTextContent"))
        let paths = [
            "/Users/me/Notes/groceries.txt",
            "/Users/me/Notes/Tokyo trip.md",
            "/Users/me/Archive/tokyo-photos.jpg",
        ]
        #expect(SpotlightQuery.pick(paths: paths, query: "tokyo trip") == "/Users/me/Notes/Tokyo trip.md")
        let html = "<html><script>alert(1)</script><body><h1>Tokyo</h1><p>A short trip.</p></body></html>"
        let plain = PageText.plain(html)
        #expect(plain.contains("Tokyo"))
        #expect(plain.contains("A short trip."))
        #expect(!plain.contains("alert"))
        #expect(!plain.contains("<"))
    }

    @Test func mediaPlayResumesAPausedSessionInPlace() {
        #expect(MediaPlayPolicy.choose(hasSession: true, spotifyInstalled: true) == .mediaKey)
        #expect(MediaPlayPolicy.choose(hasSession: false, spotifyInstalled: true) == .resumeSpotify)
        #expect(MediaPlayPolicy.choose(hasSession: false, spotifyInstalled: false) == .mediaKey)
    }
}

@Suite("Brain route")
struct BrainRouteTests {
    @Test func fastestFirstRacesLocalThenAnthropic() {
        let order = BrainRoute.order(hasAnthropicKey: true, hasOpenAIKey: false, installed: [.codex, .gemini, .claude, .grok, .cursorAgent], exhausted: [])
        #expect(order.prefix(2) == [.ollamaHTTP, .anthropicAPI])
        #expect(order.last == .cursorAgent)
        #expect(BrainRoute.racePair(hasAnthropicKey: true, hasOpenAIKey: false, installed: [.codex], exhausted: []).count == 2)
    }

    @Test func exhaustedClaudeIsSkippedAndCursorStaysLast() {
        let order = BrainRoute.order(hasAnthropicKey: false, hasOpenAIKey: true, installed: Set(RouterEngine.allCases), exhausted: [.claude])
        #expect(!order.contains(.claude))
        #expect(order.contains(.openAIAPI))
        #expect(order.last == .cursorAgent)
    }

    @Test func budgetFixtureStaysUnderTheCeiling() {
        #expect(ModelBudget.withinBudget(ModelBudget.cheapFixture))
        #expect(ModelBudget.cheapFixture.count == 50)
        let cost = ModelBudget.median(ModelBudget.cheapFixture.map(\.cost))
        let latency = ModelBudget.median(ModelBudget.cheapFixture.map { Double($0.latencyMs) })
        #expect(cost <= ModelBudget.medianCostCeiling)
        #expect(latency <= Double(ModelBudget.medianLatencyCeilingMs))
    }

    @Test func escalationIsOnlyForFailureOrMultiStep() {
        #expect(!ModelBudget.shouldEscalate(task: .quickAnswer, failed: false))
        #expect(ModelBudget.shouldEscalate(task: .quickAnswer, failed: true))
        #expect(ModelBudget.shouldEscalate(task: .code, failed: false))
        #expect(ModelBudget.tier(task: .quickAnswer, failed: false, requestedDeep: false) == .fast)
        #expect(ModelBudget.tier(task: .research, failed: false, requestedDeep: false) == .deep)
        #expect(ModelBudget.promptFits(String(repeating: "a", count: 10_000)))
        #expect(!ModelBudget.promptFits(String(repeating: "a", count: 10_001)))
    }

    @Test func aRevisedSpeculativeRunHasNoSideEffects() {
        var ahead = AheadBrain()
        #expect(AheadBrain.pauseMs == 700)
        #expect(ahead.consider("why is the sky") == .start(1))
        #expect(ahead.consider("why is the sky") == .wait)
        #expect(ahead.consider("why is the sky blue today") == .dropAndStart(2))
        #expect(ahead.dropped == 1)
        #expect(ahead.sideEffects == 0)
        #expect(!ahead.matches("why is the sky"))
        #expect(ahead.matches("why is the sky blue today"))
        ahead.discard()
        #expect(ahead.sideEffects == 0)
        #expect(ahead.generation == 0)
        #expect(ahead.consider("open Safari") == .ignore)
        #expect(ahead.consider("what can you do") == .ignore)
        #expect(ahead.consider("summarize this article") == .ignore)
    }

    @Test func warmthAndClaudeFlag() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(BrainWarmth.due(last: nil, now: now))
        #expect(!BrainWarmth.due(last: now, now: now.addingTimeInterval(10)))
        #expect(BrainWarmth.due(last: now, now: now.addingTimeInterval(BrainWarmth.interval)))
        #expect(ClaudeLaunch.supportsStrictMCP("usage: claude --strict-mcp-config"))
        #expect(!ClaudeLaunch.supportsStrictMCP("usage: claude -p"))
    }
}
