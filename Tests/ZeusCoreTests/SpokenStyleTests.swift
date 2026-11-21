import Foundation
import Testing
@testable import ZeusCore

@Suite("Spoken style")
struct SpokenStyleTests {
    func hear(_ text: String, _ language: SpokenLanguage = .english, maxSentences: Int? = nil) -> SpokenTranscript {
        SpokenStyle.transform(SpokenRequest(text: text, language: language, maxSentences: maxSentences))
    }

    func stageTitle(_ stage: SpokenStage) -> String {
        switch stage {
        case .markdown: "markdown"
        case .links: "links"
        case .quantities: "quantities"
        case .contractions: "contractions"
        case .clauses: "clauses"
        case .answerFirst: "answerFirst"
        }
    }

    @Test func emptyEnglishIsSilent() {
        let transcript = hear("")
        #expect(transcript.runs.isEmpty)
        #expect(transcript.spokenText.isEmpty)
    }

    @Test func emptyFrenchIsSilent() {
        let transcript = hear("", .french)
        #expect(transcript.runs.isEmpty)
        #expect(transcript.spokenText.isEmpty)
    }

    @Test func whitespaceOnlyIsSilent() {
        #expect(hear("  \n\t  ").runs.isEmpty)
    }

    @Test func emojiIsNotSpoken() {
        #expect(hear("Ship it 🚀 now.").spokenText == "Ship it now.")
    }

    @Test func emojiAloneIsSilent() {
        #expect(hear("🚀").runs.isEmpty)
        #expect(hear("🚀", .french).spokenText.isEmpty)
    }

    @Test func skinToneEmojiIsNotSpoken() {
        #expect(hear("OK 👍🏽").spokenText == "OK.")
    }

    @Test func inlineCodeLosesBackticks() {
        #expect(hear("`code`").spokenText == "code.")
        #expect(hear("Run `code` now.").spokenText == "Run code now.")
        #expect(!hear("`code`").spokenText.contains("`"))
    }

    @Test func codeFenceBecomesASummaryAndHidesTheBody() {
        let fenced = """
        Look:
        ```swift
        print(secret)
        ```
        Done.
        """
        let transcript = hear(fenced)
        #expect(transcript.spokenText == "Look Here's the code. Done.")
        #expect(!transcript.spokenText.contains("print"))
        #expect(!transcript.spokenText.contains("secret"))
        #expect(!transcript.spokenText.contains("`"))
        #expect(transcript.runs == [
            SpokenRun(text: "Look", pauseAfter: .clause),
            SpokenRun(text: "Here's the code.", pauseAfter: .sentence),
            SpokenRun(text: "Done.", pauseAfter: .sentence),
        ])
    }

    @Test func frenchCodeFenceIsVoiciLeCode() {
        let fenced = """
        ```
        secret = 1
        ```
        """
        let transcript = hear(fenced, .french)
        #expect(transcript.spokenText == "Voici le code.")
        #expect(!transcript.spokenText.contains("secret"))
    }

    @Test func headerIsSpokenAsASentence() {
        #expect(hear("# Status").spokenText == "Status.")
        #expect(hear("## Status report").spokenText == "Status report.")
        #expect(!hear("# Status").spokenText.contains("#"))
    }

    @Test func boldAndItalicAreSpokenAsWords() {
        #expect(hear("The **build** passed.").spokenText == "The build passed.")
        #expect(hear("A *quiet* voice.").spokenText == "A quiet voice.")
        #expect(hear("The __build__ passed.").spokenText == "The build passed.")
        #expect(!hear("The **build** passed.").spokenText.contains("*"))
    }

    @Test func englishListBecomesSpokenSequence() {
        let transcript = hear("- alpha\n- beta\n- gamma")
        #expect(transcript.spokenText == "First alpha. Next beta. And last gamma.")
        #expect(transcript.runs == [
            SpokenRun(text: "First", pauseAfter: .clause),
            SpokenRun(text: "alpha.", pauseAfter: .sentence),
            SpokenRun(text: "Next", pauseAfter: .clause),
            SpokenRun(text: "beta.", pauseAfter: .sentence),
            SpokenRun(text: "And last", pauseAfter: .clause),
            SpokenRun(text: "gamma.", pauseAfter: .sentence),
        ])
    }

    @Test func frenchListBecomesSpokenSequence() {
        let transcript = hear("- alpha\n- beta\n- gamma", .french)
        #expect(transcript.spokenText == "D'abord alpha. Ensuite beta. Et enfin gamma.")
    }

    @Test func twoItemListUsesFirstAndLast() {
        #expect(hear("1. alpha\n2. beta").spokenText == "First alpha. And last beta.")
    }

    @Test func singleListItemHasNoSequenceWord() {
        let transcript = hear("- only this")
        #expect(transcript.spokenText == "only this.")
        #expect(!transcript.spokenText.contains("First"))
    }

    @Test func percentThreePointFiveEnglish() {
        #expect(hear("3.5%").spokenText == "three point five percent.")
        #expect(hear("Use 3.5% more.").spokenText == "Use three point five percent more.")
    }

    @Test func percentThreePointFiveFrench() {
        #expect(hear("3.5%", .french).spokenText == "trois virgule cinq pour cent.")
        #expect(hear("3,5%", .french).spokenText == "trois virgule cinq pour cent.")
    }

    @Test func oneHundredPercent() {
        #expect(hear("100%").spokenText == "one hundred percent.")
        #expect(hear("100%", .french).spokenText == "cent pour cent.")
    }

    @Test func euroTwelveHundredEnglish() {
        #expect(hear("€1,200").spokenText == "one thousand two hundred euros.")
        #expect(hear("It costs €1,200 today.").spokenText == "It costs one thousand two hundred euros today.")
    }

    @Test func euroTwelveHundredFrench() {
        #expect(hear("€1,200", .french).spokenText == "mille deux cents euros.")
    }

    @Test func dollarsAndCents() {
        #expect(hear("$5.25").spokenText == "five dollars and twenty-five cents.")
    }

    @Test func slashDateEnglishIsMonthThenDay() {
        #expect(hear("12/11/2026").spokenText == "December eleventh twenty twenty-six.")
        #expect(hear("Due 12/11/2026.").spokenText == "Due December eleventh twenty twenty-six.")
    }

    @Test func slashDateFrenchIsDayThenMonth() {
        #expect(hear("12/11/2026", .french).spokenText == "douze novembre deux mille vingt-six.")
    }

    @Test func dayPastTwelveForcesDayThenMonth() {
        #expect(hear("13/11/2026").spokenText == "November thirteenth twenty twenty-six.")
        #expect(hear("13/11/2026", .french).spokenText == "treize novembre deux mille vingt-six.")
    }

    @Test func isoDateIsMonthThenDayInBothLanguages() {
        #expect(hear("2026-11-12").spokenText == "November twelfth twenty twenty-six.")
        #expect(hear("2026-11-12", .french).spokenText == "douze novembre deux mille vingt-six.")
    }

    @Test func versionEnglish() {
        #expect(hear("v2.1.0").spokenText == "version two point one point zero.")
        #expect(hear("Ship v2.1.0 today.").spokenText == "Ship version two point one point zero today.")
    }

    @Test func versionFrench() {
        #expect(hear("v2.1.0", .french).spokenText == "version deux point un point zéro.")
    }

    @Test func timeEnglishUsesTwelveHourClock() {
        #expect(hear("14:30").spokenText == "two thirty p m.")
        #expect(hear("Meet at 14:30.").spokenText == "Meet at two thirty p m.")
        #expect(hear("3:05").spokenText == "three oh five.")
    }

    @Test func timeFrenchUsesTwentyFourHourClock() {
        #expect(hear("14:30", .french).spokenText == "quatorze heures trente.")
        #expect(hear("3:05", .french).spokenText == "trois heures cinq.")
    }

    @Test func integersEnglishAndFrench() {
        #expect(hear("42").spokenText == "forty-two.")
        #expect(hear("42", .french).spokenText == "quarante-deux.")
        #expect(hear("101").spokenText == "one hundred and one.")
    }

    @Test func frenchHardNumbers() {
        #expect(hear("17", .french).spokenText == "dix-sept.")
        #expect(hear("21", .french).spokenText == "vingt-et-un.")
        #expect(hear("71", .french).spokenText == "soixante-et-onze.")
        #expect(hear("80", .french).spokenText == "quatre-vingts.")
        #expect(hear("81", .french).spokenText == "quatre-vingt-un.")
        #expect(hear("91", .french).spokenText == "quatre-vingt-onze.")
        #expect(hear("200", .french).spokenText == "deux cents.")
    }

    @Test func urlIsSpokenByDomain() {
        let transcript = hear("See https://example.com/docs?x=1 for it.")
        #expect(transcript.spokenText == "See example dot com for it.")
        #expect(!transcript.spokenText.contains("https"))
        #expect(!transcript.spokenText.contains("docs"))
        #expect(!transcript.spokenText.contains("x=1"))
    }

    @Test func frenchUrlUsesPoint() {
        let transcript = hear("https://example.com/docs", .french)
        #expect(transcript.spokenText == "example point com.")
        #expect(!transcript.spokenText.contains("https"))
    }

    @Test func wwwPrefixIsDropped() {
        #expect(hear("www.example.com/a").spokenText == "example dot com.")
    }

    @Test func ipAddressIsALink() {
        #expect(hear("http://127.0.0.1/status").spokenText == "a link.")
    }

    @Test func markdownLinkKeepsTheLabel() {
        let transcript = hear("Read [the docs](https://example.com/guide) today.")
        #expect(transcript.spokenText == "Read the docs today.")
        #expect(!transcript.spokenText.contains("example"))
        #expect(!transcript.spokenText.contains("https"))
    }

    @Test func filePathIsNotRead() {
        let transcript = hear("Open Sources/Zeus/Voice/Speaker.swift please.")
        #expect(transcript.spokenText == "Open a file please.")
        #expect(!transcript.spokenText.contains("Speaker"))
        #expect(!transcript.spokenText.contains("swift"))
    }

    @Test func frenchFilePath() {
        #expect(hear("Sources/Zeus/Voice/Speaker.swift", .french).spokenText == "un fichier.")
    }

    @Test func windowsPathIsNotRead() {
        #expect(hear("Open C:\\notes.txt now.").spokenText == "Open a file now.")
    }

    @Test func hashIsNotRead() {
        let digest = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4"
        let transcript = hear("Commit \(digest) now.")
        #expect(transcript.spokenText == "Commit a hash now.")
        #expect(!transcript.spokenText.contains(digest))
        #expect(hear("Mark deadbeef done.").spokenText == "Mark a hash done.")
        #expect(hear("See 0xdeadbeef now.").spokenText == "See a hash now.")
    }

    @Test func frenchHashIsUneEmpreinte() {
        #expect(hear("deadbeef", .french).spokenText == "une empreinte.")
    }

    @Test func feedbackIsNotAHash() {
        #expect(hear("Send feedback today.").spokenText == "Send feedback today.")
    }

    @Test func englishContractions() {
        let spoken = hear("I am ready. It is fine. Do not wait. We will see. That is all. There is time. Cannot stop. Will not fail.")
        #expect(spoken.spokenText == "I'm ready. It's fine. Don't wait. We'll see. That's all. There's time. Can't stop. Won't fail.")
    }

    @Test func frenchDoesNotApplyEnglishContractions() {
        let spoken = hear("It is prêt.", .french)
        #expect(spoken.spokenText == "It is prêt.")
    }

    @Test func contractionFollowsTheSpokenNumber() {
        #expect(hear("It is 3.5%.").spokenText == "It's three point five percent.")
        #expect(hear("It is 3.5%.", .french).spokenText == "It is trois virgule cinq pour cent.")
    }

    @Test func clausePauseSplitsAComma() {
        let transcript = hear("Yes, it passed.")
        #expect(transcript.runs == [
            SpokenRun(text: "Yes", pauseAfter: .clause),
            SpokenRun(text: "it passed.", pauseAfter: .sentence),
        ])
        #expect(transcript.spokenText == "Yes it passed.")
    }

    @Test func emDashIsAClausePause() {
        let transcript = hear("Ready — almost.")
        #expect(transcript.runs == [
            SpokenRun(text: "Ready", pauseAfter: .clause),
            SpokenRun(text: "almost.", pauseAfter: .sentence),
        ])
    }

    @Test func questionMarkStaysOnTheSentence() {
        let transcript = hear("Is it ready?")
        #expect(transcript.runs == [SpokenRun(text: "Is it ready?", pauseAfter: .sentence)])
    }

    @Test func abbreviationDoesNotEndTheSentence() {
        let transcript = hear("Dr. Smith is ready.")
        #expect(transcript.runs == [SpokenRun(text: "Dr. Smith is ready.", pauseAfter: .sentence)])
    }

    @Test func longSentenceSplitsAtAClauseBoundary() {
        let transcript = hear("The release is ready, the notes are written, and the build is green, but the signature is still missing.")
        #expect(transcript.runs == [
            SpokenRun(text: "The release is ready", pauseAfter: .clause),
            SpokenRun(text: "the notes are written", pauseAfter: .clause),
            SpokenRun(text: "and the build is green.", pauseAfter: .sentence),
            SpokenRun(text: "But the signature is still missing.", pauseAfter: .sentence),
        ])
    }

    @Test func longSentenceWithoutABoundaryStaysWhole() {
        let transcript = hear("This sentence has many words but no clause boundary so it stays together as one spoken sentence today.")
        #expect(transcript.runs.count == 1)
        #expect(transcript.runs[0].pauseAfter == .sentence)
        #expect(transcript.spokenText == "This sentence has many words but no clause boundary so it stays together as one spoken sentence today.")
    }

    @Test func answerFirstKeepsTheOpeningSentence() {
        let transcript = hear("The build passed. The logs are long and can wait.", maxSentences: 1)
        #expect(transcript.spokenText == "The build passed.")
        #expect(!transcript.spokenText.contains("logs"))
    }

    @Test func answerFirstKeepsAClauseInsideTheFirstSentence() {
        let transcript = hear("Yes, it passed. The rest can wait.", maxSentences: 1)
        #expect(transcript.runs == [
            SpokenRun(text: "Yes", pauseAfter: .clause),
            SpokenRun(text: "it passed.", pauseAfter: .sentence),
        ])
    }

    @Test func missingBudgetKeepsEverySentence() {
        let transcript = hear("The build passed. The logs are long and can wait.")
        #expect(transcript.spokenText.contains("logs"))
    }

    @Test func zeroSentenceBudgetIsSilent() {
        #expect(hear("Yes. No.", maxSentences: 0).runs.isEmpty)
    }

    @Test func pauseMarkersAreAnEnumNotSSML() {
        let transcript = hear("Yes, it passed.")
        #expect(transcript.runs.map(\.pauseAfter) == [.clause, .sentence])
        #expect(!transcript.spokenText.contains("<"))
        #expect(!transcript.spokenText.lowercased().contains("ssml"))
        #expect(SpokenPause.allCases == [.clause, .sentence])
    }

    @Test func pipelineOrderIsFixedAndExhaustive() {
        #expect(SpokenStyle.stages == [
            .markdown, .links, .quantities, .contractions, .clauses, .answerFirst,
        ])
        #expect(SpokenStage.allCases == SpokenStage.order)
        #expect(SpokenStyle.maxWordsPerSentence == 16)
        #expect(SpokenStage.order.map(stageTitle) == [
            "markdown", "links", "quantities", "contractions", "clauses", "answerFirst",
        ])
    }

    @Test func transformIsTheStagesFoldedInOrder() {
        let request = SpokenRequest(text: "It is **ready**, see https://example.com/docs.", language: .english, maxSentences: 2)
        var draft = SpokenDraft(text: request.text)
        for stage in SpokenStyle.stages {
            draft = stage.transform(draft, language: request.language, maxSentences: request.maxSentences)
        }
        #expect(hear(request.text, maxSentences: 2).runs == draft.runs)
    }

    @Test func everyStageIsAPureFunction() {
        let draft = SpokenDraft(text: "It is **3.5%** and https://example.com/a.")
        for stage in SpokenStage.allCases {
            let once = stage.transform(draft, language: .english, maxSentences: 1)
            let twice = stage.transform(draft, language: .english, maxSentences: 1)
            #expect(once == twice)
        }
    }

    @Test func markdownStageStripsMarksAndLeavesRunsEmpty() {
        let out = SpokenStage.markdown.transform(SpokenDraft(text: "The **build** passed."), language: .english, maxSentences: nil)
        #expect(out.text == "The build passed.")
        #expect(out.runs.isEmpty)
    }

    @Test func linksStageSummarizesAURL() {
        let out = SpokenStage.links.transform(
            SpokenDraft(text: "See https://example.com/docs."),
            language: .english,
            maxSentences: nil
        )
        #expect(out.text == "See example dot com.")
        #expect(out.runs.isEmpty)
    }

    @Test func quantitiesStageVerbalizesAPercent() {
        let out = SpokenStage.quantities.transform(SpokenDraft(text: "3.5%"), language: .english, maxSentences: nil)
        #expect(out.text == "three point five percent")
    }

    @Test func contractionsStageSkipsFrench() {
        let english = SpokenStage.contractions.transform(SpokenDraft(text: "It is ready."), language: .english, maxSentences: nil)
        let french = SpokenStage.contractions.transform(SpokenDraft(text: "It is ready."), language: .french, maxSentences: nil)
        #expect(english.text == "It's ready.")
        #expect(french.text == "It is ready.")
    }

    @Test func clausesStageInsertsPauses() {
        let out = SpokenStage.clauses.transform(SpokenDraft(text: "Yes, it passed."), language: .french, maxSentences: nil)
        #expect(out.runs == [
            SpokenRun(text: "Yes", pauseAfter: .clause),
            SpokenRun(text: "it passed.", pauseAfter: .sentence),
        ])
    }

    @Test func answerFirstStageDropsLaterSentences() {
        let draft = SpokenDraft(text: "", runs: [
            SpokenRun(text: "Yes.", pauseAfter: .sentence),
            SpokenRun(text: "Later.", pauseAfter: .sentence),
        ])
        let kept = SpokenStage.answerFirst.transform(draft, language: .english, maxSentences: 1)
        let all = SpokenStage.answerFirst.transform(draft, language: .english, maxSentences: nil)
        #expect(kept.runs == [SpokenRun(text: "Yes.", pauseAfter: .sentence)])
        #expect(all.runs.count == 2)
    }

    @Test func theSameInputIsTheSameSpeech() {
        let first = hear("Ship v2.1.0 and see https://example.com/docs.", .english, maxSentences: 2)
        let second = hear("Ship v2.1.0 and see https://example.com/docs.", .english, maxSentences: 2)
        #expect(first == second)
    }

    @Test func ellipsisBecomesASentenceBreak() {
        #expect(hear("The build passed... the details can wait.").spokenText == "The build passed. The details can wait.")
        #expect(hear("Wait........ done.").spokenText == "Wait. Done.")
    }

    @Test func frenchEllipsisIsASentenceBreak() {
        #expect(hear("C'est prêt… les détails peuvent attendre.", .french).spokenText == "C'est prêt. Les détails peuvent attendre.")
    }

    @Test func repeatedExclamationIsOneStop() {
        #expect(hear("Stop!!!").spokenText == "Stop!")
    }

    @Test func headingDoesNotSpendTheWholeBudget() {
        let transcript = hear("# Status\n\nThe build passed. The logs can wait.", maxSentences: 1)
        #expect(transcript.spokenText == "Status the build passed.")
        #expect(!transcript.spokenText.contains("logs"))
    }

    @Test func checkboxListIsSpokenAsDoneOrOpen() {
        let transcript = hear("- [x] Ship it\n- [ ] Wait")
        #expect(transcript.spokenText == "First Ship it done. And last Wait still open.")
        #expect(!transcript.spokenText.contains("["))
    }

    @Test func frenchCheckboxListIsSpokenAsDoneOrOpen() {
        let transcript = hear("- [x] Livrer\n- [ ] Attendre", .french)
        #expect(transcript.spokenText == "D'abord Livrer fait. Et enfin Attendre encore ouvert.")
        #expect(!transcript.spokenText.contains("["))
    }

    @Test func strikethroughIsNotRead() {
        let transcript = hear("The ~~old~~ plan is ready.")
        #expect(transcript.spokenText == "The plan is ready.")
        #expect(!transcript.spokenText.contains("~"))
    }

    @Test func parenthesesBecomeAnAside() {
        let transcript = hear("The build (the fast one) passed.")
        #expect(transcript.runs == [
            SpokenRun(text: "The build", pauseAfter: .clause),
            SpokenRun(text: "the fast one", pauseAfter: .clause),
            SpokenRun(text: "passed.", pauseAfter: .sentence),
        ])
        #expect(!transcript.spokenText.contains("("))
    }

    @Test func htmlBreakIsANewSentence() {
        #expect(hear("Line one<br>line two").spokenText == "Line one. Line two.")
        #expect(hear("Line one<br/>line two").spokenText == "Line one. Line two.")
        #expect(!hear("Line one<br>line two").spokenText.contains("<"))
    }

    @Test func autolinkBracketsAreNotSpoken() {
        let transcript = hear("See <https://example.com/docs> now.")
        #expect(transcript.spokenText == "See example dot com now.")
        #expect(!transcript.spokenText.contains("<"))
        #expect(!transcript.spokenText.contains("docs"))
    }

    @Test func tildeFenceHidesTheCode() {
        let fenced = """
        Wait.
        ~~~
        secret
        ~~~
        Done.
        """
        let transcript = hear(fenced)
        #expect(transcript.spokenText == "Wait. Here's the code. Done.")
        #expect(!transcript.spokenText.contains("secret"))
        #expect(!transcript.spokenText.contains("~"))
    }

    @Test func ampersandIsSpokenAsAnd() {
        #expect(hear("A & B are ready.").spokenText == "A and B are ready.")
        #expect(hear("A & B sont prêts.", .french).spokenText == "A et B sont prêts.")
    }

    @Test func shoutedSentenceIsSpokenCalmly() {
        #expect(hear("THE BUILD PASSED.").spokenText == "The build passed.")
        #expect(hear("I AM READY.").spokenText == "I'm ready.")
    }

    @Test func aWallOfWordsIsCutIntoShortSentences() {
        let text = Array(repeating: "alpha", count: 40).joined(separator: " ") + "."
        let transcript = hear(text)
        #expect(transcript.runs.count == 3)
        for run in transcript.runs {
            #expect(run.text.split(whereSeparator: \.isWhitespace).count <= SpokenStyle.maxWordsPerSentence)
            #expect(run.pauseAfter == .sentence)
        }
    }

    @Test func aLongReplyKeepsOnlyTheFirstShortSentences() {
        let text = Array(repeating: "alpha", count: 1500).joined(separator: " ") + "."
        let transcript = hear(text, maxSentences: 2)
        #expect(transcript.runs.count == 2)
        for run in transcript.runs {
            #expect(run.text.split(whereSeparator: \.isWhitespace).count <= SpokenStyle.maxWordsPerSentence)
        }
    }
}
