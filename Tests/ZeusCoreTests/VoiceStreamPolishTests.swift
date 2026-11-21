import Foundation
import Testing
@testable import ZeusCore

/// Loudness fixtures, measured with pyloudnorm 0.1.1 (numpy 2.5.5, scipy 1.18.1).
///
/// Sine: one second, 48 kHz, 200 Hz, amplitude 0.25.
/// ```
/// t = numpy.arange(48000) / 48000
/// sine = 0.25 * numpy.sin(2 * numpy.pi * 200 * t)
/// pyloudnorm.Meter(48000).integrated_loudness(sine) == -16.050401513837055
/// ```
/// True peak of that sine, `max(abs(scipy.signal.resample_poly(sine, 4, 1)))`, is 0.250159141272278.
///
/// Noise: one second, 48 kHz, LCG seed `0x5EED` (`state = 1664525 * state + 1013904223`),
/// uniform on [-1, 1], then scaled so the sample peak is 0.2.
/// `integrated_loudness` is -15.643973357363588. After a gain to -16 LUFS the same meter
/// reads -16.0 and the 4× true peak is about -8.90 dBTP, under the -1 dBTP ceiling.
///
/// A six-sample probe `[0, 0.5, 1, -1, 0.25, 0]` has 4× true peak 1.2442025609169483.

private let chunkCases: [(name: String, language: String, text: String, expected: [String])] = [
    ("empty", "en", "", []),
    ("whitespace", "en", "   \n  ", []),
    ("short ack", "en", "OK, done.", ["OK, done."]),
    ("one medium sentence", "en", "This reply is short enough to speak as one chunk.", ["This reply is short enough to speak as one chunk."]),
    ("two sentences", "en", "The build finished cleanly this morning. The notes are in the log.", ["The build finished cleanly this morning.", "The notes are in the log."]),
    ("three sentences", "en", "The patch is in. The tests passed. Ship it.", ["The patch is in.", "The tests passed.", "Ship it."]),
    ("comma clause", "en", "Once the morning build has fully finished, the rest of this sentence continues well beyond the ninety character clause window and keeps going.", ["Once the morning build has fully finished,", "the rest of this sentence continues well beyond the ninety character clause window and keeps going."]),
    ("semicolon clause", "en", "Once the morning build has fully finished; the rest of this sentence continues well beyond the ninety character clause window and keeps going.", ["Once the morning build has fully finished;", "the rest of this sentence continues well beyond the ninety character clause window and keeps going."]),
    ("colon clause", "en", "Once the morning build has fully finished: the rest of this sentence continues well beyond the ninety character clause window and keeps going.", ["Once the morning build has fully finished:", "the rest of this sentence continues well beyond the ninety character clause window and keeps going."]),
    ("em dash clause", "en", "Once the morning build has fully finished — the rest of this sentence continues well beyond the ninety character clause window and keeps going.", ["Once the morning build has fully finished —", "the rest of this sentence continues well beyond the ninety character clause window and keeps going."]),
    ("and conjunction", "en", "Once the morning build has fully finished and the rest of this sentence continues well beyond the ninety character clause window.", ["Once the morning build has fully finished", "and the rest of this sentence continues well beyond the ninety character clause window."]),
    ("decimal point", "en", "Version 3.14159 is the pinned value for this release, and the explanation after that continues past ninety characters easily.", ["Version 3.14159 is the pinned value for this release,", "and the explanation after that continues past ninety characters easily."]),
    ("doctor abbreviation", "en", "Dr. Amelia wrote the release note, and then she explained the rest of the very long result in careful detail today.", ["Dr. Amelia wrote the release note, and then she explained the rest of the very long result", "in careful detail today."]),
    ("mr and mrs", "en", "Mr. and Mrs. Hale arrived early this morning. They brought the signed copy with them.", ["Mr. and Mrs. Hale arrived early this morning.", "They brought the signed copy with them."]),
    ("am and pm", "en", "The window opens at 9 a.m. sharp today. Please be there before the review.", ["The window opens at 9 a.m. sharp today.", "Please be there before the review."]),
    ("us abbreviation", "en", "The U.S. team signed off yesterday afternoon. The notes are filed with the release.", ["The U.S. team signed off yesterday afternoon.", "The notes are filed with the release."]),
    ("inc abbreviation", "en", "Acme Inc. shipped the patch last night. Customers can update this morning.", ["Acme Inc. shipped the patch last night.", "Customers can update this morning."]),
    ("https url", "en", "Read https://example.com/docs/v1.2/guide now, then continue with the longer explanation that follows this clause today.", ["Read https://example.com/docs/v1.2/guide now,", "then continue with the longer explanation that follows this clause today."]),
    ("www url", "en", "See www.example.com/a.b/guide for the note. Then read the rest.", ["See www.example.com/a.b/guide for the note.", "Then read the rest."]),
    ("question", "en", "Are you ready to ship the build today? The rest of the answer follows in another sentence.", ["Are you ready to ship the build today?", "The rest of the answer follows in another sentence."]),
    ("exclamation", "en", "The build is green and ready to ship! The rest of the answer follows in another sentence.", ["The build is green and ready to ship!", "The rest of the answer follows in another sentence."]),
    ("ellipsis", "en", "Wait... the build is still running and this sentence keeps going past the ninety character window easily.", ["Wait...", "the build is still running and this sentence keeps going past the ninety character window easily."]),
    ("digit ellipsis", "en", "Pages 1...5 stay together. The next sentence is separate.", ["Pages 1...5 stay together.", "The next sentence is separate."]),
    ("quoted stop", "en", "He said \"stop.\" Then he left the room.", ["He said \"stop.\"", "Then he left the room."]),
    ("no clause boundary", "en", "Supercalifragilisticexpialidocious wording without a comma keeps rolling forward until a space finally appears well after the forty mark and beyond ninety too.", ["Supercalifragilisticexpialidocious wording without a comma keeps rolling forward until a", "space finally appears well after the forty mark and beyond ninety too."]),
    ("number abbreviation", "en", "See No. 12 in the index for the full citation. The next sentence stays whole.", ["See No. 12 in the index for the full citation.", "The next sentence stays whole."]),
    ("eg abbreviation", "en", "Use e.g. this form in the note. Then continue with the longer explanation.", ["Use e.g. this form in the note.", "Then continue with the longer explanation."]),
    ("initials", "en", "J. R. R. Tolkien wrote it. The next sentence follows.", ["J. R. R. Tolkien wrote it.", "The next sentence follows."]),
    ("pronoun i", "en", "So was I. Then he left.", ["So was I.", "Then he left."]),
    ("short decimal", "en", "Pi is 3.5 today. Tomorrow we ship.", ["Pi is 3.5 today.", "Tomorrow we ship."]),
    ("short greeting", "fr", "Bonjour, le correctif est prêt.", ["Bonjour, le correctif est prêt."]),
    ("french question", "fr", "Est-ce que le correctif est prêt ? La suite arrive dans la phrase suivante.", ["Est-ce que le correctif est prêt ?", "La suite arrive dans la phrase suivante."]),
    ("monsieur", "fr", "M. Dupont a signé le document hier soir. La copie est au dossier.", ["M. Dupont a signé le document hier soir.", "La copie est au dossier."]),
    ("madame", "fr", "Mme Curie a publié le résultat hier. La suite est dans le journal.", ["Mme Curie a publié le résultat hier.", "La suite est dans le journal."]),
    ("mademoiselle", "fr", "Mlle Martin arrive demain matin. Le bureau ouvre à neuf heures.", ["Mlle Martin arrive demain matin.", "Le bureau ouvre à neuf heures."]),
    ("french doctor", "fr", "Le Dr Martin a validé le résultat ce matin. La note reste courte.", ["Le Dr Martin a validé le résultat ce matin.", "La note reste courte."]),
    ("decimal comma", "fr", "Le total est de 12,50 euros pour ce lot, puis la phrase continue longtemps au-delà de la fenêtre du premier morceau prévu ici.", ["Le total est de 12,50 euros pour ce lot,", "puis la phrase continue longtemps au-delà de la fenêtre du premier morceau prévu ici."]),
    ("et conjunction", "fr", "Le correctif du matin est validé et la suite de la phrase française continue bien au-delà des quatre-vingt-dix caractères.", ["Le correctif du matin est validé et la suite de la phrase française continue bien au-delà", "des quatre-vingt-dix caractères."]),
    ("french url", "fr", "Voir https://exemple.fr/docs/v1.2/guide maintenant, puis continuer avec le reste de l'explication qui suit ce premier morceau.", ["Voir https://exemple.fr/docs/v1.2/guide maintenant,", "puis continuer avec le reste de l'explication qui suit ce premier morceau."]),
    ("guillemets", "fr", "Il a dit « bonjour ». La suite de la réponse arrive ensuite.", ["Il a dit « bonjour ».", "La suite de la réponse arrive ensuite."]),
    ("cad abbreviation", "fr", "Le correctif est prêt, c.-à-d. la version que nous avons testée. La suite reste une phrase entière.", ["Le correctif est prêt, c.-à-d. la version que nous avons testée.", "La suite reste une phrase entière."]),
    ("mais clause", "fr", "Le correctif du matin est validé, mais la suite de cette phrase française continue bien au-delà de la fenêtre prévue pour le premier morceau.", ["Le correctif du matin est validé, mais la suite de cette phrase française continue bien", "au-delà de la fenêtre prévue pour le premier morceau."]),
]

@Suite struct VoiceStreamPolishTests {
    @Test func clauseChunkerCoversEnglishAndFrench() {
        let english = chunkCases.filter { $0.language == "en" }
        let french = chunkCases.filter { $0.language == "fr" }
        #expect(english.count >= 20)
        #expect(french.count >= 10)
        for item in chunkCases {
            let pieces = SpeechClauseChunker.chunks(of: item.text)
            #expect(pieces == item.expected, "\(item.name)")
            if item.text.count > 90, let first = pieces.first, first.count >= 40, first.count < item.text.count {
                #expect((40...90).contains(first.count), "\(item.name) opened at \(first.count)")
            }
        }
    }

    @Test func crossfadeKeepsTheJoinContinuous() {
        let rate = 24_000.0
        let count = 2_000
        let frequency = 200.0
        let amplitude: Float = 0.6
        let leftPhase = Double.pi / 2 - 2 * Double.pi * frequency * Double(count - 1) / rate
        let left = tone(count: count, frequency: frequency, amplitude: amplitude, sampleRate: rate, phase: leftPhase)
        let right = tone(count: count, frequency: frequency, amplitude: amplitude, sampleRate: rate, phase: -Double.pi / 2)
        let fade = EqualPowerCrossfade.fadeSamples(sampleRate: rate)
        #expect(Double(fade) / rate >= 0.010 && Double(fade) / rate <= 0.030)
        let joined = EqualPowerCrossfade.join(left, right, sampleRate: rate)
        #expect(joined.count == left.count + right.count - fade)
        #expect(maxAdjacentStep(left + right) > 0.5)
        #expect(maxAdjacentStep(joined) < 0.08)
    }

    @Test func primerHoldsTheOnsetNearSilence() {
        let rate = 24_000.0
        let input = [Float](repeating: 0.5, count: 2_400)
        let output = WarmupPrimer.apply(input, sampleRate: rate)
        let primer = WarmupPrimer.sampleCount(sampleRate: rate)
        let milliseconds = Double(primer) / rate * 1_000
        #expect(milliseconds >= 40 && milliseconds <= 80)
        #expect(output.count == input.count + primer)
        let onset = Int(rate * 0.040)
        #expect(output.prefix(onset).allSatisfy { abs($0) < 1e-4 })
        let later = primer + Int(rate * 0.020)
        #expect(abs(output[primer]) < abs(output[later]))
        #expect(abs(output[later] - 0.5) < 0.02)
    }

    @Test func loudnessLandsOnMinusSixteenForSineAndNoise() {
        let rate = 48_000.0
        let sine = tone(count: 48_000, frequency: 200, amplitude: 0.25, sampleRate: rate, phase: 0)
        let sineLUFS = LoudnessNormalizer.measureIntegratedLUFS(sine, sampleRate: rate)
        #expect(abs(sineLUFS - (-16.050401513837055)) < 0.05)
        var normalizer = LoudnessNormalizer()
        let normalizedSine = normalizer.normalize(sine, sampleRate: rate)
        let sineOut = LoudnessNormalizer.measureIntegratedLUFS(normalizedSine, sampleRate: rate)
        #expect(abs(sineOut - (-16)) <= 0.5)

        let noise = lcgNoise(count: 48_000)
        #expect(abs(noise[0] - 0.0615952668) < 1e-5)
        let noiseLUFS = LoudnessNormalizer.measureIntegratedLUFS(noise, sampleRate: rate)
        #expect(abs(noiseLUFS - (-15.643973357363588)) < 0.05)
        normalizer.reset()
        let normalizedNoise = normalizer.normalize(noise, sampleRate: rate)
        let noiseOut = LoudnessNormalizer.measureIntegratedLUFS(normalizedNoise, sampleRate: rate)
        #expect(abs(noiseOut - (-16)) <= 0.5)

        let polish = VoiceStreamPolish()
        let rendered = polish.process(sine, sampleRate: rate)
        let primer = WarmupPrimer.sampleCount(sampleRate: rate)
        let speech = Array(rendered.dropFirst(primer))
        let polished = LoudnessNormalizer.measureIntegratedLUFS(speech, sampleRate: rate)
        #expect(abs(polished - (-16)) <= 0.5)
    }

    @Test func gainMovesOnlyPartwayTowardTheNextChunk() {
        let rate = 48_000.0
        let quiet = tone(count: 48_000, frequency: 200, amplitude: 0.05, sampleRate: rate, phase: 0)
        let loud = tone(count: 48_000, frequency: 200, amplitude: 0.25, sampleRate: rate, phase: 0)
        let target = LoudnessNormalizer.targetGain(for: loud, sampleRate: rate)
        var normalizer = LoudnessNormalizer()
        _ = normalizer.normalize(quiet, sampleRate: rate)
        let previous = normalizer.appliedGain
        _ = normalizer.normalize(loud, sampleRate: rate)
        let expected = previous + LoudnessNormalizer.smoothing * (target - previous)
        #expect(abs(normalizer.appliedGain - expected) < 1e-4)
        #expect(abs(normalizer.appliedGain - target) > abs(target - previous) * 0.5)
    }

    @Test func limiterHoldsTheTruePeakAtOrBelowMinusOne() {
        let probe: [Float] = [0, 0.5, 1, -1, 0.25, 0]
        #expect(abs(TruePeakLimiter.truePeak(probe) - 1.2442025609169483) < 1e-5)
        let rate = 48_000.0
        let sine = tone(count: 48_000, frequency: 200, amplitude: 0.25, sampleRate: rate, phase: 0)
        #expect(abs(TruePeakLimiter.truePeak(sine) - 0.250159141272278) < 1e-4)
        let hot = tone(count: 48_000, frequency: 200, amplitude: 0.99, sampleRate: rate, phase: 0)
        #expect(TruePeakLimiter.truePeakDBTP(hot, sampleRate: rate) > -1)
        let limited = TruePeakLimiter.limit(hot, sampleRate: rate)
        #expect(TruePeakLimiter.truePeakDBTP(limited, sampleRate: rate) <= -1)
        let hotNoise = lcgNoise(count: 4_800, peak: 1)
        #expect(TruePeakLimiter.truePeakDBTP(hotNoise, sampleRate: rate) > -1)
        let limitedNoise = TruePeakLimiter.limit(hotNoise, sampleRate: rate)
        #expect(TruePeakLimiter.truePeakDBTP(limitedNoise, sampleRate: rate) <= -1)
    }

    @Test func numberedListMarkerStaysWithTheSentence() {
        let english = SpeechClauseChunker.chunks(of: "1. The build is ready to ship this morning. The notes are in the log.")
        #expect(english.first?.hasPrefix("1. The build") == true)
        #expect(english.contains("1.") == false)
        let french = SpeechClauseChunker.chunks(of: "1. Le fichier est prêt pour la revue de ce matin. La suite reste une phrase.")
        #expect(french.first?.hasPrefix("1. Le fichier") == true)
        #expect(french.contains("1.") == false)
    }

    @Test func aTrailingPeriodAfterAURLEndsTheSentence() {
        let pieces = SpeechClauseChunker.chunks(of: "Read https://example.com/guide. The rest of this answer is its own sentence.")
        #expect(pieces.count == 2)
        #expect(pieces[0] == "Read https://example.com/guide.")
        #expect(pieces[1] == "The rest of this answer is its own sentence.")
    }

    @Test func frenchNarrowNoBreakSpaceBeforeAQuestionStillSplits() {
        let pieces = SpeechClauseChunker.chunks(of: "Est-ce que le correctif est prêt\u{00A0}? La suite arrive dans la phrase suivante.")
        #expect(pieces.count == 2)
        #expect(pieces[0].hasSuffix("?"))
        #expect(pieces[1].hasPrefix("La suite"))
    }

    @Test func shortBuffersDoNotClickAtTheJoin() {
        let left = [Float](repeating: 0.8, count: 20)
        let right = [Float](repeating: -0.8, count: 20)
        #expect(maxAdjacentStep(left + right) > 1)
        let joined = EqualPowerCrossfade.join(left, right, sampleRate: 24_000)
        #expect(maxAdjacentStep(joined) < 0.25)
    }

    @Test func cancelMidChunkStopsWithinOneBufferAndEmitsNoTail() {
        let polish = VoiceStreamPolish()
        let token = SpeechCancelToken()
        token.cancelAfterSamples = 500
        polish.begin(token)
        let input = [Float](repeating: 0.2, count: 4_000)
        let output = polish.process(input, sampleRate: 24_000)
        let primer = WarmupPrimer.sampleCount(sampleRate: 24_000)
        #expect(output.count == primer + 500)
        let tail = Array(output.suffix(16))
        let high = tail.max() ?? 0
        let low = tail.min() ?? 0
        #expect(high - low < 1e-3)
        #expect(polish.process([0.2, 0.2, 0.2], sampleRate: 24_000).isEmpty)
        #expect(polish.finish().isEmpty)

        let blocked = VoiceStreamPolish()
        let immediate = SpeechCancelToken()
        immediate.cancelAfterSamples = 0
        blocked.begin(immediate)
        #expect(blocked.process(input, sampleRate: 24_000).isEmpty)
        #expect(blocked.finish().isEmpty)
    }

    @Test func firstClauseIsScheduledBeforeTheFullRenderCompletes() {
        let text = longAnswer
        #expect(text.count == 709)
        let fullCost = 5.31
        var clock = SpeechManualClock()
        let output = VoiceStreamPolish()
        var scheduledAt: [Double] = []
        var scheduled: [[Float]] = []
        let receipt = ClauseSpeechScheduler.speak(
            text: text,
            sampleRate: 24_000,
            clock: &clock,
            output: output,
            synthesize: { chunk, clock in
                clock.advance(by: fullCost * Double(chunk.count) / Double(text.count))
                return [Float](repeating: 0.25, count: 2_400)
            },
            schedule: { samples, at in
                scheduled.append(samples)
                scheduledAt.append(at)
            })
        #expect(receipt.chunks.count >= 2)
        #expect((40...90).contains(receipt.chunks[0].count))
        #expect(receipt.firstScheduledAt < receipt.fullRenderCompletedAt)
        #expect(receipt.firstScheduledAt < ClauseSpeechBudget.proposedFirstClauseSeconds)
        #expect(scheduledAt.count == receipt.chunks.count)
        let firstOnly = fullCost * Double(receipt.chunks[0].count) / Double(text.count)
        #expect(abs(receipt.firstScheduledAt - firstOnly) < 0.001)
        let pause = Int((24_000 * ClauseSpeechScheduler.clausePauseSeconds).rounded())
        let tail = scheduled[0].suffix(pause)
        #expect(tail.allSatisfy { abs($0) < 1e-3 })
    }

    @Test func cancelDuringALaterClauseSchedulesNoFurtherBuffer() {
        let text = "The reply is spoken one sentence at a time. Each sentence is rendered by the engine that is ready, then handed to the player while the next sentence is still being prepared."
        var clock = SpeechManualClock()
        let token = SpeechCancelToken()
        var calls = 0
        let receipt = ClauseSpeechScheduler.speak(
            text: text,
            sampleRate: 24_000,
            clock: &clock,
            output: VoiceStreamPolish(),
            token: token,
            synthesize: { _, clock in
                calls += 1
                if calls > 1 {
                    token.cancel()
                    return [Float](repeating: 0.4, count: 400)
                }
                clock.advance(by: 0.4)
                return [Float](repeating: 0.2, count: 800)
            },
            schedule: { _, _ in })
        #expect(receipt.scheduled == 1)
        #expect(receipt.fullRenderCompletedAt == receipt.firstScheduledAt)
        #expect(calls == 2)
    }

    @Test func speakKokoroSchedulesTheFirstClauseInsideTheOneSecondBudget() {
        let text = longAnswer
        var clock = SpeechManualClock()
        let fullCost = 5.31
        var scheduledAt: [Double] = []
        let receipt = KokoroClausePlayback.speak(
            text: text,
            personaVoiceID: OriginalSyntheticVoice.id,
            sampleRate: 24_000,
            clock: &clock,
            output: VoiceStreamPolish(),
            synthesize: { chunk, clock in
                clock.advance(by: fullCost * Double(chunk.count) / Double(text.count))
                return kokoroCrestReply(sampleRate: 24_000)
            },
            schedule: { _, at in scheduledAt.append(at) })
        #expect(receipt.accepted)
        #expect(receipt.chunks.count >= 2)
        #expect((40...90).contains(receipt.chunks[0].count))
        let first = try #require(receipt.firstAudioAt)
        #expect(first < receipt.fullRenderCompletedAt)
        #expect(first < KokoroClausePlayback.firstAudioBudgetSeconds)
        #expect(first <= 1.0)
        #expect(scheduledAt.first == first)
        #expect(scheduledAt.count == receipt.chunks.count)
    }

    @Test func eachClauseAndTheJoinedStreamStayAtOrBelowMinusOneDBTP() {
        var clock = SpeechManualClock()
        let receipt = KokoroClausePlayback.speak(
            text: longAnswer,
            personaVoiceID: OriginalSyntheticVoice.id,
            sampleRate: 24_000,
            clock: &clock,
            output: VoiceStreamPolish(),
            synthesize: { _, _ in kokoroCrestReply(sampleRate: 24_000) },
            schedule: { _, _ in })
        #expect(receipt.scheduled.count >= 2)
        for clause in receipt.scheduled {
            #expect(TruePeakLimiter.truePeakDBTP(clause, sampleRate: 24_000) <= -1.0)
        }
        #expect(TruePeakLimiter.truePeakDBTP(receipt.joined, sampleRate: 24_000) <= -1.0)
    }

    @Test func theNormalizedFullReplyLandsNearMinusSeventeenPointEightLUFS() {
        let reply = kokoroCrestReply(sampleRate: 24_000)
        let shaped = KokoroClausePlayback.normalizedFullReply(reply, sampleRate: 24_000, output: VoiceStreamPolish())
        let lufs = LoudnessNormalizer.measureIntegratedLUFS(shaped, sampleRate: 24_000)
        #expect(abs(lufs - (-17.8)) <= 0.5)
        #expect(TruePeakLimiter.truePeakDBTP(shaped, sampleRate: 24_000) <= -1.0)
    }

    @Test func onlyTheOriginalSyntheticVoiceIsSpoken() {
        let refused = ["am_michael", "bm_george", "JARVIS (MCU)", "JARVIS MCU", "Paul Bettany", "Bettany", "preset-not-used", ""]
        for voiceID in refused {
            var clock = SpeechManualClock()
            var scheduled = 0
            let receipt = KokoroClausePlayback.speak(
                text: "The reply is spoken one sentence at a time. The next sentence waits.",
                personaVoiceID: voiceID,
                sampleRate: 24_000,
                clock: &clock,
                output: VoiceStreamPolish(),
                synthesize: { _, clock in
                    clock.advance(by: 2)
                    return [Float](repeating: 0.2, count: 800)
                },
                schedule: { _, _ in scheduled += 1 })
            #expect(!receipt.accepted, voiceID)
            #expect(receipt.scheduled.isEmpty, voiceID)
            #expect(scheduled == 0, voiceID)
            #expect(clock.seconds == 0, voiceID)
        }
        #expect(OriginalSyntheticVoice.accepts("zeus.synthetic"))
        #expect(!OriginalSyntheticVoice.accepts("am_michael"))
    }

    @Test func pipelineNamesEveryStageWithoutADefault() {
        #expect(VoiceStreamPolish.pipeline == [.clauseChunk, .loudness, .crossfade, .primer, .limiter])
        var seen: [String] = []
        for stage in VoiceStreamPolish.pipeline {
            seen.append(stageName(stage))
        }
        #expect(seen == ["clauseChunk", "loudness", "crossfade", "primer", "limiter"])
        let polish = VoiceStreamPolish()
        let text = "The build finished cleanly this morning. The notes are in the log."
        let left = tone(count: 2_000, frequency: 200, amplitude: 0.4, sampleRate: 24_000, phase: 0)
        let right = tone(count: 2_000, frequency: 200, amplitude: 0.4, sampleRate: 24_000, phase: 1)
        _ = polish.render(text: text, buffers: [left, right], sampleRate: 24_000)
        #expect(polish.lastTextChunks == SpeechClauseChunker.chunks(of: text))
        let step: any SpeechOutputProcessing = VoiceStreamPolish()
        #expect(!step.process([0.1, -0.1], sampleRate: 24_000).isEmpty)
    }
}

private let longAnswer = "The reply is spoken one sentence at a time. Each sentence is rendered by the engine that is ready, then handed to the player while the next sentence is still being prepared. A short pause sits between sentences so the line does not run together. If the preferred engine has no key, no model, or a recent failure, the next engine in the chain takes that sentence. The last engine is the system voice: it renders buffers, lowers the pitch, and slows the rate before the same player speaks them. This paragraph is synthetic fixture text for a voice harness. It names no person, no account, and no private recording. The numbers here are only a shape, such as section 4 and step 2, and they are not a measurement."

private func stageName(_ stage: SpeechPolishStage) -> String {
    switch stage {
    case .clauseChunk: "clauseChunk"
    case .loudness: "loudness"
    case .crossfade: "crossfade"
    case .primer: "primer"
    case .limiter: "limiter"
    }
}

/// Body 0.08 and a peak of 0.55 every 250 samples. pyloudnorm 0.1.1 on this shape,
/// after a gain to -16 LUFS and a -1 dBTP limit, is about -17.69 LUFS.
private func kokoroCrestReply(sampleRate: Double) -> [Float] {
    let count = Int(sampleRate) * 2
    var state: UInt32 = 0xC0FFEE
    var raw = [Double]()
    raw.reserveCapacity(count)
    var peak = 0.0
    for _ in 0..<count {
        state = 1664525 &* state &+ 1013904223
        let unit = (Double(state) / 4294967295.0) * 2 - 1
        raw.append(unit)
        peak = max(peak, abs(unit))
    }
    var samples = raw.map { Float($0 / peak * 0.08) }
    var index = 0
    var spike = 0
    while index < samples.count {
        samples[index] = spike % 2 == 0 ? 0.55 : -0.55
        spike += 1
        index += 250
    }
    return samples
}

private func tone(count: Int, frequency: Double, amplitude: Float, sampleRate: Double, phase: Double) -> [Float] {
    (0..<count).map { index in
        let angle = 2 * Double.pi * frequency * Double(index) / sampleRate + phase
        return Float(sin(angle) * Double(amplitude))
    }
}

private func lcgNoise(count: Int, peak target: Float = 0.2, seed: UInt32 = 0x5EED) -> [Float] {
    var state = seed
    var raw = [Double]()
    raw.reserveCapacity(count)
    var peak = 0.0
    for _ in 0..<count {
        state = 1664525 &* state &+ 1013904223
        let unit = (Double(state) / 4294967295.0) * 2.0 - 1.0
        raw.append(unit)
        peak = max(peak, abs(unit))
    }
    let scale = Double(target) / peak
    return raw.map { Float($0 * scale) }
}

private func maxAdjacentStep(_ samples: [Float]) -> Float {
    guard samples.count > 1 else { return 0 }
    var step: Float = 0
    for index in 1..<samples.count {
        step = max(step, abs(samples[index] - samples[index - 1]))
    }
    return step
}
