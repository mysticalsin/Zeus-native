import Testing
@testable import ZeusCore

@Suite("Question sort")
struct QuestionSortTests {
    private let neither = QuestionSort(guides: false, webSearch: false)

    private func sort(_ question: String, knowledgeThrough year: Int = 2025) -> QuestionSort {
        QuestionSort.sort(question, knowledgeThrough: year)
    }

    @Test func whereIsTheButtonSetsTheGuideAndLeavesWebSearchOff() {
        let sorted = sort("Where is the button")
        #expect(sorted.guides)
        #expect(sorted.webSearch == false)
        #expect(sorted == QuestionSort(guides: true, webSearch: false))
        let longer = sort("hey, where is the button please")
        #expect(longer.guides)
        #expect(longer.webSearch == false)
    }

    @Test func walkMeThroughThisSetsTheGuideAndLeavesWebSearchOff() {
        let sorted = sort("walk me through this")
        #expect(sorted.guides)
        #expect(sorted.webSearch == false)
        let polite = sort("Please walk me through this.")
        #expect(polite == QuestionSort(guides: true, webSearch: false))
    }

    @Test func casePunctuationAndSpacingStillMatch() {
        let shouted = sort("WALK ME THROUGH THIS!")
        #expect(shouted.guides)
        #expect(shouted.webSearch == false)
        let spaced = sort("  where   is\nthe   button?  ")
        #expect(spaced.guides)
        #expect(spaced.webSearch == false)
        let contracted = sort("Where’s the button")
        #expect(contracted.guides)
        #expect(contracted.webSearch == false)
    }

    @Test func whereIsTheSaveButtonStillGuides() {
        let sorted = sort("where is the save button")
        #expect(sorted.guides)
        #expect(sorted.webSearch == false)
    }

    @Test func whatDoIClickLeavesWebSearchOff() {
        let sorted = sort("What do I click?")
        #expect(sorted.guides)
        #expect(sorted.webSearch == false)
    }

    @Test func aGuideQuestionThatNamesALaterYearLeavesWebSearchOff() {
        let sorted = sort("where is the button in 2026", knowledgeThrough: 2025)
        #expect(sorted.guides)
        #expect(sorted.webSearch == false)
        let today = sort("where is the button today")
        #expect(today.guides)
        #expect(today.webSearch == false)
        let latest = sort("where is the latest button")
        #expect(latest.guides)
        #expect(latest.webSearch == false)
    }

    @Test func walkMeThroughThisWeekIsALaterFactNotAGuide() {
        let sorted = sort("walk me through this week", knowledgeThrough: 2025)
        #expect(sorted.guides == false)
        #expect(sorted.webSearch)
        let news = sort("walk me through this week's news")
        #expect(news.guides == false)
        #expect(news.webSearch)
    }

    @Test func aYearAfterTheCutoffMayTurnWebSearchOn() {
        let sorted = sort("what shipped in 2026", knowledgeThrough: 2025)
        #expect(sorted.guides == false)
        #expect(sorted.webSearch)
        let budget = sort("walk me through the 2026 budget", knowledgeThrough: 2025)
        #expect(budget.guides == false)
        #expect(budget.webSearch)
        let edge = sort("what changed in 1991", knowledgeThrough: 1990)
        #expect(edge.webSearch)
        #expect(edge.guides == false)
    }

    @Test func aYearTheModelAlreadyKnowsLeavesWebSearchOff() {
        #expect(sort("what shipped in 2025", knowledgeThrough: 2025) == neither)
        #expect(sort("what shipped in 2024", knowledgeThrough: 2025) == neither)
        #expect(sort("what changed in 1990", knowledgeThrough: 1990) == neither)
        #expect(sort("what shipped in 2099", knowledgeThrough: 2099) == neither)
        #expect(sort("what shipped in 2100", knowledgeThrough: 2099) == neither)
    }

    @Test func todayLatestAndRightNowMayTurnWebSearchOn() {
        #expect(sort("what is the price today").webSearch)
        #expect(sort("what is the price today").guides == false)
        #expect(sort("the latest note").webSearch)
        #expect(sort("what is true right now").webSearch)
        #expect(sort("just announced this morning").webSearch)
        #expect(sort("the plan for this month").webSearch)
        #expect(sort("today's price").webSearch)
    }

    @Test func anOrdinaryQuestionSortsToNeither() {
        #expect(sort("what is 2 + 2") == neither)
        #expect(sort("press the button") == neither)
        #expect(sort("where is the menu") == neither)
        #expect(sort("nowhere is the button") == neither)
        #expect(sort("where is the buttonhole") == neither)
        #expect(sort("walk me through thisweek") == neither)
        let twice = sort("what is 2 + 2")
        #expect(sort("what is 2 + 2") == twice)
    }

    @Test func aBlankOrHugeQuestionSortsToNeither() {
        #expect(sort("") == neither)
        #expect(sort("   \n\t  ") == neither)
        #expect(sort("???") == neither)
        let base = "where is the button "
        let fitted = base + String(repeating: "a", count: QuestionSort.maximumCharacters - base.count)
        #expect(fitted.count == QuestionSort.maximumCharacters)
        #expect(sort(fitted).guides)
        #expect(sort(fitted).webSearch == false)
        #expect(sort(fitted + "a") == neither)
        let later = "what changed today " + String(repeating: "a", count: QuestionSort.maximumCharacters)
        #expect(later.count > QuestionSort.maximumCharacters)
        #expect(sort(later) == neither)
    }

    @Test func anUnusableCutoffDoesNotReadAYearAsLater() {
        #expect(sort("what shipped in 2026", knowledgeThrough: 0) == neither)
        #expect(sort("what shipped in 2026", knowledgeThrough: -4) == neither)
        #expect(sort("what shipped in 2026", knowledgeThrough: 1989) == neither)
        #expect(sort("what shipped in 2026", knowledgeThrough: 2100) == neither)
        let latest = sort("the latest note", knowledgeThrough: 0)
        #expect(latest.webSearch)
        #expect(latest.guides == false)
    }

    @Test func aGluedYearIsNotAYear() {
        #expect(sort("build 2026a", knowledgeThrough: 2025) == neither)
        #expect(sort("x2026 shipped", knowledgeThrough: 2025) == neither)
        #expect(sort("room 12026", knowledgeThrough: 2025) == neither)
    }

    @Test func theTwoFlagsAreNeverBothOn() {
        let samples = [
            "Where is the button",
            "walk me through this",
            "What do I click?",
            "where is the button in 2026",
            "what shipped in 2026",
            "what is the price today",
            "press the button",
            "",
        ]
        for sample in samples {
            let sorted = sort(sample, knowledgeThrough: 2025)
            #expect(sorted.guides == false || sorted.webSearch == false)
        }
    }
}
