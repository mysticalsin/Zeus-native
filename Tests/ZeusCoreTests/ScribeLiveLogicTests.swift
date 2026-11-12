import Foundation
import Testing
import ZeusCore

@Suite("Scribe live logic")
struct ScribeLiveLogicTests {
    private let rate = Double(ScribePCM.sampleRate)

    private func tone(seconds: Double, amplitude: Float = 0.3) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * sin(Float($0) * 0.05) }
    }

    // MARK: PCM

    @Test func pcmRoundTripsExactly() {
        let samples: [Float] = [0, 0.5, -0.25, 1, -1, 0.001]
        let data = ScribePCM.encode(samples)
        #expect(data.count == samples.count * MemoryLayout<Float>.size)
        #expect(ScribePCM.decode(data) == samples)
    }

    @Test func pcmDecodeIgnoresTrailingPartialSampleAndEmpty() {
        #expect(ScribePCM.decode(Data()).isEmpty)
        var data = ScribePCM.encode([0.25, 0.5])
        data.append(contentsOf: [0x01, 0x02])
        #expect(ScribePCM.decode(data) == [0.25, 0.5])
    }

    // MARK: Mono mix and level

    @Test func interleavedStereoAveragesToMono() {
        let mono = ScribeAudioMath.monoMix(interleaved: [1, 0, 0.5, 0.5, -1, 1], channels: 2)
        #expect(mono == [0.5, 0.5, 0])
    }

    @Test func monoInputIsUnchangedAndPartialFrameDropped() {
        #expect(ScribeAudioMath.monoMix(interleaved: [0.1, 0.2, 0.3], channels: 1) == [0.1, 0.2, 0.3])
        #expect(ScribeAudioMath.monoMix(interleaved: [1, 1, 1], channels: 2) == [1])
        #expect(ScribeAudioMath.monoMix(interleaved: [], channels: 2).isEmpty)
    }

    @Test func planarChannelsAverageUsingShortestPlane() {
        let mono = ScribeAudioMath.monoMix(planar: [[1, 1, 1], [0, 0]])
        #expect(mono == [0.5, 0.5])
        #expect(ScribeAudioMath.monoMix(planar: [[0.2, 0.4]]) == [0.2, 0.4])
        #expect(ScribeAudioMath.monoMix(planar: [[Float]]()).isEmpty)
    }

    @Test func silenceIsDetectedAndSpeechLevelIsNot() {
        #expect(ScribeAudioMath.isSilent([Float](repeating: 0, count: 1000)))
        #expect(ScribeAudioMath.isSilent([]))
        #expect(!ScribeAudioMath.isSilent(tone(seconds: 0.5)))
    }

    // MARK: Resampler

    @Test func downsamplingFortyEightToSixteenKeepsOneThirdAndTheLevel() {
        var resampler = ScribeResampler(inputRate: 48_000)
        let input = [Float](repeating: 0.5, count: 4_800)
        let output = resampler.process(input)
        #expect(output.count == 1_600)
        #expect(output.allSatisfy { abs($0 - 0.5) < 1e-6 })
    }

    @Test func splittingInputNeverChangesTheResampledOutput() {
        let input = (0..<9_600).map { sin(Float($0) * 0.01) }
        // Ratios 3, 2, 1.5 and 1 are exact in binary, so split and whole runs agree sample for sample.
        for inputRate in [48_000.0, 32_000.0, 24_000.0, 16_000.0] {
            var whole = ScribeResampler(inputRate: inputRate)
            let expected = whole.process(input)
            var split = ScribeResampler(inputRate: inputRate)
            var pieces: [Float] = []
            var index = 0
            for size in [1, 7, 480, 1_001, 3, 8_108] where index < input.count {
                let end = min(input.count, index + size)
                pieces += split.process(Array(input[index..<end]))
                index = end
            }
            pieces += split.process(Array(input[index...]))
            #expect(pieces == expected)
        }
    }

    @Test func equalRatePassesSamplesThroughWithoutChangingValues() {
        var resampler = ScribeResampler(inputRate: 16_000)
        let input: [Float] = [0, 1, 2, 3, 4]
        let output = resampler.process(input)
        #expect(output == [0, 1, 2, 3])
        let next = resampler.process([5])
        #expect(next == [4])
    }

    @Test func invalidInputRateFallsBackToPassThrough() {
        let resampler = ScribeResampler(inputRate: 0)
        #expect(resampler.inputRate == resampler.outputRate)
    }

    // MARK: Timeline

    @Test func timelineKeepsFramesContiguousWhileTheClockAgrees() {
        var timeline = ScribeTimeline()
        let first = timeline.stamp(duration: 0.1, arrival: 1.1)
        let second = timeline.stamp(duration: 0.1, arrival: 1.21)
        #expect(abs(first - 1.0) < 1e-9)
        #expect(abs(second - 1.1) < 1e-9)
    }

    @Test func timelineResyncsAfterALargeJump() {
        var timeline = ScribeTimeline()
        _ = timeline.stamp(duration: 0.1, arrival: 1.0)
        let later = timeline.stamp(duration: 0.1, arrival: 20.1)
        #expect(abs(later - 20.0) < 1e-9)
    }

    // MARK: Chunker

    @Test func chunkerCutsAtFifteenSecondsAndKeepsTheRemainder() {
        var chunker = ScribeChunker(chunkSeconds: 15)
        let chunks = chunker.append(tone(seconds: 32), at: 4)
        #expect(chunks.count == 2)
        #expect(chunks.map(\.index) == [0, 1])
        #expect(chunks.allSatisfy { $0.samples.count == 15 * ScribePCM.sampleRate })
        #expect(abs(chunks[0].start - 4) < 1e-9)
        #expect(abs(chunks[1].start - 19) < 1e-9)
        #expect(chunker.bufferedSamples == 2 * ScribePCM.sampleRate)
        let last = chunker.flush()
        #expect(last?.index == 2)
        #expect(abs((last?.start ?? 0) - 34) < 1e-9)
        #expect(chunker.bufferedSamples == 0)
    }

    @Test func chunkerAssemblesChunksFromSmallContiguousFrames() {
        var chunker = ScribeChunker(chunkSeconds: 15)
        var chunks: [ScribeChunk] = []
        var time = 0.0
        let frame = tone(seconds: 0.1)
        for _ in 0..<160 {
            chunks += chunker.append(frame, at: time)
            time += 0.1
        }
        #expect(chunks.count == 1)
        #expect(chunker.bufferedSamples == Int(1.0 * rate))
    }

    @Test func chunkerClosesAtATimingGapSoMuteTimeIsNotInvented() {
        var chunker = ScribeChunker()
        let first = chunker.append(tone(seconds: 3), at: 0)
        #expect(first.isEmpty)
        let chunks = chunker.append(tone(seconds: 2), at: 10)
        #expect(chunks.count == 1)
        #expect(abs(chunks[0].start) < 1e-9)
        #expect(abs(chunks[0].duration - 3) < 1e-9)
        let rest = chunker.flush()
        #expect(abs((rest?.start ?? 0) - 10) < 1e-9)
        #expect(abs((rest?.duration ?? 0) - 2) < 1e-9)
    }

    @Test func chunkerDropsTinyFlushesAndGapRemnants() {
        var chunker = ScribeChunker()
        _ = chunker.append(tone(seconds: 0.2), at: 0)
        let tiny = chunker.flush()
        #expect(tiny == nil)
        _ = chunker.append(tone(seconds: 0.2), at: 5)
        let chunks = chunker.append(tone(seconds: 1), at: 30)
        #expect(chunks.isEmpty)
        let rest = chunker.flush()
        #expect(rest?.start == 30)
    }

    @Test func chunkerIndexesAreContinuousAcrossGaps() {
        var chunker = ScribeChunker()
        _ = chunker.append(tone(seconds: 2), at: 0)
        _ = chunker.append(tone(seconds: 2), at: 50)
        let tail = chunker.flush()
        #expect(tail?.index == 1)
    }

    // MARK: Pause-aware chunking

    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int((seconds * rate).rounded()))
    }

    @Test func chunkerDefaultsToEightSecondTurns() {
        let chunker = ScribeChunker()
        #expect(chunker.chunkSamples == 8 * ScribePCM.sampleRate)
        #expect(chunker.pauseCutSamples == Int(1.5 * rate))
        #expect(chunker.pauseSamples == Int(0.45 * rate))
    }

    @Test func continuousSpeechHardCutsAtTheChunkLength() {
        var chunker = ScribeChunker()
        let chunks = chunker.append(tone(seconds: 20), at: 0)
        #expect(chunks.map(\.index) == [0, 1])
        #expect(chunks.allSatisfy { $0.samples.count == 8 * ScribePCM.sampleRate })
        #expect(chunker.bufferedSamples == 4 * ScribePCM.sampleRate)
    }

    @Test func aPauseAfterSpeechClosesTheChunkEarly() {
        var chunker = ScribeChunker()
        let chunks = chunker.append(tone(seconds: 2) + silence(seconds: 0.6), at: 3)
        #expect(chunks.count == 1)
        #expect(chunks[0].index == 0)
        #expect(abs(chunks[0].start - 3) < 1e-9)
        // Closed as soon as its last 0.45 s were quiet, well before the 8 s cut.
        #expect(chunks[0].samples.count == 40_000)
        #expect(chunker.bufferedSamples == 1_600)
    }

    @Test func aPauseInsideOneLargeAppendIsStillFound() {
        var chunker = ScribeChunker()
        let chunks = chunker.append(tone(seconds: 2) + silence(seconds: 1) + tone(seconds: 2), at: 0)
        #expect(chunks.count == 1)
        #expect(chunks[0].samples.count == 40_000)
        #expect(chunker.bufferedSamples == 40_000)
    }

    @Test func aShortBufferIsNotCutAtAPause() {
        var chunker = ScribeChunker()
        let chunks = chunker.append(tone(seconds: 0.6) + silence(seconds: 0.6), at: 0)
        #expect(chunks.isEmpty)
        #expect(chunker.bufferedSamples == 19_200)
    }

    @Test func speechWithoutAPauseIsNotCutEarly() {
        var chunker = ScribeChunker()
        #expect(chunker.append(tone(seconds: 5), at: 0).isEmpty)
        #expect(chunker.bufferedSamples == 5 * ScribePCM.sampleRate)
    }

    @Test func nonFinitePauseCutTurnsPauseCutsOff() {
        var chunker = ScribeChunker(pauseCutAfterSeconds: .infinity)
        let chunks = chunker.append(tone(seconds: 2) + silence(seconds: 3), at: 0)
        #expect(chunks.isEmpty)
        #expect(chunker.bufferedSamples == 5 * ScribePCM.sampleRate)
    }

    @Test func previewIsNilWhenTheBufferIsShort() {
        var chunker = ScribeChunker()
        #expect(chunker.preview() == nil)
        _ = chunker.append(tone(seconds: 0.5), at: 0)
        #expect(chunker.preview() == nil)
        #expect(chunker.preview(minimumSeconds: 0.4) != nil)
        _ = chunker.append(tone(seconds: 0.6), at: 0.5)
        #expect(chunker.preview() != nil)
    }

    @Test func previewSharesItsIndexAndStartWithTheChunkThatLaterCloses() throws {
        var chunker = ScribeChunker()
        _ = chunker.append(tone(seconds: 2), at: 5)
        let first = try #require(chunker.preview())
        #expect(first.index == 0)
        #expect(abs(first.start - 5) < 1e-9)
        #expect(abs(first.duration - 2) < 1e-9)
        let closed = chunker.append(silence(seconds: 0.6), at: 7)
        #expect(closed.count == 1)
        #expect(closed[0].index == first.index)
        #expect(closed[0].start == first.start)
        #expect(Array(closed[0].samples.prefix(first.samples.count)) == first.samples)

        _ = chunker.append(tone(seconds: 1.5), at: 8)
        let second = try #require(chunker.preview())
        #expect(second.index == 1)
        let flushed = chunker.flush()
        let tail = try #require(flushed)
        #expect(tail.index == second.index)
    }

    @Test func previewDoesNotChangeTheChunker() {
        var chunker = ScribeChunker()
        _ = chunker.append(tone(seconds: 3), at: 0)
        let before = chunker.bufferedSamples
        _ = chunker.preview()
        #expect(chunker.bufferedSamples == before)
    }

    // MARK: Level meter

    @Test func levelMapsMinusFiftyToZeroAndFullScaleToOne() {
        #expect(ScribeLevelMeter.level([]) == 0)
        #expect(ScribeLevelMeter.level([Float](repeating: 0, count: 100)) == 0)
        #expect(ScribeLevelMeter.level([Float](repeating: 1, count: 100)) == 1)
        #expect(ScribeLevelMeter.level([Float](repeating: 3, count: 100)) == 1)
        #expect(ScribeLevelMeter.level([Float](repeating: 0.001, count: 100)) == 0)
        let minusTwentyFive = Float(pow(10.0, -25.0 / 20.0))
        #expect(abs(ScribeLevelMeter.level([Float](repeating: minusTwentyFive, count: 100)) - 0.5) < 0.01)
    }

    @Test func levelIsMonotonicInLoudness() {
        let levels = [0.004, 0.01, 0.05, 0.2, 0.8].map { ScribeLevelMeter.level([Float](repeating: Float($0), count: 64)) }
        #expect(levels == levels.sorted())
        #expect(Set(levels).count == levels.count)
    }

    @Test func barsPadWithZeroInFrontAndKeepTheNewestLast() {
        #expect(ScribeLevelMeter.barCount == 7)
        #expect(ScribeLevelMeter.bars(history: []) == [Double](repeating: 0, count: 7))
        #expect(ScribeLevelMeter.bars(history: [0.5, 0.2]) == [0, 0, 0, 0, 0, 0.5, 0.2])
        let long = (1...10).map { Double($0) / 10 }
        #expect(ScribeLevelMeter.bars(history: long) == Array(long.suffix(7)))
        #expect(ScribeLevelMeter.bars(history: [0.3, 0.4], count: 3) == [0, 0.3, 0.4])
        #expect(ScribeLevelMeter.bars(history: [0.3], count: 0).isEmpty)
        #expect(ScribeLevelMeter.bars(history: [-1, 2, .nan], count: 3) == [0, 1, 0])
        #expect(ScribeLevelMeter.silentBelow == 0.08)
    }

    // MARK: Word reveal

    @Test func reduceMotionShowsEveryWordAtOnce() {
        #expect(ScribeWordReveal.visibleWords(total: 20, alreadyShown: 0, since: 0, reduceMotion: true) == 20)
        #expect(ScribeWordReveal.visibleWords(total: 0, alreadyShown: 5, since: 0, reduceMotion: true) == 0)
    }

    @Test func wordsAppearOverTimeAndNeverShrink() {
        var previous = 0
        for step in 0...40 {
            let shown = ScribeWordReveal.visibleWords(total: 30, alreadyShown: 0, since: Double(step) * 0.1, reduceMotion: false)
            #expect(shown >= previous)
            #expect(shown <= 30)
            previous = shown
        }
        #expect(previous == 30)
        #expect(ScribeWordReveal.visibleWords(total: 30, alreadyShown: 0, since: 0.5, reduceMotion: false) == 6)
        #expect(ScribeWordReveal.visibleWords(total: 30, alreadyShown: 0, since: 0.5, wordsPerSecond: 4, reduceMotion: false) == 2)
    }

    @Test func wordsAlreadyOnScreenStayAndEverythingIsClamped() {
        #expect(ScribeWordReveal.visibleWords(total: 30, alreadyShown: 10, since: 0, reduceMotion: false) == 10)
        #expect(ScribeWordReveal.visibleWords(total: 8, alreadyShown: 20, since: 0, reduceMotion: false) == 8)
        #expect(ScribeWordReveal.visibleWords(total: 8, alreadyShown: -3, since: 0, reduceMotion: false) == 0)
        #expect(ScribeWordReveal.visibleWords(total: -4, alreadyShown: 0, since: 9, reduceMotion: false) == 0)
        #expect(ScribeWordReveal.visibleWords(total: 5, alreadyShown: 2, since: -1, reduceMotion: false) == 2)
        #expect(ScribeWordReveal.visibleWords(total: 5, alreadyShown: 2, since: .nan, reduceMotion: false) == 2)
        #expect(ScribeWordReveal.visibleWords(total: 5, alreadyShown: 0, since: 1e300, reduceMotion: false) == 5)
        #expect(ScribeWordReveal.visibleWords(total: 5, alreadyShown: 1, since: 3, wordsPerSecond: 0, reduceMotion: false) == 1)
    }

    @Test func additionsRevealOnTopOfWhatIsAlreadyShown() {
        // 20 words on screen, replacement text 25 words long: new words arrive at the reveal rate, not after 20/rate.
        #expect(ScribeWordReveal.visibleWords(total: 25, alreadyShown: 20, since: 0.5, reduceMotion: false) == 25)
        #expect(ScribeWordReveal.visibleWords(total: 30, alreadyShown: 10, since: 0.5, reduceMotion: false) == 16)
        #expect(ScribeWordReveal.visibleWords(total: 30, alreadyShown: 20, since: 0.2, reduceMotion: false) == 22)
        #expect(ScribeWordReveal.visibleWords(total: 30, alreadyShown: 20, since: 0.05, reduceMotion: false) == 20)
        #expect(ScribeWordReveal.visibleWords(total: 30, alreadyShown: 29, since: 100, reduceMotion: false) == 30)
    }

    // MARK: Speaker palette

    @Test func speakerColoursAreDeterministicAndDistinct() {
        #expect(ScribeSpeakerPalette.color(for: .you) == ScribeSpeakerPalette.color(for: .you))
        #expect(ScribeSpeakerPalette.color(for: .unknown) == ScribeSpeakerPalette.unknown)
        let tints = (1...6).map { ScribeSpeakerPalette.color(for: .participant("Speaker \($0)")) }
        for (index, tint) in tints.enumerated() {
            #expect(tints.firstIndex(of: tint) == index)
            #expect(tint != ScribeSpeakerPalette.color(for: .you))
            #expect(tint != ScribeSpeakerPalette.color(for: .unknown))
        }
        #expect(ScribeSpeakerPalette.color(for: .participant("Speaker 7")) == tints[0])
        #expect(ScribeSpeakerPalette.color(for: .participant("Speaker 12")) == tints[5])
    }

    @Test func theFirstParticipantIsBlueAndTheBareSystemLabelMatchesIt() {
        let first = ScribeSpeakerPalette.color(for: .participant("Speaker 1"))
        #expect(first.blue > first.red)
        #expect(first.blue > first.green)
        #expect(ScribeSpeakerPalette.color(for: .participant("Speaker")) == first)
        let green = ScribeSpeakerPalette.color(for: .you)
        #expect(green.green > green.red && green.green > green.blue)
    }

    @Test func otherParticipantNamesGetAStableTint() {
        let one = ScribeSpeakerPalette.color(for: .participant("Dana"))
        let two = ScribeSpeakerPalette.color(for: .participant("Dana"))
        #expect(one == two)
        #expect(ScribeSpeakerPalette.participants.contains(one))
    }

    // MARK: Speakers

    @Test func microphoneIsYouAndSystemIsOneParticipantLabel() {
        #expect(ScribeLiveSpeakers.speaker(for: .microphone) == .you)
        #expect(ScribeLiveSpeakers.speaker(for: .system) == .participant("Speaker"))
    }

    @Test func segmentIDsAreStablePerSourceAndChunk() {
        #expect(ScribeLiveSpeakers.segmentID(source: .microphone, chunkIndex: 3) == "mic-3")
        #expect(ScribeLiveSpeakers.segmentID(source: .system, chunkIndex: 3) == "sys-3")
    }

    // MARK: Preview engine

    @Test func previewsUseTheChosenOnDeviceEngineWhenReady() {
        let ready: [TranscriptionEngineKind: EngineAvailability] = [.parakeet: .ready, .whisper: .ready, .apple: .ready]
        #expect(ScribePreviewEngine.pick(preferred: .whisper, availability: ready) == .whisper)
    }

    @Test func previewsFallBackToTheFirstReadyOnDeviceEngine() {
        let states: [TranscriptionEngineKind: EngineAvailability] = [.whisper: .notDownloaded, .parakeet: .ready, .apple: .ready]
        #expect(ScribePreviewEngine.pick(preferred: .whisper, availability: states) == .parakeet)
        #expect(ScribePreviewEngine.pick(preferred: .whisperKit, availability: [.apple: .ready]) == .apple)
    }

    @Test func previewsNeverUseACloudEngineEvenWhenChosenAndReady() {
        let states: [TranscriptionEngineKind: EngineAvailability] = [.openAI: .ready, .elevenLabs: .ready, .apple: .ready]
        #expect(ScribePreviewEngine.pick(preferred: .openAI, availability: states) == .apple)
        #expect(ScribePreviewEngine.pick(preferred: .elevenLabs, availability: [.elevenLabs: .ready, .openAI: .ready]) == nil)
    }

    @Test func noReadyOnDeviceEngineMeansNoPreview() {
        #expect(ScribePreviewEngine.pick(preferred: .parakeet, availability: [:]) == nil)
        #expect(ScribePreviewEngine.pick(preferred: .apple, availability: [.apple: .downloading(0.5)]) == nil)
    }

    // MARK: Call-app identification

    @Test func nativeCallAppsAreIdentifiedByBundleID() {
        #expect(ScribeCallDetection.identify(bundleID: "com.microsoft.teams2") == .teams)
        #expect(ScribeCallDetection.identify(bundleID: "com.microsoft.teams2.modulehost") == .teams)
        #expect(ScribeCallDetection.identify(bundleID: "com.microsoft.teams") == .teams)
        #expect(ScribeCallDetection.identify(bundleID: "us.zoom.xos") == .zoom)
        #expect(ScribeCallDetection.identify(bundleID: "com.apple.FaceTime") == .other("FaceTime"))
        #expect(ScribeCallDetection.identify(bundleID: "com.tinyspeck.slackmacgap.helper") == .other("Slack"))
    }

    @Test func unrelatedAppsAndLookalikePrefixesAreNotCallApps() {
        #expect(ScribeCallDetection.identify(bundleID: "com.apple.Music") == nil)
        #expect(ScribeCallDetection.identify(bundleID: "us.zoom.xosfake") == nil)
        #expect(ScribeCallDetection.identify(bundleID: "app.zeus.mac") == nil)
        #expect(ScribeCallDetection.appBundleID(for: "com.example.thing") == nil)
    }

    @Test func browsersCountOnlyOnAMeetTab() {
        let chrome = "com.google.Chrome.helper"
        #expect(ScribeCallDetection.identify(bundleID: chrome, windowTitles: []) == nil)
        #expect(ScribeCallDetection.identify(bundleID: chrome, windowTitles: ["Inbox - Gmail"]) == nil)
        #expect(ScribeCallDetection.identify(bundleID: chrome, windowTitles: ["Inbox", "Meet – abc-defg-hij"]) == .meet)
        #expect(ScribeCallDetection.identify(bundleID: "com.apple.Safari", windowTitles: ["Meet - abc-defg-hij"]) == .meet)
        #expect(ScribeCallDetection.isBrowser(chrome))
        #expect(!ScribeCallDetection.isBrowser("us.zoom.xos"))
    }

    @Test func meetTitlesAcceptDashVariantsButNotOtherPages() {
        #expect(ScribeCallDetection.isMeetTitle("Meet – abc-defg-hij"))
        #expect(ScribeCallDetection.isMeetTitle("Meet - abc"))
        #expect(ScribeCallDetection.isMeetTitle("Meet — abc"))
        #expect(ScribeCallDetection.isMeetTitle("meet.google.com/abc-defg-hij"))
        #expect(!ScribeCallDetection.isMeetTitle("Meetings - Calendar"))
        #expect(!ScribeCallDetection.isMeetTitle("Team Meet"))
    }

    @Test func helperProcessesMapToTheirMainApp() {
        #expect(ScribeCallDetection.appBundleID(for: "com.google.Chrome.helper.Renderer") == "com.google.Chrome")
        #expect(ScribeCallDetection.appBundleID(for: "com.google.Chrome.canary.helper") == "com.google.Chrome.canary")
        #expect(ScribeCallDetection.appBundleID(for: "com.apple.WebKit.WebContent") == "com.apple.Safari")
    }

    @Test func displayNamesAreReadable() {
        #expect(ScribeCallDetection.displayName(.teams) == "Teams")
        #expect(ScribeCallDetection.displayName(.zoom) == "Zoom")
        #expect(ScribeCallDetection.displayName(.meet) == "Google Meet")
        #expect(ScribeCallDetection.displayName(.other("Slack")) == "Slack")
    }

    // MARK: Popup wording

    @Test func upcomingHeadlineCountsMinutesRoundedUp() {
        let now = Date(timeIntervalSince1970: 1_000)
        let slot = ScribeCalendarSlot(id: "a", title: "Design review", start: now.addingTimeInterval(61))
        #expect(ScribeCallPromptText.headline(for: .upcoming(slot), now: now) == "Starts in 2 min: Design review")
        let soon = ScribeCalendarSlot(id: "b", title: "Standup", start: now.addingTimeInterval(20))
        #expect(ScribeCallPromptText.headline(for: .upcoming(soon), now: now) == "Starts in 1 min: Standup")
    }

    @Test func startedAndUntitledMeetingsAndCallsHaveHonestHeadlines() {
        let now = Date(timeIntervalSince1970: 1_000)
        let started = ScribeCalendarSlot(id: "a", title: "  ", start: now.addingTimeInterval(-30))
        #expect(ScribeCallPromptText.headline(for: .upcoming(started), now: now) == "Started: Meeting")
        #expect(ScribeCallPromptText.headline(for: .callDetected(.teams), now: now) == "Meeting detected: Teams")
        #expect(ScribeCallPromptText.headline(for: .none, now: now) == nil)
    }

    @Test func meetingTitleComesFromTheEventOrTheCallApp() {
        let slot = ScribeCalendarSlot(id: "a", title: " Roadmap ", start: Date())
        #expect(ScribeCallPromptText.meetingTitle(for: .upcoming(slot)) == "Roadmap")
        #expect(ScribeCallPromptText.meetingTitle(for: .callDetected(.zoom)) == "Zoom call")
        #expect(ScribeCallPromptText.meetingTitle(for: .none) == nil)
    }

    // MARK: Record and store

    private func sampleRecord(id: UUID = UUID(), dismissedAt: Date? = nil) -> ScribeMeetingRecord {
        let session = ScribeSessionID(rawValue: id)
        let segments = [
            ScribeTranscriptSegment(id: "mic-0", session: session, speaker: .you, start: 0, end: 15, text: "We decided to ship.", isFinal: true),
            ScribeTranscriptSegment(id: "sys-0", session: session, speaker: .participant("Speaker"), start: 1, end: 16, text: "I will send it.", isFinal: true),
        ]
        let notes = ScribeMeetingNotes(
            summary: "We decided to ship.",
            decisions: ["We decided to ship."],
            actionItems: [ScribeActionItem(text: "I will send it.", done: true)],
            privateNotes: "my note",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            method: .extractive
        )
        return ScribeMeetingRecord(
            id: id, title: "Design review", endedAt: Date(timeIntervalSince1970: 1_700_000_100),
            duration: 99, notes: notes, transcript: segments, dismissedAt: dismissedAt
        )
    }

    @Test func recordConvertsBackToTheSameNotesAndSegments() {
        let id = UUID()
        let record = sampleRecord(id: id)
        let session = ScribeSessionID(rawValue: id)
        #expect(record.meetingNotes.summary == "We decided to ship.")
        #expect(record.meetingNotes.privateNotes == "my note")
        #expect(record.meetingNotes.method == .extractive)
        #expect(record.meetingNotes.actionItems == [ScribeActionItem(text: "I will send it.", done: true)])
        let segments = record.segments(session: session)
        #expect(segments.map(\.speaker) == [.you, .participant("Speaker")])
        #expect(segments.allSatisfy { $0.isFinal && $0.session == session })
        #expect(record.fileName == "\(id.uuidString.lowercased()).json")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scribe-live-tests-\(UUID().uuidString)", isDirectory: true)
        return url.appendingPathComponent("meetings", isDirectory: true)
    }

    @Test func storeSavesPrivatelyAndLoadsNewestFirst() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let store = ScribeMeetingStore(directory: directory)
        var older = sampleRecord()
        older.endedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let newer = sampleRecord()
        try store.save(older)
        try store.save(newer)

        let file = directory.appendingPathComponent(newer.fileName)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o700)

        let loaded = store.loadAll()
        #expect(loaded.failures.isEmpty)
        #expect(loaded.records == [newer, older])
    }

    @Test func storeOverwritesAtomicallyAndLeavesNoTemporaryFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let store = ScribeMeetingStore(directory: directory)
        var record = sampleRecord()
        try store.save(record)
        record.privateNotes = "changed"
        record.dismissedAt = Date(timeIntervalSince1970: 1_700_000_500)
        try store.save(record)

        let loaded = store.loadAll()
        #expect(loaded.records == [record])
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names == [record.fileName])
    }

    @Test func storeReportsUnreadableFilesInsteadOfSkippingThemSilently() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let store = ScribeMeetingStore(directory: directory)
        try store.save(sampleRecord())
        try Data("not json".utf8).write(to: directory.appendingPathComponent("broken.json"))

        let loaded = store.loadAll()
        #expect(loaded.records.count == 1)
        #expect(loaded.failures.count == 1)
        #expect(loaded.failures[0].hasPrefix("broken.json"))
    }

    @Test func storeWithNoFolderYetLoadsNothingWithoutFailures() throws {
        let directory = try temporaryDirectory()
        let loaded = ScribeMeetingStore(directory: directory).loadAll()
        #expect(loaded.records.isEmpty)
        #expect(loaded.failures.isEmpty)
    }

    @Test func storeSaveFailureIsThrownNotSwallowed() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-live-tests-\(UUID().uuidString)")
        try Data("a file, not a folder".utf8).write(to: base)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ScribeMeetingStore(directory: base.appendingPathComponent("meetings", isDirectory: true))
        #expect(throws: ScribeMeetingStoreError.self) { try store.save(sampleRecord()) }
    }

    @Test func transcriptionNoteSurvivesTheStoreAndOldFilesStillLoad() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let store = ScribeMeetingStore(directory: directory)
        var record = sampleRecord()
        record.transcriptionNote = "Transcription is behind."
        try store.save(record)
        #expect(store.loadAll().records.first?.transcriptionNote == "Transcription is behind.")
        #expect(sampleRecord().transcriptionNote == nil)
    }

    // MARK: Mute evidence (fail closed)

    @Test func freshEvidenceIsServedAndExpiredEvidenceIsUnknown() {
        let evidence = ScribeMuteEvidence(state: .unmuted, takenAt: 100)
        #expect(evidence.effectiveState(now: 100.5) == .unmuted)
        #expect(evidence.effectiveState(now: 101.5) == .unmuted)
        #expect(evidence.effectiveState(now: 101.51) == .unknown)
        #expect(evidence.effectiveState(now: 160) == .unknown)
        #expect(ScribeMuteEvidence(state: .muted, takenAt: 100).effectiveState(now: 100.2) == .muted)
    }

    @Test func missingOrFutureEvidenceIsUnknown() {
        #expect(ScribeMuteEvidence.effectiveState(nil, now: 5) == .unknown)
        #expect(ScribeMuteEvidence(state: .unmuted, takenAt: 10).effectiveState(now: 9) == .unknown)
    }

    @Test func refreshStartsWhenStaleAndNotWhileOneIsFreshlyInFlight() {
        func start(now: Double, taken: Double?, flight: Double?) -> Bool {
            ScribeMuteRefreshPolicy.shouldStart(now: now, evidenceTakenAt: taken, inFlightSince: flight, interval: 0.5, watchdog: 3)
        }
        #expect(start(now: 10, taken: nil, flight: nil))
        #expect(!start(now: 10, taken: 9.8, flight: nil))
        #expect(start(now: 10, taken: 9.4, flight: nil))
        #expect(!start(now: 10, taken: 9, flight: 9.5))
        // A read stalled past the watchdog no longer blocks a new one.
        #expect(start(now: 13, taken: 9, flight: 9.5))
    }


    private func native(_ pid: Int32 = 100, _ kind: String = "Zoom") -> ScribeCallIdentity {
        ScribeCallIdentity(pid: pid, kind: kind, source: .native)
    }

    private func web(_ pid: Int32 = 200, _ title: String = "Meet – abc-defg-hij", window: Int = 1000) -> ScribeCallIdentity {
        ScribeCallIdentity(pid: pid, kind: "Browser", source: .browserWindow, detail: title, windowNumber: window)
    }

    private func completed(_ calls: [ScribeCallIdentity] = [], browserUnknown: Bool = false) -> ScribeInputScan {
        .completed(calls: calls, browserUnknown: browserUnknown)
    }

    @Test func aMutedOrUnreadableDeviceNeverReadsUnmuted() {
        #expect(ScribeMuteResolver.resolve(device: .muted) == .muted)
        #expect(ScribeMuteResolver.resolve(device: .unreadable) == .unknown)
        #expect(ScribeMuteResolver.resolve(device: .notMuted) == .unmuted)
        #expect(ScribeMuteResolver.resolve(device: .noSwitch) == .unmuted)
    }

    @Test func anotherAppUsingTheMicrophoneNeverExcludesIt() {
        // A call, a browser that might be in one, or an owner Zeus can't identify: the person's microphone is
        // still recorded, because only the device's own mute decides. Each still counts as call evidence.
        for call in [native(100, "Zoom"), native(101, "Teams"), native(104, "FaceTime"), web()] {
            let scan = completed([call])
            #expect(ScribeMuteResolver.callDetected(scan: scan))
            #expect(ScribeMuteResolver.sample(device: .notMuted, callPresent: true)
                == ScribeMuteSample(admission: .unmuted, callPresent: true))
        }
        #expect(ScribeMuteResolver.callDetected(scan: completed(browserUnknown: true)))
        let unknownOwner = ScribeScanReducer.reduce(reads: [.input(pid: 50, bundleID: "com.example.unsupported-call")],
                                                    running: [], ownPID: 1)
        #expect(unknownOwner == .incomplete)
        #expect(ScribeMuteResolver.sample(device: .noSwitch, callPresent: false).admission == .unmuted)
        // Muting the device itself still withholds it, call or not.
        #expect(ScribeMuteResolver.sample(device: .muted, callPresent: true).admission == .muted)
    }

    @Test func aCallIsReportedAsTheReasonOnlyForACompleteScanWithAnIdentityOrBrowserDoubt() {
        #expect(ScribeMuteResolver.callDetected(scan: completed([native()])))
        #expect(ScribeMuteResolver.callDetected(scan: completed([web()])))
        #expect(ScribeMuteResolver.callDetected(scan: completed(browserUnknown: true)))
        #expect(!ScribeMuteResolver.callDetected(scan: completed()))
        #expect(!ScribeMuteResolver.callDetected(scan: .incomplete))
    }

    @Test func distinctBrowserWindowsWithIdenticalTitlesAreDistinctIdentities() {
        let first = web(200, "Zoom Meeting", window: 11)
        let second = web(200, "Zoom Meeting", window: 12)
        #expect(first != second)
        #expect(Set([first, second]).count == 2)
    }

    @Test func theSharedNoticeSaysZeusKeepsRecordingTheMicrophone() {
        #expect(ScribeMicCallText.sharedNotice
            == "Another app is using your microphone too. Zeus keeps recording it, so muting in that app does not mute Zeus.")
        #expect(!ScribeMicCallText.sharedNotice.contains("\u{2014}"))
    }

    // MARK: Scan reduction

    private let ownPID: Int32 = 1
    /// Window numbers default to 1000, 1001, ... in title order, like distinct CoreGraphics windows.
    private func app(
        _ bundle: String, pid: Int32 = 100, titles: [String]? = nil, numbers: [Int]? = nil, complete: Bool = true
    ) -> ScribeRunningApp {
        let defaults = (titles ?? []).indices.map { 1000 + $0 }
        return ScribeRunningApp(pid: pid, bundleID: bundle, windowTitles: titles, windowNumbers: numbers ?? defaults, titlesComplete: complete)
    }

    @Test func anUnreadableProcessMakesTheScanIncomplete() {
        let reads: [ScribeProcessRead] = [.idle, .unreadable, .idle]
        #expect(ScribeScanReducer.reduce(reads: reads, running: [], ownPID: ownPID) == .incomplete)
        // Never silently dropped, even when everything else looks empty.
        #expect(ScribeScanReducer.reduce(reads: [.unreadable], running: [app("com.apple.Music")], ownPID: ownPID) == .incomplete)
    }

    @Test func aFullyReadScanWithOnlyIdleExternalAppsIsEmptyAndPositive() {
        let reads: [ScribeProcessRead] = [.idle, .input(pid: ownPID, bundleID: "com.zeus.app")]
        let scan = ScribeScanReducer.reduce(reads: reads, running: [app("com.apple.Music")], ownPID: ownPID)
        #expect(scan == completed())
    }

    @Test func anUnknownActiveMicrophoneOwnerNeverInventsACallOrExcludesTheMicrophone() {
        for bundleID in ["com.example.unsupported-call", "com.example.new-browser", "", "com.apple.Music"] {
            let reads: [ScribeProcessRead] = [.input(pid: 50, bundleID: bundleID)]
            let running = [app(bundleID, pid: 50)]
            let scan = ScribeScanReducer.reduce(reads: reads, running: running, ownPID: ownPID)
            #expect(scan == .incomplete)
            #expect(ScribeMuteResolver.sample(device: .noSwitch, callPresent: false).admission == .unmuted)
            #expect(!ScribeScanReducer.callPresence(reads: reads, running: running, ownPID: ownPID))
        }
    }

    @Test func anUnknownInputDoesNotHideKnownCallEvidence() {
        let reads: [ScribeProcessRead] = [
            .input(pid: 50, bundleID: "com.example.unsupported-call"),
            .input(pid: 100, bundleID: "us.zoom.xos"),
        ]
        let running = [app("us.zoom.xos", pid: 100)]
        #expect(ScribeScanReducer.reduce(reads: reads, running: running, ownPID: ownPID) == .incomplete)
        #expect(ScribeScanReducer.callPresence(reads: reads, running: running, ownPID: ownPID))
    }

    @Test func aNativeCallAppIsAnIdentityOnlyWhileItCapturesTheMic() {
        // Idle in the background (no call): not a call.
        let idle = ScribeScanReducer.reduce(reads: [.idle], running: [app("us.zoom.xos", pid: 100)], ownPID: ownPID)
        #expect(idle == completed())
        #expect(!ScribeMuteResolver.callDetected(scan: idle))
        // The same app also capturing through a helper is still one identity.
        let both = ScribeScanReducer.reduce(
            reads: [.input(pid: 101, bundleID: "us.zoom.xos.helper")], running: [app("us.zoom.xos", pid: 100)], ownPID: ownPID
        )
        #expect(both == completed([native(100, "Zoom")]))
        let capturing = ScribeScanReducer.reduce(
            reads: [.input(pid: 9, bundleID: "com.microsoft.teams2.helper")], running: [], ownPID: ownPID
        )
        #expect(capturing == completed([native(9, "Teams")]))
    }

    @Test func aCapturingBrowserWithoutReadableTitlesIsUnknownButAnIdleOneIsNot() {
        let chrome = "com.google.Chrome"
        for titles in [nil, []] as [[String]?] {
            let scan = ScribeScanReducer.reduce(reads: [.input(pid: 7, bundleID: "com.google.Chrome.helper")], running: [app(chrome, titles: titles)], ownPID: ownPID)
            #expect(scan == completed(browserUnknown: true))
            // Window titles are hidden without Screen Recording; a browser not using the mic is in no call.
            let idle = ScribeScanReducer.reduce(reads: [.idle], running: [app(chrome, titles: titles)], ownPID: ownPID)
            #expect(idle == completed())
        }
    }

    @Test func oneReadableWindowPlusOneUnreadableWindowIsUnknown() {
        let scan = ScribeScanReducer.reduce(
            reads: [.input(pid: 7, bundleID: "com.google.Chrome.helper")], running: [app("com.google.Chrome", titles: ["Inbox"], complete: false)], ownPID: ownPID
        )
        #expect(scan == completed(browserUnknown: true))
        #expect(ScribeMuteResolver.callDetected(scan: scan))
        // Complete titles with no call name no call.
        let plain = ScribeScanReducer.reduce(reads: [.idle], running: [app("com.google.Chrome", titles: ["Inbox"])], ownPID: ownPID)
        #expect(!ScribeMuteResolver.callDetected(scan: plain))
    }

    @Test func browserTitlesDecideCallOrNoCall() {
        let chrome = "com.google.Chrome"
        let plain = ScribeScanReducer.reduce(reads: [.idle], running: [app(chrome, titles: ["Inbox - Gmail"])], ownPID: ownPID)
        #expect(plain == completed())
        for title in ["Meet – abc-defg-hij", "Zoom Meeting", "Weekly | Microsoft Teams", "Webex Meetings"] {
            let scan = ScribeScanReducer.reduce(reads: [.input(pid: 7, bundleID: "com.google.Chrome.helper")], running: [app(chrome, pid: 200, titles: [title])], ownPID: ownPID)
            #expect(scan == completed([web(200, title)]))
        }
    }

    @Test func twoBrowserCallWindowsAreTwoIdentities() {
        let scan = ScribeScanReducer.reduce(
            reads: [.input(pid: 7, bundleID: "com.google.Chrome.helper")],
            running: [app("com.google.Chrome", pid: 200, titles: ["Meet – abc-defg-hij", "Meet – xyz-uvwx-rst"])],
            ownPID: ownPID
        )
        #expect(scan == completed([web(200, "Meet – abc-defg-hij", window: 1000), web(200, "Meet – xyz-uvwx-rst", window: 1001)]))
    }

    @Test func twoBrowserWindowsWithIdenticalTitlesAreTwoIdentities() {
        let scan = ScribeScanReducer.reduce(
            reads: [.input(pid: 7, bundleID: "com.google.Chrome.helper")],
            running: [app("com.google.Chrome", pid: 200, titles: ["Zoom Meeting", "Zoom Meeting"], numbers: [41, 42])],
            ownPID: ownPID
        )
        #expect(scan == completed([web(200, "Zoom Meeting", window: 41), web(200, "Zoom Meeting", window: 42)]))
        #expect(ScribeMuteResolver.callDetected(scan: scan))
    }

    @Test func aMissingWindowNumberStillKeepsIdenticalTitlesApart() {
        let scan = ScribeScanReducer.reduce(
            reads: [.input(pid: 7, bundleID: "com.google.Chrome.helper")],
            running: [app("com.google.Chrome", pid: 200, titles: ["Zoom Meeting", "Zoom Meeting"], numbers: [])],
            ownPID: ownPID
        )
        guard case .completed(let calls, _) = scan else {
            Issue.record("expected a completed scan")
            return
        }
        #expect(calls.count == 2)
    }

    @Test func aNativeAppPlusABrowserCallListsBoth() {
        let scan = ScribeScanReducer.reduce(
            reads: [.input(pid: 101, bundleID: "us.zoom.xos"), .input(pid: 7, bundleID: "com.google.Chrome.helper")],
            running: [app("us.zoom.xos", pid: 100), app("com.google.Chrome", pid: 200, titles: ["Webex Meetings"])],
            ownPID: ownPID
        )
        #expect(scan == completed([native(100, "Zoom"), web(200, "Webex Meetings")]))
        #expect(ScribeMuteResolver.callDetected(scan: scan))
    }

    @Test func everyKnownCallAppCapturingTheMicIsAnIdentity() {
        for (bundle, kind) in [
            ("com.microsoft.teams2", "Teams"), ("us.zoom.xos", "Zoom"), ("com.cisco.webexmeetingsapp", "Webex"),
            ("com.tinyspeck.slackmacgap", "Slack"), ("com.apple.FaceTime", "FaceTime"),
        ] {
            let scan = ScribeScanReducer.reduce(reads: [.input(pid: 78, bundleID: bundle)], running: [app(bundle, pid: 77)], ownPID: ownPID)
            #expect(scan == completed([native(77, kind)]))
            #expect(ScribeMuteResolver.callDetected(scan: scan))
            let idle = ScribeScanReducer.reduce(reads: [.idle], running: [app(bundle, pid: 77)], ownPID: ownPID)
            #expect(!ScribeMuteResolver.callDetected(scan: idle))
        }
    }

    @Test func aBrowserUsingTheMicWithoutACallTitleIsUnknown() {
        let reads: [ScribeProcessRead] = [.input(pid: 7, bundleID: "com.google.Chrome.helper")]
        let scan = ScribeScanReducer.reduce(reads: reads, running: [app("com.google.Chrome", titles: ["Docs"])], ownPID: ownPID)
        #expect(scan == completed(browserUnknown: true))
        let orphan = ScribeScanReducer.reduce(reads: reads, running: [], ownPID: ownPID)
        #expect(orphan == completed(browserUnknown: true))
    }

    @Test func ownProcessesAreIgnored() {
        let reads: [ScribeProcessRead] = [.input(pid: ownPID, bundleID: "com.apple.WebKit.WebContent")]
        let scan = ScribeScanReducer.reduce(reads: reads, running: [app("us.zoom.xos", pid: ownPID)], ownPID: ownPID)
        #expect(scan == completed())
    }

    // MARK: Evidence coverage

    private func window(_ start: Double, _ end: Double) -> ScribeEvidenceWindow {
        ScribeEvidenceWindow(start: start, end: end)
    }

    @Test func aFullyCoveredIntervalIsAdmitted() {
        #expect(ScribeMicAdmission.coverage(start: 11, end: 12, windows: [window(10, 13)]) == .admitted)
        // Adjacent and overlapping windows join into one.
        #expect(ScribeMicAdmission.coverage(start: 11, end: 15, windows: [window(10, 12), window(12, 14), window(13.5, 16)]) == .admitted)
        #expect(ScribeMicAdmission.coverage(start: 10, end: 13, windows: [window(10, 13)]) == .admitted)
    }

    @Test func partialOrMissingCoverageIsDropped() {
        #expect(ScribeMicAdmission.coverage(start: 9.9, end: 12, windows: [window(10, 13)]) == .dropped(.unknown))
        #expect(ScribeMicAdmission.coverage(start: 11, end: 13.1, windows: [window(10, 13)]) == .dropped(.unknown))
        #expect(ScribeMicAdmission.coverage(start: 11, end: 15, windows: [window(10, 12), window(13, 16)]) == .dropped(.unknown))
        #expect(ScribeMicAdmission.coverage(start: 1, end: 2, windows: []) == .dropped(.unknown))
        #expect(ScribeMicAdmission.coverage(start: 2, end: 1, windows: [window(0, 5)]) == .dropped(.unknown))
    }

    @Test func aDropIsWordedMutedOnlyWhenTheNewestReadingSaysMuted() {
        #expect(ScribeMicAdmission.coverage(start: 1, end: 2, windows: [], latest: .muted) == .dropped(.muted))
        #expect(ScribeMicAdmission.coverage(start: 1, end: 2, windows: [], latest: .unknown) == .dropped(.unknown))
        #expect(ScribeMicAdmission.coverage(start: 1, end: 2, windows: [], latest: .unmuted) == .dropped(.unknown))
    }

    @Test func evidenceIsGoodForItsTimeToLiveAndNotLonger() {
        var timeline = ScribeMuteTimeline(timeToLive: 1.5)
        timeline.record(state: .unmuted, readStart: 100, readEnd: 100.1)
        #expect(timeline.coverage(start: 100.2, end: 101.4) == .admitted)
        // Stale: past readStart + timeToLive.
        #expect(timeline.coverage(start: 101, end: 101.6) == .dropped(.unknown))
        #expect(timeline.coverage(start: 110, end: 111) == .dropped(.unknown))
    }

    @Test func audioCapturedBeforeTheReadFinishedIsNotVouchedFor() {
        var timeline = ScribeMuteTimeline(timeToLive: 1.5)
        timeline.record(state: .unmuted, readStart: 100, readEnd: 100.4)
        #expect(timeline.coverage(start: 99.9, end: 100.2) == .dropped(.unknown))
        #expect(timeline.coverage(start: 100.3, end: 100.6) == .dropped(.unknown))
        #expect(timeline.coverage(start: 100.4, end: 100.6) == .admitted)
    }

    @Test func aStalledWorkerCannotAdmitMutedOrUnknownAudioWithLaterFreshEvidence() {
        var timeline = ScribeMuteTimeline(timeToLive: 1.5)
        timeline.record(state: .unmuted, readStart: 100, readEnd: 100.1)
        timeline.record(state: .muted, readStart: 101, readEnd: 101.1)
        timeline.record(state: .unknown, readStart: 103, readEnd: 103.1)
        timeline.record(state: .unmuted, readStart: 105, readEnd: 105.1)
        // The worker drains everything at t = 106, long after capture.
        #expect(timeline.coverage(start: 101.2, end: 101.8) == .dropped(.muted))
        #expect(timeline.coverage(start: 103.2, end: 104) == .dropped(.unknown))
        #expect(timeline.coverage(start: 102, end: 102.5) == .dropped(.muted))
        #expect(timeline.coverage(start: 104.2, end: 104.6) == .dropped(.unknown))
        // Audio from the unmuted windows is still admitted, and a muted reading clips the earlier window.
        #expect(timeline.coverage(start: 100.2, end: 100.9) == .admitted)
        #expect(timeline.coverage(start: 100.9, end: 101.2) == .dropped(.muted))
        #expect(timeline.coverage(start: 105.2, end: 106.4) == .admitted)
    }

    @Test func lateReadingsAreOrderedByWhenTheyStarted() {
        var timeline = ScribeMuteTimeline(timeToLive: 1.5)
        timeline.record(state: .unmuted, readStart: 100.5, readEnd: 100.6)
        timeline.record(state: .muted, readStart: 100.2, readEnd: 101)
        #expect(timeline.readings.map(\.state) == [.muted, .unmuted])
        #expect(timeline.coverage(start: 100.7, end: 101) == .admitted)
    }

    @Test func oldReadingsArePruned() {
        var timeline = ScribeMuteTimeline(timeToLive: 1.5, retention: 10)
        timeline.record(state: .unmuted, readStart: 0, readEnd: 0.1)
        timeline.record(state: .unmuted, readStart: 50, readEnd: 50.1)
        #expect(timeline.readings.count == 1)
    }

    // MARK: Invalid capture time

    @Test func anInvalidHostTimeIsNeverStampedFromCallbackTime() {
        #expect(ScribeMicStamp.captureStart(hostTimeValid: false, hostTime: 123_456) == nil)
        #expect(ScribeMicStamp.captureStart(hostTimeValid: true, hostTime: 0) == 0)
    }

    @Test func aDelayedBlockWithAnInvalidTimestampIsDroppedEvenInsideAFreshUnmutedWindow() {
        var timeline = ScribeMuteTimeline(timeToLive: 1.5)
        // Muted (or unknown) at capture time, unmuted by the time the delayed block is drained.
        timeline.record(state: .muted, readStart: 100, readEnd: 100.1)
        timeline.record(state: .unmuted, readStart: 105, readEnd: 105.1)
        let start = ScribeMicStamp.captureStart(hostTimeValid: false, hostTime: 0)
        #expect(timeline.coverage(start: start, seconds: 0.1) == .dropped(.unknown))
        // The same block with a valid early stamp is dropped by coverage; a valid fresh stamp is admitted.
        #expect(timeline.coverage(start: 100.2, seconds: 0.1) == .dropped(.muted))
        #expect(timeline.coverage(start: 105.2, seconds: 0.1) == .admitted)
    }

    @Test func theCallFlagFollowsTheNewestReadingThatBeganByTheIntervalsEnd() {
        var timeline = ScribeMuteTimeline(timeToLive: 1.5)
        timeline.record(state: .unknown, readStart: 100, readEnd: 100.1, callDetected: true)
        timeline.record(state: .unmuted, readStart: 105, readEnd: 105.1, callDetected: false)
        #expect(timeline.callDetected(start: 100.2, seconds: 0.1))
        #expect(!timeline.callDetected(start: 105.2, seconds: 0.1))
        // A delayed block still sees the reading that was current when it was captured.
        #expect(timeline.callDetected(start: 101, seconds: 0.5))
        // Unknown capture time reads the newest reading.
        #expect(!timeline.callDetected(start: nil, seconds: 0.1))
        #expect(!ScribeMuteTimeline().callDetected(start: 1, seconds: 1))
    }

    /// Mirrors the capture run: each reading joins the timeline, the next microphone interval is admitted or
    /// dropped against it, and the ownership machine reports "shared with another app" on change.
    private func recordDuringCall(_ readings: [ScribeMuteSample]) -> (admitted: [Bool], shared: [Bool]) {
        var timeline = ScribeMuteTimeline(timeToLive: 1.5)
        var ownership = MicInputOwnership()
        var admitted: [Bool] = []
        var shared: [Bool] = []
        _ = ownership.apply(.zeusStarted)
        for (index, reading) in readings.enumerated() {
            let start = Double(index) * 10
            timeline.record(state: reading.admission, readStart: start, readEnd: start + 0.1, callDetected: reading.callPresent)
            let coverage = timeline.coverage(start: start + 0.2, seconds: 0.1)
            admitted.append(coverage == .admitted)
            let otherApp = timeline.callDetected(start: start + 0.2, seconds: 0.1)
            for case .sharedChanged(let value) in ownership.apply(.otherApp(active: otherApp)) { shared.append(value) }
        }
        for case .sharedChanged(let value) in ownership.apply(.zeusStopped) { shared.append(value) }
        return (admitted, shared)
    }

    @Test func zoomInACallKeepsTheMicrophoneUnlessTheDeviceItselfIsMuted() {
        let reads: [ScribeProcessRead] = [.input(pid: 101, bundleID: "us.zoom.xos")]
        let present = ScribeScanReducer.callPresence(reads: reads, running: [app("us.zoom.xos", pid: 100)], ownPID: ownPID)
        let muted = ScribeMuteResolver.sample(device: .muted, callPresent: present)
        let open = ScribeMuteResolver.sample(device: .notMuted, callPresent: present)
        #expect(muted == ScribeMuteSample(admission: .muted, callPresent: true))
        #expect(open == ScribeMuteSample(admission: .unmuted, callPresent: true))
        let run = recordDuringCall([open, muted, open])
        #expect(run.admitted == [true, false, true])
        #expect(run.shared == [true, false])
    }

    @Test func anUnreadableProcessWithAKnownCallAppStillReportsACallAndKeepsTheMicrophone() {
        let reads: [ScribeProcessRead] = [.input(pid: 101, bundleID: "us.zoom.xos"), .unreadable]
        let running = [app("us.zoom.xos", pid: 100)]
        #expect(ScribeScanReducer.reduce(reads: reads, running: running, ownPID: ownPID) == .incomplete)
        let present = ScribeScanReducer.callPresence(reads: reads, running: running, ownPID: ownPID)
        let sample = ScribeMuteResolver.sample(device: .notMuted, callPresent: present)
        #expect(sample == ScribeMuteSample(admission: .unmuted, callPresent: true))
        #expect(recordDuringCall([sample]).admitted == [true])
    }

    @Test func theSharedStateClearsAsSoonAsTheOtherAppLetsGo() {
        let inCall = ScribeMuteResolver.sample(device: .noSwitch, callPresent: true)
        let afterCall = ScribeMuteResolver.sample(device: .noSwitch, callPresent: false)
        let run = recordDuringCall([afterCall, inCall, inCall, afterCall, afterCall])
        #expect(run.admitted == [true, true, true, true, true])
        #expect(run.shared == [true, false])
    }

    @Test func callPresenceIsFalseWithoutCallEvidence() {
        let reads: [ScribeProcessRead] = [.idle, .unreadable]
        let running = [app("com.apple.Music")]
        let present = ScribeScanReducer.callPresence(reads: reads, running: running, ownPID: ownPID)
        #expect(!present)
        let sample = ScribeMuteResolver.sample(device: .noSwitch, callPresent: present)
        #expect(sample == ScribeMuteSample(admission: .unmuted, callPresent: false))
        #expect(recordDuringCall([sample]).shared.isEmpty)
        // Presence is also ignorant of own-process entries.
        #expect(!ScribeScanReducer.callPresence(reads: [], running: [app("us.zoom.xos", pid: ownPID)], ownPID: ownPID))
    }

    @Test func theCallFlagSurvivesTheStoreAndOldFilesStillLoad() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let store = ScribeMeetingStore(directory: directory)
        var record = sampleRecord()
        #expect(record.micExcludedDuringCall == nil)
        record.micExcludedDuringCall = true
        try store.save(record)
        #expect(store.loadAll().records.first?.micExcludedDuringCall == true)
        let flagged = ScribeMeetingRecord(
            id: UUID(), title: "Call", endedAt: Date(), duration: 1, notes: ScribeMeetingNotes(), transcript: [],
            micExcludedDuringCall: true
        )
        #expect(flagged.micExcludedDuringCall == true)
    }

    // MARK: Ring contention

    @Test func aFinalContendedWriteIsReportedByTheShutdownDrainWithoutAnotherWrite() {
        let ring = ScribeSampleRing(capacityFrames: 1024, channels: 1)
        #expect(ring.write(frames: 100, at: 1) { _, _ in 0.1 })
        // The last callback loses the lock; capture stops, so no later write folds the loss in.
        ring.recordContentionLoss(frames: 480)
        let drained = ring.drainBlocks()
        #expect(drained.samples.count == 100)
        #expect(ring.takeDroppedFrames() == 480)
        // Read and cleared.
        #expect(ring.takeDroppedFrames() == 0)
    }

    @Test func contentionAndFullRingLossesAreBothCounted() {
        let ring = ScribeSampleRing(capacityFrames: 10, channels: 1)
        #expect(ring.write(frames: 8, at: 1) { _, _ in 0 })
        #expect(!ring.write(frames: 8, at: 2) { _, _ in 0 })
        ring.recordContentionLoss(frames: 5)
        #expect(ring.takeDroppedFrames() == 13)
    }

    @Test func contentionLossesAccumulateAndAreClearedByEachTake() {
        let ring = ScribeSampleRing(capacityFrames: 16, channels: 1)
        #expect(ring.takeDroppedFrames() == 0)
        ring.recordContentionLoss(frames: 100)
        ring.recordContentionLoss(frames: 28)
        #expect(ring.takeDroppedFrames() == 128)
        #expect(ring.takeDroppedFrames() == 0)
        ring.recordContentionLoss(frames: 7)
        #expect(ring.takeDroppedFrames() == 7)
    }

    @Test func concurrentContentionLossesAreNeverLost() async {
        let ring = ScribeSampleRing(capacityFrames: 16, channels: 1)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<1_000 { ring.recordContentionLoss(frames: 3) }
                }
            }
        }
        #expect(ring.takeDroppedFrames() == 8 * 1_000 * 3)
    }

    // MARK: Save failures per meeting

    @Test func aSuccessClearsOnlyItsOwnMeetingsFailure() {
        var tracker = ScribeSaveFailureTracker<String>()
        let a = UUID()
        let b = UUID()
        tracker.recordFailure(id: a, message: "A failed", payload: "recap A")
        let strangerCleared = tracker.recordSuccess(id: b)
        #expect(!strangerCleared)
        #expect(tracker.entries.map(\.id) == [a])
        tracker.recordFailure(id: b, message: "B failed", payload: "recap B")
        #expect(tracker.entries.map(\.id) == [a, b])
        let ownCleared = tracker.recordSuccess(id: b)
        #expect(ownCleared)
        #expect(tracker.entries.map(\.message) == ["A failed"])
        #expect(tracker.entry(for: a)?.payload == "recap A")
    }

    @Test func aRepeatedFailureReplacesInPlaceAndDismissAllClears() {
        var tracker = ScribeSaveFailureTracker<Int>()
        let a = UUID()
        let b = UUID()
        tracker.recordFailure(id: a, message: "first", payload: 1)
        tracker.recordFailure(id: b, message: "other", payload: 2)
        tracker.recordFailure(id: a, message: "second", payload: 3)
        #expect(tracker.entries.map(\.message) == ["second", "other"])
        #expect(tracker.entries.first?.payload == 3)
        tracker.dismissAll()
        #expect(tracker.isEmpty)
    }

    // MARK: Host clock

    @Test func hostClockIsMonotonicAndConvertsTicks() {
        let first = ScribeHostClock.now()
        let second = ScribeHostClock.now()
        #expect(second >= first)
        #expect(ScribeHostClock.seconds(hostTime: 0) == 0)
    }

    // MARK: System audio support

    @Test func systemAudioNeedsMacOS14Point2() {
        #expect(!ScribeSystemAudioSupport.isSupported(major: 14, minor: 1))
        #expect(!ScribeSystemAudioSupport.isSupported(major: 13, minor: 6))
        #expect(ScribeSystemAudioSupport.isSupported(major: 14, minor: 2))
        #expect(ScribeSystemAudioSupport.isSupported(major: 15, minor: 0))
        #expect(ScribeSystemAudioSupport.unavailableMessage == "System audio capture needs macOS 14.2 or later.")
    }

    // MARK: Bounded queue

    @Test func fullQueueDropsTheOldestAndCountsIt() {
        var queue = ScribeBoundedQueue<Int>(capacity: 4)
        for value in 1...4 {
            let evicted = queue.push(value)
            #expect(evicted == nil)
        }
        let evictedFive = queue.push(5)
        let evictedSix = queue.push(6)
        #expect(evictedFive == 1)
        #expect(evictedSix == 2)
        #expect(queue.droppedCount == 2)
        #expect(queue.count == 4)
        #expect(queue.first == 3)
        var popped: [Int] = []
        while let value = queue.pop() { popped.append(value) }
        #expect(popped == [3, 4, 5, 6])
        #expect(queue.isEmpty)
    }

    @Test func queueCapacityIsAtLeastOneAndClearKeepsTheDropCount() {
        var queue = ScribeBoundedQueue<Int>(capacity: 0)
        #expect(queue.capacity == 1)
        queue.push(1)
        queue.push(2)
        queue.removeAll()
        #expect(queue.isEmpty)
        #expect(queue.droppedCount == 1)
    }

    // MARK: Shutdown order

    @Test func shutdownStopsAndSynchronizesProducersBeforeTheFinalDrainAndEndsLast() {
        let order = ScribeShutdown.order
        func index(_ step: ScribeShutdownStep) -> Int { order.firstIndex(of: step) ?? -1 }
        #expect(index(.stopProducers) == 0)
        #expect(index(.stopProducers) < index(.synchronizeProducers))
        #expect(index(.synchronizeProducers) < index(.drainRemaining))
        #expect(index(.drainRemaining) < index(.closeDelivery))
        #expect(order.last == .emitEnded)
        #expect(Set(order).count == order.count)
    }

    // MARK: Sample ring

    @Test func ringReturnsInterleavedFramesInOrder() {
        let ring = ScribeSampleRing(capacityFrames: 8, channels: 2)
        #expect(ring.write(frames: 3) { frame, channel in Float(frame * 10 + channel) })
        #expect(ring.drain() == [0, 1, 10, 11, 20, 21])
        #expect(ring.drain().isEmpty)
    }

    @Test func ringWrapsAroundWithoutLosingOrder() {
        let ring = ScribeSampleRing(capacityFrames: 4, channels: 1)
        #expect(ring.write(frames: 3) { frame, _ in Float(frame) })
        #expect(ring.drain(maxFrames: 2) == [0, 1])
        #expect(ring.write(frames: 3) { frame, _ in Float(10 + frame) })
        #expect(ring.drain() == [2, 10, 11, 12])
    }

    @Test func ringDropsAWholeWriteWhenFullAndCountsIt() {
        let ring = ScribeSampleRing(capacityFrames: 4, channels: 1)
        #expect(ring.write(frames: 3) { _, _ in 1 })
        #expect(!ring.write(frames: 2) { _, _ in 9 })
        #expect(ring.storedFrames == 3)
        #expect(ring.takeDroppedFrames() == 2)
        #expect(ring.takeDroppedFrames() == 0)
        #expect(ring.drain() == [1, 1, 1])
    }

    @Test func ringDrainRespectsTheFrameLimit() {
        let ring = ScribeSampleRing(capacityFrames: 16, channels: 2)
        ring.write(frames: 6) { frame, _ in Float(frame) }
        #expect(ring.drain(maxFrames: 4).count == 8)
        #expect(ring.drain(maxFrames: 4).count == 4)
        #expect(ring.drain(maxFrames: 0).isEmpty)
    }

    @Test func ringCarriesCaptureTimesWithItsBlocks() {
        let ring = ScribeSampleRing(capacityFrames: 64, channels: 1, sampleRate: 10)
        ring.write(frames: 4, at: 100) { _, _ in 1 }
        ring.write(frames: 2, at: 200) { _, _ in 2 }
        ring.write(frames: 3) { _, _ in 3 }
        let drained = ring.drainBlocks()
        #expect(drained.samples == [1, 1, 1, 1, 2, 2, 3, 3, 3])
        #expect(drained.blocks == [
            ScribeSampleRing.Block(frames: 4, start: 100),
            ScribeSampleRing.Block(frames: 2, start: 200),
            ScribeSampleRing.Block(frames: 3, start: nil),
        ])
    }

    @Test func aPartialDrainAdvancesTheRemainingBlocksStart() {
        let ring = ScribeSampleRing(capacityFrames: 64, channels: 2, sampleRate: 10)
        ring.write(frames: 5, at: 100) { _, _ in 1 }
        let first = ring.drainBlocks(maxFrames: 2)
        #expect(first.samples.count == 4)
        #expect(first.blocks == [ScribeSampleRing.Block(frames: 2, start: 100)])
        let second = ring.drainBlocks()
        #expect(second.samples.count == 6)
        #expect(second.blocks.count == 1)
        #expect(second.blocks[0].frames == 3)
        #expect(abs((second.blocks[0].start ?? 0) - 100.2) < 1e-9)
    }

    @Test func ringKeepsBlockTimesAcrossWrapAndDroppedWrites() {
        let ring = ScribeSampleRing(capacityFrames: 4, channels: 1, sampleRate: 10)
        ring.write(frames: 3, at: 1) { _, _ in 1 }
        #expect(!ring.write(frames: 3, at: 2) { _, _ in 9 })
        _ = ring.drainBlocks(maxFrames: 2)
        ring.write(frames: 3, at: 5) { _, _ in 2 }
        let rest = ring.drainBlocks()
        #expect(rest.blocks.map(\.frames) == [1, 3])
        #expect(abs((rest.blocks[0].start ?? 0) - 1.2) < 1e-9)
        #expect(rest.blocks[1].start == 5)
        #expect(ring.takeDroppedFrames() == 3)
    }
}
