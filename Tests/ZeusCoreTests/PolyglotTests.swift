import Foundation
import Testing
@testable import ZeusCore

// MARK: Audio helpers

private func speech(seconds: Double, amplitude: Float = 0.12) -> [Float] {
    (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * 0.31)) * amplitude }
}

private func silence(seconds: Double) -> [Float] { Array(repeating: 0, count: Int(seconds * 16_000)) }

@Suite struct PolyglotRunIDTests {
    @Test func runsOwnDisjointBlocks() {
        let first = PolyglotRunIDs.firstID(run: 1)
        let second = PolyglotRunIDs.firstID(run: 2)
        #expect(second - first == PolyglotRunIDs.blockSize)
        // A run would need a million lines to reach the next run's ids.
        #expect(first + 400 < second)
    }

    @Test func aRunBelowOneStillGetsAValidBlock() {
        #expect(PolyglotRunIDs.firstID(run: 0) == PolyglotRunIDs.firstID(run: 1))
        #expect(PolyglotRunIDs.firstID(run: -3) == PolyglotRunIDs.firstID(run: 1))
    }

    @Test func onlySettledEventsSurviveARunEnding() {
        let line = PolyglotLine(id: 1, side: .system, original: "Hola", language: "es")
        #expect(PolyglotEvent.line(line).isSettled)
        #expect(PolyglotEvent.translated(id: 1, text: "Hello", target: "en").isSettled)
        #expect(PolyglotEvent.discarded(side: .system, id: 1).isSettled)
        #expect(!PolyglotEvent.partial(side: .system, id: 1, text: "Ho").isSettled)
        #expect(!PolyglotEvent.needsPack(source: "es", target: "en").isSettled)
        #expect(!PolyglotEvent.failed("x").isSettled)
    }

    @Test func anOlderRunsFinalNeverClearsTheNewRunsPartial() {
        var live = PolyglotLivePartials()
        let older = PolyglotRunIDs.firstID(run: 1)
        let newer = PolyglotRunIDs.firstID(run: 2)
        live.reset()
        live.applyPartial(side: .system, id: newer, text: "Bonjour")
        live.settle(side: .system, id: older)
        #expect(live.texts[.system] == "Bonjour")
    }

    @Test func linesFromTwoRunsStayDistinctInTheTranscript() {
        var transcript = PolyglotTranscript()
        transcript.upsert(PolyglotLine(id: PolyglotRunIDs.firstID(run: 1), side: .system, original: "uno", language: "es"))
        transcript.upsert(PolyglotLine(id: PolyglotRunIDs.firstID(run: 2), side: .system, original: "dos", language: "es"))
        transcript.upsert(PolyglotLine(id: PolyglotRunIDs.firstID(run: 1), side: .system, original: "uno", language: "es", translation: "one"))
        #expect(transcript.lines.count == 2)
        #expect(transcript.lines[0].translation == "one")
        #expect(transcript.lines[1].translation == nil)
    }
}

@Suite struct PolyglotSegmenterTests {
    @Test func oneSentenceBecomesOneFinalAfterTheHangover() {
        var segmenter = PolyglotSegmenter()
        var events = segmenter.feed(silence(seconds: 0.5) + speech(seconds: 1.0))
        #expect(events.isEmpty)
        #expect(segmenter.isSpeaking)
        events = segmenter.feed(silence(seconds: 1.0))
        #expect(events.count == 1)
        guard case .final(_, let samples) = events[0] else { Issue.record("expected a final"); return }
        // About a second of speech plus a little lead-in and tail, not the whole second of quiet.
        #expect(samples.count > 16_000 && samples.count < 16_000 * 2)
        #expect(!segmenter.isSpeaking)
    }

    @Test func shortBlipsAreDropped() {
        var segmenter = PolyglotSegmenter()
        let events = segmenter.feed(speech(seconds: 0.1) + silence(seconds: 1.0))
        #expect(events.isEmpty)
        #expect(!segmenter.isSpeaking)
    }

    @Test func silenceNeverStartsAnything() {
        var segmenter = PolyglotSegmenter()
        #expect(segmenter.feed(silence(seconds: 5)).isEmpty)
        #expect(!segmenter.isSpeaking)
    }

    @Test func twoSentencesApart() {
        var segmenter = PolyglotSegmenter()
        let events = segmenter.feed(speech(seconds: 0.8) + silence(seconds: 1.0) + speech(seconds: 0.8) + silence(seconds: 1.0))
        #expect(events.count == 2)
    }

    @Test func longTalkGivesPartialsThenIsCut() {
        var segmenter = PolyglotSegmenter()
        let events = segmenter.feed(speech(seconds: 16))
        let partials = events.filter { if case .partial = $0 { true } else { false } }
        let finals = events.filter { if case .final = $0 { true } else { false } }
        #expect(partials.count >= 3)
        #expect(finals.count == 1) // cut at 15 s so captions never lag
    }

    @Test func utterancesAreNumberedAndPartialsShareTheirFinalsNumber() {
        var segmenter = PolyglotSegmenter()
        let first = segmenter.feed(speech(seconds: 7) + silence(seconds: 1.0))
        let second = segmenter.feed(speech(seconds: 1) + silence(seconds: 1.0))
        func number(_ event: PolyglotSegmenter.Event) -> Int {
            switch event {
            case .partial(let utterance, _), .final(let utterance, _): utterance
            }
        }
        #expect(!first.isEmpty && first.map(number).allSatisfy { $0 == 1 })
        #expect(second.count == 1 && number(second[0]) == 2)
        if case .final? = first.last {} else { Issue.record("the first utterance should end with its final") }
    }

    @Test func aLongMonologueCutStartsANewUtteranceNumber() {
        var segmenter = PolyglotSegmenter()
        let events = segmenter.feed(speech(seconds: 16))
        var cutNumber = 0
        for case .final(let utterance, _) in events { cutNumber = utterance }
        var after = 0
        for case .partial(let utterance, _) in events { after = max(after, utterance) }
        #expect(cutNumber == 1)
        #expect(after >= 1)
        let rest = segmenter.flush()
        if case .final(let utterance, _)? = rest.first { #expect(utterance == 2) } else { Issue.record("expected the rest to flush") }
    }

    @Test func flushClosesWhatWasBeingSaid() {
        var segmenter = PolyglotSegmenter()
        _ = segmenter.feed(speech(seconds: 1.0))
        let events = segmenter.flush()
        #expect(events.count == 1)
        #expect(segmenter.flush().isEmpty)
    }

    @Test func feedingInSmallPiecesGivesTheSameResult() {
        var whole = PolyglotSegmenter()
        let audio = speech(seconds: 1) + silence(seconds: 1)
        let expected = whole.feed(audio)
        var pieces = PolyglotSegmenter()
        var got: [PolyglotSegmenter.Event] = []
        var index = 0
        while index < audio.count {
            got += pieces.feed(Array(audio[index..<min(index + 777, audio.count)]))
            index += 777
        }
        #expect(got == expected)
    }
}

@Suite struct PolyglotLogicTests {
    @Test func phantomCaptionsAreDropped() {
        for text in ["", "  ", "...", "Thanks for watching!", "Obrigado.", "Subtitles by the Amara.org community", "you", "♪"] where text != "Obrigado." {
            #expect(PolyglotTextFilter.isPhantom(text), "\(text)")
        }
        #expect(!PolyglotTextFilter.isPhantom("Obrigado pela reunião."))
        #expect(!PolyglotTextFilter.isPhantom("Vamos começar."))
    }

    @Test func languageBadgesAndBases() {
        #expect(PolyglotLanguage.base("pt-BR") == "pt")
        #expect(PolyglotLanguage.base("EN_us") == "en")
        #expect(PolyglotLanguage.base("zh-Hant-TW") == "zh-Hant")
        #expect(PolyglotLanguage.base("zh") == "zh-Hans")
        #expect(PolyglotLanguage.badge("pt-BR") == "PT")
        #expect(PolyglotLanguage.name(for: "ja") == "Japanese")
        #expect(PolyglotLanguage.targets.first?.code == "en")
        #expect(PolyglotLanguage.parakeetLanguages.contains("pt") && !PolyglotLanguage.parakeetLanguages.contains("ja"))
    }

    @Test func sourcesSayWhatTheyNeed() {
        #expect(PolyglotSource.microphone.usesMicrophone && !PolyglotSource.microphone.usesSystemAudio)
        #expect(!PolyglotSource.system.usesMicrophone && PolyglotSource.system.usesSystemAudio)
        #expect(PolyglotSource.both.usesMicrophone && PolyglotSource.both.usesSystemAudio)
        #expect(PolyglotSource.allCases.count == 3)
    }

    @Test func trackerHoldsTheLanguageThroughNoise() {
        var tracker = PolyglotLanguageTracker(expected: ["pt", "es", "en"])
        #expect(tracker.resolve(("pt", 0.95), wordCount: 8) == "pt")
        // A two-word phrase that looks Spanish does not flip it.
        #expect(tracker.resolve(("es", 0.7), wordCount: 2) == "pt")
        // A real sentence in Spanish does.
        #expect(tracker.resolve(("es", 0.8), wordCount: 6) == "es")
        // An unexpected language needs a strong score.
        #expect(tracker.resolve(("it", 0.6), wordCount: 6) == "es")
        #expect(tracker.resolve(("it", 0.92), wordCount: 6) == "it")
        // Nothing detected keeps what is known.
        #expect(tracker.resolve(nil, wordCount: 4) == "it")
    }

    @Test func trackerBelievesAStrongFirstGuessEvenWhenShort() {
        var tracker = PolyglotLanguageTracker()
        #expect(tracker.resolve(("fr", 0.5), wordCount: 2) == nil)
        #expect(tracker.resolve(("fr", 0.9), wordCount: 2) == "fr")
    }

    @Test func batchingGroupsByLanguageAndSplitsLongRuns() {
        func item(_ id: Int, _ language: String) -> (language: String, request: PolyglotTranslationRequest) {
            (language, PolyglotTranslationRequest(id: id, text: "t\(id)"))
        }
        let batches = PolyglotBatching.group([item(1, "pt"), item(2, "es"), item(3, "pt"), item(4, "pt"), item(5, "es")], limit: 2)
        #expect(batches.map(\.language) == ["pt", "pt", "es"])
        #expect(batches.map { $0.requests.map(\.id) } == [[1, 3], [4], [2, 5]])
        #expect(PolyglotBatching.group([]).isEmpty)
    }

    @Test func transcriptKeepsOrderUpdatesAndCopiesAsText() {
        var transcript = PolyglotTranscript()
        transcript.upsert(PolyglotLine(id: 1, side: .system, original: "Bom dia a todos.", language: "pt"))
        transcript.upsert(PolyglotLine(id: 2, side: .microphone, original: "Good morning.", language: "en", isTarget: true))
        transcript.setTranslation(id: 1, "Good morning, everyone.")
        transcript.upsert(PolyglotLine(id: 3, side: .system, original: "partial", language: "pt", isFinal: false))
        #expect(transcript.recent(2).map(\.id) == [2, 3])
        #expect(transcript.text(target: "en") == "[PT] Bom dia a todos.\n→ Good morning, everyone.\n[EN] Good morning.")
        // An update replaces, never duplicates.
        transcript.upsert(PolyglotLine(id: 3, side: .system, original: "settled", language: "pt"))
        #expect(transcript.lines.count == 3 && transcript.lines[2].original == "settled")
        transcript.clear()
        #expect(transcript.lines.isEmpty)
    }

    @Test func aFinalClearsItsOwnPartialAndLaterPartialsOfThatUtteranceAreRefused() {
        var live = PolyglotLivePartials()
        let first = live.applyPartial(side: .system, id: 3, text: "Vamos")
        #expect(first && live.texts[.system] == "Vamos")
        live.settle(side: .system, id: 3)
        #expect(live.texts[.system] == nil)
        let ghost = live.applyPartial(side: .system, id: 3, text: "Vamos começar")
        #expect(!ghost && live.texts.isEmpty)
    }

    @Test func aFinalNeverClearsTheNextUtterancesPartial() {
        var live = PolyglotLivePartials()
        live.applyPartial(side: .system, id: 4, text: "next sentence")
        live.settle(side: .system, id: 3)
        #expect(live.texts[.system] == "next sentence")
    }

    @Test func aStalePartialCannotReplaceANewerOne() {
        var live = PolyglotLivePartials()
        live.applyPartial(side: .system, id: 5, text: "newer")
        let stale = live.applyPartial(side: .system, id: 4, text: "older")
        #expect(!stale && live.texts[.system] == "newer")
        let growing = live.applyPartial(side: .system, id: 5, text: "newer and longer")
        #expect(growing && live.texts[.system] == "newer and longer")
    }

    @Test func inputsDoNotAffectEachOther() {
        var live = PolyglotLivePartials()
        live.applyPartial(side: .system, id: 8, text: "mac")
        live.applyPartial(side: .microphone, id: 2, text: "you")
        live.settle(side: .microphone, id: 2)
        #expect(live.texts == [.system: "mac"])
    }

    @Test func aDiscardedUtteranceCannotShowAPartialLater() {
        var live = PolyglotLivePartials()
        live.settle(side: .microphone, id: 6)
        let late = live.applyPartial(side: .microphone, id: 6, text: "ghost")
        #expect(!late && live.texts.isEmpty)
    }

    @Test func stoppingKeepsWhatEndedAndANewRunForgetsIt() {
        var live = PolyglotLivePartials()
        live.applyPartial(side: .system, id: 2, text: "talking")
        live.settle(side: .system, id: 1)
        live.dropPartials()
        #expect(live.texts.isEmpty)
        let stillRefused = live.applyPartial(side: .system, id: 1, text: "late")
        #expect(!stillRefused)
        live.reset()
        let fresh = live.applyPartial(side: .system, id: 1, text: "new run")
        #expect(fresh && live.texts[.system] == "new run")
    }

    @Test func captionSizes() {
        #expect(PolyglotCaptionSize.medium.translationPoints == 17)
        #expect(PolyglotCaptionSize.small.translationPoints < PolyglotCaptionSize.large.translationPoints)
    }
}

// MARK: Pipeline with fakes

private actor Script {
    var texts: [String]
    var calls: [(count: Int, language: String?)] = []
    init(_ texts: [String]) { self.texts = texts }
    func next(samples: Int, language: String?) -> String {
        calls.append((samples, language))
        return texts.isEmpty ? "" : texts.removeFirst()
    }
}

private struct FakeRecognizer: PolyglotRecognizing {
    let script: Script
    func transcribe(samples: [Float], language: String?) async throws -> String { await script.next(samples: samples.count, language: language) }
}

private struct FakeDetector: PolyglotLanguageDetecting {
    let table: [String: (String, Double)]
    func detect(_ text: String) -> (code: String, confidence: Double)? { table[text].map { ($0.0, $0.1) } }
}

private actor FakeTranslator: PolyglotTranslating {
    var status: PolyglotPackStatus = .installed
    private(set) var batches: [(from: String, ids: [Int])] = []
    func setStatus(_ new: PolyglotPackStatus) { status = new }
    func status(from source: String, to target: String) async -> PolyglotPackStatus { status }
    func translate(_ requests: [PolyglotTranslationRequest], from source: String, to target: String) async throws -> [String] {
        batches.append((source, requests.map(\.id)))
        return requests.map { "EN: \($0.text)" }
    }
}

private struct FixedRecognizer: PolyglotRecognizing {
    let text: String
    func transcribe(samples: [Float], language: String?) async throws -> String { text }
}

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [PolyglotEvent] = []
    func add(_ event: PolyglotEvent) { lock.withLock { store.append(event) } }
    var all: [PolyglotEvent] { lock.withLock { store } }
    var partialIDs: [Int] { all.compactMap { if case .partial(_, let id, _) = $0 { id } else { nil } } }
    var lines: [PolyglotLine] { all.compactMap { if case .line(let line) = $0 { line } else { nil } } }
    var translations: [Int: String] {
        Dictionary(uniqueKeysWithValues: all.compactMap { if case .translated(let id, let text, _) = $0 { (id, text) } else { nil } })
    }
}

@Suite struct PolyglotPipelineTests {
    private let table: [String: (String, Double)] = [
        "Vamos começar a reunião agora.": ("pt", 0.97), "¿Podemos revisar el presupuesto primero?": ("es", 0.95),
        "Okay, let's go.": ("en", 0.99), "Bom dia.": ("pt", 0.9),
    ]

    private func make(_ texts: [String], translator: FakeTranslator = FakeTranslator(), target: String = "en", passLimit: Int = 6)
        -> (PolyglotPipeline, Events, Script, FakeTranslator) {
        let events = Events()
        let script = Script(texts)
        let pipeline = PolyglotPipeline(recognizer: FakeRecognizer(script: script), detector: FakeDetector(table: table), translator: translator,
                                        target: target, expected: ["pt", "es", "en"], passLimit: passLimit) { events.add($0) }
        return (pipeline, events, script, translator)
    }

    private func say(_ pipeline: PolyglotPipeline, _ side: PolyglotSide = .system, seconds: Double = 1) async {
        await pipeline.ingest(speech(seconds: seconds) + silence(seconds: 1), from: side)
    }

    @Test func sentenceIsTranscribedDetectedAndTranslated() async {
        let (pipeline, events, _, translator) = make(["Vamos começar a reunião agora."])
        await say(pipeline)
        await pipeline.finish()
        #expect(events.lines.count == 1)
        #expect(events.lines[0].language == "pt" && events.lines[0].side == .system && !events.lines[0].isTarget)
        #expect(events.translations[events.lines[0].id] == "EN: Vamos começar a reunião agora.")
        #expect(await translator.batches.count == 1)
    }

    @Test func targetLanguageSpeechIsNotTranslated() async {
        let (pipeline, events, _, translator) = make(["Okay, let's go."])
        await say(pipeline, .microphone)
        await pipeline.finish()
        #expect(events.lines.first?.isTarget == true && events.lines.first?.side == .microphone)
        #expect(events.translations.isEmpty)
        #expect(await translator.batches.isEmpty)
    }

    @Test func detectedLanguageIsHandedBackToTheRecognizer() async {
        let (pipeline, events, script, _) = make(["Vamos começar a reunião agora.", "Bom dia."])
        await say(pipeline)
        await pipeline.finish()
        await say(pipeline)
        await pipeline.finish()
        #expect(events.lines.count == 2)
        let calls = await script.calls
        // The first utterance is transcribed with no hint; the second is told it is Portuguese.
        #expect(calls.first?.language == nil)
        #expect(calls.last?.language == "pt")
    }

    @Test func microphoneDoesNotInheritTheRemoteSpeakersLanguage() async {
        let (pipeline, _, script, _) = make(["Vamos começar a reunião agora.", "Okay, let's go.", "Bom dia."])
        await say(pipeline, .system)
        await pipeline.finish()
        await say(pipeline, .microphone)
        await pipeline.finish()
        await say(pipeline, .system)
        await pipeline.finish()
        let calls = await script.calls
        #expect(calls.map(\.language) == [nil, nil, "pt"])
    }

    @Test func phantomTextNeverReachesTheCard() async {
        let (pipeline, events, _, translator) = make(["Thanks for watching!"])
        await say(pipeline)
        await pipeline.finish()
        #expect(events.lines.isEmpty)
        #expect(await translator.batches.isEmpty)
    }

    @Test func aBacklogIsTranslatedInBatchesPerLanguage() async {
        // Three sentences pile up before the worker gets to them: one batch per source language.
        let (pipeline, events, _, translator) = make(["Vamos começar a reunião agora.", "¿Podemos revisar el presupuesto primero?", "Vamos começar a reunião agora."])
        // Feed all three without letting the worker run in between.
        let audio = (speech(seconds: 1) + silence(seconds: 1)) + (speech(seconds: 1) + silence(seconds: 1)) + (speech(seconds: 1) + silence(seconds: 1))
        await pipeline.ingest(audio, from: .system)
        await pipeline.finish()
        #expect(events.lines.count == 3)
        let batches = await translator.batches
        let portuguese = batches.filter { $0.from == "pt" }
        let spanish = batches.filter { $0.from == "es" }
        #expect(batches.count == 2)
        #expect(portuguese.first?.ids.count == 2 && spanish.first?.ids.count == 1)
        #expect(events.translations.count == 3)
    }

    @Test func missingPackAsksToDownloadAndTranslatesNothing() async {
        let translator = FakeTranslator()
        await translator.setStatus(.needsDownload)
        let (pipeline, events, _, _) = make(["Vamos começar a reunião agora."], translator: translator)
        await say(pipeline)
        await pipeline.finish()
        #expect(events.all.contains(.needsPack(source: "pt", target: "en")))
        #expect(events.translations.isEmpty)
        #expect(events.lines.count == 1) // the original still shows
        #expect(await translator.batches.isEmpty)
    }

    @Test func unsupportedPairSaysSo() async {
        let translator = FakeTranslator()
        await translator.setStatus(.unsupported)
        let (pipeline, events, _, _) = make(["Vamos começar a reunião agora."], translator: translator)
        await say(pipeline)
        await pipeline.finish()
        #expect(events.all.contains { if case .failed(let text) = $0 { text.contains("Portuguese") } else { false } })
        #expect(events.lines.count == 1)
        #expect(events.lines[0].original == "Vamos começar a reunião agora.")
        #expect(events.translations.isEmpty)
        var transcript = PolyglotTranscript()
        for event in events.all { transcript.applySettled(event) }
        #expect(transcript.lines.count == 1)
        #expect(transcript.lines[0].original == "Vamos começar a reunião agora.")
        #expect(transcript.lines[0].translation == nil)
    }

    @Test func targetChangeAppliesToTheNextSentence() async {
        let (pipeline, events, _, _) = make(["Okay, let's go.", "Vamos começar a reunião agora."])
        await say(pipeline)
        await pipeline.finish()
        #expect(events.lines.first?.isTarget == true)
        await pipeline.setTarget("pt")
        await say(pipeline)
        await pipeline.finish()
        // Now Portuguese is the target: the second one is shown as it is.
        #expect(events.lines.last?.isTarget == true)
    }

    @Test func anOlderSettingsTaskCannotUndoTheLatestTarget() async {
        let (pipeline, events, _, _) = make(["Vamos começar a reunião agora."])
        await pipeline.setTarget("pt", request: 2)
        await pipeline.setTarget("es", request: 1)
        await say(pipeline)
        await pipeline.finish()
        #expect(events.lines.first?.isTarget == true)
        #expect(events.translations.isEmpty)
    }

    @Test func finishWithNothingSaidReturnsAtOnce() async {
        let (pipeline, events, _, _) = make([])
        await pipeline.finish()
        #expect(events.all.isEmpty)
    }

    private func fixed(_ text: String, firstID: Int = 1) -> (PolyglotPipeline, Events) {
        let events = Events()
        let pipeline = PolyglotPipeline(recognizer: FixedRecognizer(text: text), detector: FakeDetector(table: table), translator: FakeTranslator(),
                                        target: "en", firstID: firstID) { events.add($0) }
        return (pipeline, events)
    }

    @Test func aPartialCarriesTheIdOfTheLineItBecomes() async {
        let (pipeline, events) = fixed("Vamos começar a reunião agora.", firstID: 40)
        await pipeline.ingest(speech(seconds: 4), from: .system)
        for _ in 0..<150 where events.partialIDs.isEmpty { try? await Task.sleep(for: .milliseconds(20)) }
        await pipeline.ingest(silence(seconds: 1), from: .system)
        await pipeline.finish()
        #expect(!events.partialIDs.isEmpty)
        #expect(events.lines.count == 1)
        #expect(events.lines.first?.id == 40)
        #expect(events.partialIDs.allSatisfy { $0 == 40 })
    }

    @Test func aPartialThatAnswersAfterItsFinalWasQueuedIsDropped() async {
        let (pipeline, events) = fixed("Vamos começar a reunião agora.")
        // The partial is requested and the utterance ends in the same feed: its answer is late by then.
        await pipeline.ingest(speech(seconds: 4) + silence(seconds: 1), from: .system)
        await pipeline.finish()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(events.partialIDs.isEmpty)
        #expect(events.lines.count == 1)
    }

    @Test func aPhantomFinalRetiresItsUtterance() async {
        let (pipeline, events) = fixed("Thanks for watching!")
        await pipeline.ingest(speech(seconds: 1) + silence(seconds: 1), from: .system)
        await pipeline.finish()
        #expect(events.lines.isEmpty)
        #expect(events.all.contains(.discarded(side: .system, id: 1)))
    }

    @Test func linesOfALaterRunStartAboveTheEarlierOnes() async {
        let (pipeline, events) = fixed("Vamos começar a reunião agora.", firstID: 7)
        await say(pipeline)
        await pipeline.finish()
        #expect(events.lines.map(\.id) == [7])
    }

    @Test func eachInputKeepsItsOwnUtterance() async {
        let (pipeline, events, _, _) = make(["Vamos começar a reunião agora.", "Okay, let's go."])
        // Both talk at once: two lines, one per side, never a blend.
        let audio = speech(seconds: 1) + silence(seconds: 1)
        await pipeline.ingest(audio, from: .system)
        await pipeline.ingest(audio, from: .microphone)
        await pipeline.finish()
        #expect(Set(events.lines.map(\.side)) == [.system, .microphone])
    }
}
