import Foundation
import Testing
import ZeusCore

/// Speaker identification (docs/SPEAKER-IDENTIFICATION.md): embeddings in the diarizer (S1), renaming and
/// merging (S3), the saved-voice library (S4), name suggestions (S5) and the post-meeting correction (S6).
/// All vectors are synthetic and no audio is involved.
@Suite("Scribe speaker identification")
struct ScribeSpeakerIdentificationTests {
    // MARK: Synthetic voices

    /// A voice that points along one axis of the 256-d space: any two different axes are unrelated (distance 1).
    private func axis(_ index: Int) -> [Float] {
        var vector = [Float](repeating: 0, count: ScribeVoiceEmbedding.wespeakerDimension)
        vector[index] = 1
        return vector
    }

    /// The same voice heard again: the base plus a little deterministic noise (cosine distance about 0.03).
    private func again(_ base: [Float], seed: UInt64, amount: Float = 0.05) -> [Float] {
        var state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return base.map { value in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = Float(state >> 40) / Float(1 << 24) - 0.5
            return value + noise * amount
        }
    }

    private func voice(_ vector: [Float]) -> ScribeVoiceEmbedding {
        ScribeVoiceEmbedding(kind: .wespeaker, vector: vector)
    }

    private let session = ScribeSessionID()

    private func segment(
        _ id: String, _ speaker: ScribeSpeaker, at start: TimeInterval = 0, for length: TimeInterval = 4, _ text: String = "words"
    ) -> ScribeTranscriptSegment {
        ScribeTranscriptSegment(
            id: id, session: session, speaker: speaker, start: start, end: start + length, text: text, isFinal: true
        )
    }

    private func turn(_ id: String, _ source: ScribeAudioSource, _ vector: [Float], seconds: TimeInterval = 4) -> ScribeTurnEmbedding {
        ScribeTurnEmbedding(segmentID: id, source: source, embedding: voice(vector), duration: seconds)
    }

    private let one = ScribeSpeaker.participant("Speaker 1")
    private let two = ScribeSpeaker.participant("Speaker 2")
    private let three = ScribeSpeaker.participant("Speaker 3")

    // MARK: S1 embeddings

    @Test func aTrainedEmbeddingMustBeTheRightSizeFiniteAndNotSilent() {
        #expect(ScribeVoiceEmbedding.wespeaker(axis(0)) != nil)
        #expect(ScribeVoiceEmbedding.wespeaker([1, 0, 0]) == nil)
        #expect(ScribeVoiceEmbedding.wespeaker([Float](repeating: 0, count: 256)) == nil)
        var broken = axis(0)
        broken[5] = .nan
        #expect(ScribeVoiceEmbedding.wespeaker(broken) == nil)
    }

    @Test func cosineDistanceSeparatesTheSameVoiceFromAnother() {
        let a = voice(axis(0))
        #expect(a.distance(to: a) < 1e-5)
        #expect(a.distance(to: voice(again(axis(0), seed: 1))) < 0.1)
        #expect(a.distance(to: voice(axis(1))) > 0.99)
        // Different kinds are never close, whatever the numbers.
        let handBuilt = ScribeVoiceEmbedding(kind: .handBuilt, vector: axis(0))
        #expect(a.distance(to: handBuilt) == 1)
    }

    @Test func twoCloseVoicesAndOneFarGiveTwoSpeakers() {
        var diarizer = ScribeDiarizer()
        let first = diarizer.assign(source: .system, embedding: voice(axis(0)))
        let firstAgain = diarizer.assign(source: .system, embedding: voice(again(axis(0), seed: 2)))
        let other = diarizer.assign(source: .system, embedding: voice(axis(1)))
        let otherAgain = diarizer.assign(source: .system, embedding: voice(again(axis(1), seed: 3)))
        #expect(first == one)
        #expect(firstAgain == first)
        #expect(other == two)
        #expect(otherAgain == other)
        #expect(diarizer.speakerCount == 2)
    }

    @Test func theFirstMicrophoneVoiceIsStillYouWithTrainedEmbeddings() {
        var diarizer = ScribeDiarizer()
        let me = diarizer.assign(source: .microphone, embedding: voice(axis(0)))
        let visitor = diarizer.assign(source: .microphone, embedding: voice(axis(1)))
        let meAgain = diarizer.assign(source: .microphone, embedding: voice(again(axis(0), seed: 4)))
        // The same voice on the other channel is another cluster.
        let remote = diarizer.assign(source: .system, embedding: voice(axis(0)))
        #expect(me == .you)
        #expect(visitor == one)
        #expect(meAgain == .you)
        #expect(remote == two)
    }

    @Test func aChunkWithoutAnEmbeddingContinuesThePreviousSpeaker() {
        var diarizer = ScribeDiarizer()
        let before = diarizer.assign(source: .system, embedding: nil)
        _ = diarizer.assign(source: .system, embedding: voice(axis(0)))
        let second = diarizer.assign(source: .system, embedding: voice(axis(1)))
        let after = diarizer.assign(source: .system, embedding: nil)
        let mic = diarizer.assign(source: .microphone, embedding: nil)
        #expect(before == one)
        #expect(after == second)
        #expect(mic == .you)
    }

    @Test func clustersOfDifferentKindsNeverCompare() {
        var diarizer = ScribeDiarizer()
        let trained = diarizer.assign(source: .system, embedding: voice(axis(0)))
        let handBuilt = diarizer.assign(source: .system, embedding: ScribeVoiceEmbedding(kind: .handBuilt, vector: axis(0)))
        #expect(trained != handBuilt)
        #expect(diarizer.classify(source: .system, embedding: voice(axis(0))) == trained)
    }

    @Test func atTheSpeakerCapANewVoiceJoinsTheNearestOfItsSource() {
        var diarizer = ScribeDiarizer(maxSpeakers: 2)
        _ = diarizer.assign(source: .system, embedding: voice(axis(0)))
        let second = diarizer.assign(source: .system, embedding: voice(axis(1)))
        let third = diarizer.assign(source: .system, embedding: voice(again(axis(1), seed: 5, amount: 0.9)))
        #expect(diarizer.speakerCount == 2)
        #expect(third == second || third == one)
    }

    @Test func classifyNeverLearns() {
        var diarizer = ScribeDiarizer()
        _ = diarizer.assign(source: .system, embedding: voice(axis(0)))
        #expect(diarizer.classify(source: .system, embedding: voice(axis(1))) == nil)
        #expect(diarizer.speakerCount == 1)
        #expect(diarizer.classify(source: .system, embedding: nil) == nil)
    }

    @Test func theHandBuiltPathIsUnchanged() {
        let samples = (0..<(ScribePCM.sampleRate * 2)).map { Float(sin(Double($0) * 0.05)) * 0.2 }
        var viaSamples = ScribeDiarizer()
        var viaEmbedding = ScribeDiarizer()
        let first = viaSamples.assign(source: .system, samples: samples)
        let second = viaEmbedding.assign(source: .system, embedding: .handBuilt(samples: samples))
        #expect(first == second)
        #expect(ScribeVoiceEmbedding.defaultThreshold(for: .handBuilt) == ScribeDiarizer.defaultThreshold)
        #expect(ScribeVoiceEmbedding.defaultThreshold(for: .wespeaker) == 0.5)
    }

    // MARK: S4 seeding

    @Test func aSeededVoiceTakesItsNameAndCountsOnlyOnceHeard() {
        var diarizer = ScribeDiarizer()
        diarizer.seed(name: "Marie Dubois", embedding: voice(axis(3)))
        #expect(diarizer.speakerCount == 0)
        #expect(diarizer.classify(source: .system, embedding: voice(again(axis(3), seed: 6))) == .participant("Marie Dubois"))
        let stranger = diarizer.assign(source: .system, embedding: voice(axis(4)))
        #expect(stranger == one)
        let marie = diarizer.assign(source: .system, embedding: voice(again(axis(3), seed: 7)))
        #expect(marie == .participant("Marie Dubois"))
        #expect(diarizer.speakerCount == 2)
        // She can be heard on the microphone too, and a seed never becomes "You".
        let onMicrophone = diarizer.assign(source: .microphone, embedding: voice(again(axis(3), seed: 8)))
        let someoneElse = diarizer.assign(source: .microphone, embedding: voice(axis(9)))
        #expect(onMicrophone == .participant("Marie Dubois"))
        #expect(someoneElse == .you)
    }

    @Test func aSeedBeyondThresholdIsIgnoredAndBlankNamesAreRefused() {
        var diarizer = ScribeDiarizer()
        diarizer.seed(name: "Paul", embedding: voice(axis(3)))
        diarizer.seed(name: "  ", embedding: voice(axis(5)))
        let heard = diarizer.assign(source: .system, embedding: voice(axis(5)))
        #expect(heard == one)
    }

    // MARK: S3 rename and merge

    private var meeting: [ScribeTranscriptSegment] {
        [
            segment("a", .you, at: 0, for: 5, "Welcome everyone"),
            segment("b", one, at: 5, for: 10, "Thanks for having me"),
            segment("c", two, at: 15, for: 5, "I can take that"),
            segment("d", one, at: 20, for: 5, "Agreed"),
        ]
    }

    @Test func renamingASpeakerRelabelsEveryLineAndTheStatistics() {
        let renamed = ScribeSpeakerNames.rename(one, to: "  Marie  ", in: meeting)
        #expect(renamed.map(\.speaker) == [.you, .participant("Marie"), two, .participant("Marie")])
        #expect(renamed.map(\.text) == meeting.map(\.text))
        let stats = ScribeSpeakerStats(segments: renamed)
        #expect(stats.speakers.map(\.speaker) == [.you, .participant("Marie"), two])
        #expect(stats.speakers[1].talkSeconds == 15)
        #expect(stats.speakers[1].segmentCount == 2)
    }

    @Test func theSameNameOnTwoSpeakersMerges() {
        let named = ScribeSpeakerNames.rename(one, to: "Marie", in: meeting)
        let merged = ScribeSpeakerNames.rename(two, to: "marie", in: named)
        #expect(merged.map(\.speaker) == [.you, .participant("Marie"), .participant("Marie"), .participant("Marie")])
        let stats = ScribeSpeakerStats(segments: merged)
        #expect(stats.speakers.count == 2)
        #expect(stats.speakers[1].talkSeconds == 20)
    }

    @Test func youCanMergeAStrayVoiceIntoYouButNeverRenameYou() {
        #expect(ScribeSpeakerNames.rename(.you, to: "Tony", in: meeting) == meeting)
        let merged = ScribeSpeakerNames.rename(two, to: "you", in: meeting)
        #expect(merged[2].speaker == .you)
    }

    @Test func aBlankOrUnchangedNameChangesNothing() {
        #expect(ScribeSpeakerNames.rename(one, to: "   ", in: meeting) == meeting)
        #expect(ScribeSpeakerNames.rename(one, to: "Speaker 1", in: meeting) == meeting)
    }

    @Test func aFinishedTranscriptCanBeRelabelledButNotRewritten() {
        var transcript = ScribeTranscript(session: session)
        for item in meeting { transcript.upsert(item) }
        transcript.finalize()
        transcript.relabelSpeakers { $0.speaker == one ? .participant("Marie") : $0.speaker }
        #expect(transcript.finalSegments.map(\.speaker.displayName) == ["You", "Marie", "Speaker 2", "Marie"])
        #expect(transcript.upsert(segment("z", one)) == .rejectedFinalized)
    }

    @Test func theExportsCarryTheNames() {
        let renamed = ScribeSpeakerNames.rename(one, to: "Marie", in: meeting)
        let markdown = ScribeTranscriptExport.markdown(title: "Roadmap", segments: renamed)
        #expect(markdown.hasPrefix("# Roadmap\n"))
        #expect(markdown.contains("**Marie** (0:05)\nThanks for having me"))
        #expect(markdown.contains("**You** (0:00)\nWelcome everyone"))
        #expect(!markdown.contains("Speaker 1"))
        #expect(!markdown.contains("\u{2014}"))
        let plain = ScribeTranscriptExport.plainText(segments: renamed)
        #expect(plain.hasPrefix("You: Welcome everyone\nMarie: Thanks for having me"))
    }

    @Test func provisionalAndEmptySegmentsAreNotExported() {
        var provisional = segment("p", one, at: 30, "still talking")
        provisional.isFinal = false
        let empty = segment("e", one, at: 31, "   ")
        let text = ScribeTranscriptExport.plainText(segments: meeting + [provisional, empty])
        #expect(!text.contains("still talking"))
        #expect(text.split(separator: "\n").count == 4)
    }

    @Test func attendeeNamesAreDisplayNamesOnly() {
        let cleaned = ScribeAttendeeNames.clean(["Marie Dubois", "marie@example.com", " ", "Paul Martin", "marie dubois", "mailto:x@y.z"])
        #expect(cleaned == ["Marie Dubois", "Paul Martin"])
        let slot = ScribeCalendarSlot(id: "x", title: "Review", start: Date(), attendeeNames: ["Ana", "ana@corp.test"])
        #expect(slot.attendeeNames == ["Ana"])
        #expect(ScribeCalendarSlot(id: "y", title: "Solo", start: Date()).attendeeNames.isEmpty)
    }

    // MARK: S4 library

    @Test func aVoiceIsSavedMatchedAndDeleted() throws {
        var library = ScribeVoiceLibrary()
        let savedResult = library.remember(name: "Marie", embedding: voice(axis(0)), sampleCount: 5)
        let saved = try #require(savedResult)
        #expect(library.match(voice(again(axis(0), seed: 1)))?.id == saved.id)
        #expect(library.match(voice(axis(1))) == nil)
        // A voice of another kind never matches.
        #expect(library.match(ScribeVoiceEmbedding(kind: .handBuilt, vector: axis(0))) == nil)
        library.delete(id: saved.id)
        #expect(library.isEmpty)
        #expect(library.match(voice(axis(0))) == nil)
    }

    @Test func rememberingTheSameNameFoldsIntoOneVoice() throws {
        var library = ScribeVoiceLibrary()
        library.remember(name: "Marie", embedding: voice(axis(0)), sampleCount: 3)
        let foldedResult = library.remember(name: " MARIE ", embedding: voice(again(axis(0), seed: 2)), sampleCount: 2)
        let folded = try #require(foldedResult)
        #expect(library.voices.count == 1)
        #expect(folded.sampleCount == 5)
        library.remember(name: "Paul", embedding: voice(axis(1)), sampleCount: 1)
        #expect(library.voices.count == 2)
        #expect(library.names == ["Marie", "Paul"])
    }

    @Test func blankNamesEmptyEmbeddingsAndZeroSamplesAreRefused() {
        var library = ScribeVoiceLibrary()
        #expect(library.remember(name: " ", embedding: voice(axis(0)), sampleCount: 1) == nil)
        #expect(library.remember(name: "A", embedding: ScribeVoiceEmbedding(kind: .wespeaker, vector: []), sampleCount: 1) == nil)
        #expect(library.remember(name: "A", embedding: voice(axis(0)), sampleCount: 0) == nil)
        #expect(library.isEmpty)
    }

    @Test func theSampleCountIsCapped() throws {
        var library = ScribeVoiceLibrary()
        let savedResult = library.remember(name: "Marie", embedding: voice(axis(0)), sampleCount: 500)
        let saved = try #require(savedResult)
        #expect(saved.sampleCount == ScribeVoiceLibrary.sampleCap)
    }

    @Test func seedsAreTheVoicesOfOneKind() {
        var library = ScribeVoiceLibrary()
        library.remember(name: "Marie", embedding: voice(axis(0)), sampleCount: 1)
        library.remember(name: "Old", embedding: ScribeVoiceEmbedding(kind: .handBuilt, vector: axis(2)), sampleCount: 1)
        #expect(library.seeds(kind: .wespeaker).map(\.name) == ["Marie"])
        #expect(library.seeds(kind: .handBuilt).map(\.name) == ["Old"])
    }

    private func temporaryStore() -> ScribeVoiceLibraryStore {
        ScribeVoiceLibraryStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-voices-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func theLibraryRoundTripsThroughAPrivateFileAndDeletingTheLastVoiceRemovesIt() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(try store.load().isEmpty)
        var library = ScribeVoiceLibrary()
        let marieResult = library.remember(name: "Marie", embedding: voice(axis(0)), sampleCount: 4)
        let marie = try #require(marieResult)
        library.remember(name: "Paul", embedding: voice(axis(1)), sampleCount: 2)
        try store.save(library)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let loaded = try store.load()
        #expect(loaded.voices.map(\.name) == ["Marie", "Paul"])
        #expect(loaded.match(voice(axis(0)))?.id == marie.id)

        var after = loaded
        after.delete(id: marie.id)
        try store.save(after)
        #expect(try store.load().names == ["Paul"])
        after.deleteAll()
        try store.save(after)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(try store.load().isEmpty)
    }

    @Test func anUnreadableFileIsAnErrorNotAnEmptyLibrary() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(throws: ScribeVoiceLibraryStoreError.self) { try store.load() }
    }

    @Test func savedVoicesLiveUnderApplicationSupportNeverInAVault() {
        let directory = ScribeVoiceLibraryStore.standard.directory
        #expect(directory.path.hasPrefix(ZeusPaths.supportDirectory.path))
        #expect(directory.lastPathComponent == "Voices")
        #expect(!directory.path.localizedCaseInsensitiveContains("Second Brain"))
    }

    // MARK: S5 suggestions

    private func talk(_ lines: [(ScribeSpeaker, String)]) -> [ScribeTranscriptSegment] {
        lines.enumerated().map { index, line in segment("s\(index)", line.0, at: Double(index) * 5, line.1) }
    }

    @Test func aSelfIntroductionMatchingAnAttendeeIsSuggestedWithTheFullName() {
        let segments = talk([(.you, "Welcome everyone"), (one, "Hi, I'm Marie, glad to be here")])
        let result = ScribeNameSuggester.suggestions(segments: segments, attendees: ["Marie Dubois", "Paul Martin"])
        #expect(result.map(\.speaker) == [one])
        #expect(result.first?.name == "Marie Dubois")
        #expect(result.first?.evidence == .introduction)
    }

    @Test func directAddressNamesTheNextSpeaker() {
        let segments = talk([(.you, "Thanks, Paul, over to you"), (one, "Sure, here is the plan")])
        let result = ScribeNameSuggester.suggestions(segments: segments, attendees: ["Paul Martin"])
        #expect(result.map(\.speaker) == [one])
        #expect(result.first?.name == "Paul Martin")
        #expect(result.first?.evidence == .address)
    }

    @Test func aSavedVoiceNameVouchesForAMention() {
        let segments = talk([(one, "This is Paul from finance")])
        let result = ScribeNameSuggester.suggestions(segments: segments, savedNames: ["Paul Martin"])
        #expect(result.first?.name == "Paul Martin")
    }

    @Test func oneStrayMentionWithNoAttendeeBehindItGivesNothing() {
        let segments = talk([(one, "I'm Marie"), (two, "Okay")])
        #expect(ScribeNameSuggester.suggestions(segments: segments, attendees: ["Paul Martin"]).isEmpty)
        #expect(ScribeNameSuggester.suggestions(segments: segments).isEmpty)
    }

    @Test func aNameSaidTwiceIsKeptWithoutAnInvite() {
        let segments = talk([(one, "Hi, I'm Marie"), (two, "Welcome"), (one, "Marie here again, quick update")])
        let result = ScribeNameSuggester.suggestions(segments: segments)
        #expect(result.map(\.name) == ["Marie"])
    }

    @Test func wordsThatAreNotNamesAreNeverSuggested() {
        let segments = talk([(one, "I'm Sorry"), (one, "I'm Sorry again"), (one, "this is Monday")])
        #expect(ScribeNameSuggester.suggestions(segments: segments, attendees: ["Sorry Person"]).isEmpty)
    }

    @Test func theOwnersNameIsNeverSuggestedForAnotherVoice() {
        let segments = talk([(.you, "Thanks, Tony"), (one, "Sure")])
        #expect(ScribeNameSuggester.suggestions(segments: segments, attendees: ["Tony Stark"], ownerName: "Tony Stark").isEmpty)
        #expect(!ScribeNameSuggester.suggestions(segments: segments, attendees: ["Tony Stark"]).isEmpty)
    }

    @Test func youAndAlreadyNamedSpeakersGetNoSuggestion() {
        let segments = talk([(.you, "I'm Tony"), (.participant("Marie"), "I'm Paul"), (.you, "Thanks, Paul")])
        #expect(ScribeNameSuggester.suggestions(segments: segments, attendees: ["Tony Stark", "Paul Martin"]).isEmpty)
    }

    @Test func oneNamePerSpeakerAndOneSpeakerPerName() {
        let segments = talk([
            (one, "I'm Marie"), (two, "Thanks, Marie"), (one, "Welcome"),
        ])
        let result = ScribeNameSuggester.suggestions(segments: segments, attendees: ["Marie Dubois"])
        // Speaker 1 introduced herself and was thanked by name: one suggestion, for her, not repeated for Speaker 2.
        #expect(result.count == 1)
        #expect(result.first?.speaker == one)
    }

    // MARK: S6 correction

    @Test func aLiveSplitMergesBackAndADistinctVoiceStays() {
        // Live pass split one voice into Speaker 1 and Speaker 2 and heard another as Speaker 3.
        let segments = [segment("a", one, at: 0), segment("b", two, at: 5, for: 2), segment("c", three, at: 10), segment("d", one, at: 15)]
        let turns = [
            turn("a", .system, axis(0)), turn("b", .system, again(axis(0), seed: 1), seconds: 2),
            turn("c", .system, axis(1)), turn("d", .system, again(axis(0), seed: 2)),
        ]
        let fixed = ScribeSpeakerCorrection.corrected(segments: segments, turns: turns)
        #expect(fixed.map(\.speaker) == [one, one, three, one])
        #expect(fixed.map(\.text) == segments.map(\.text))
    }

    @Test func clearlyDifferentVoicesKeepTheirLabels() {
        let segments = [segment("a", one, at: 0), segment("b", two, at: 5), segment("c", one, at: 10)]
        let turns = [turn("a", .system, axis(0)), turn("b", .system, axis(1)), turn("c", .system, again(axis(0), seed: 3))]
        #expect(ScribeSpeakerCorrection.corrected(segments: segments, turns: turns) == segments)
    }

    @Test func twoVoicesTheLivePassMergedAreSplitIntoANewSpeaker() {
        let segments = [segment("a", one, at: 0, for: 8), segment("b", one, at: 8, for: 3), segment("c", one, at: 11, for: 8)]
        let turns = [turn("a", .system, axis(0), seconds: 8), turn("b", .system, axis(1), seconds: 3), turn("c", .system, again(axis(0), seed: 4), seconds: 8)]
        let fixed = ScribeSpeakerCorrection.corrected(segments: segments, turns: turns)
        #expect(fixed.map(\.speaker) == [one, two, one])
    }

    @Test func theMicrophoneAndTheSystemAudioNeverMerge() {
        let segments = [segment("a", .you, at: 0), segment("b", one, at: 5)]
        let turns = [turn("a", .microphone, axis(0)), turn("b", .system, axis(0))]
        #expect(ScribeSpeakerCorrection.corrected(segments: segments, turns: turns) == segments)
    }

    @Test func aMicrophoneVoiceSplitFromYouMergesBackIntoYou() {
        let segments = [segment("a", .you, at: 0, for: 8), segment("b", one, at: 8, for: 2), segment("c", .you, at: 10, for: 8)]
        let turns = [
            turn("a", .microphone, axis(0), seconds: 8), turn("b", .microphone, again(axis(0), seed: 5), seconds: 2),
            turn("c", .microphone, again(axis(0), seed: 6), seconds: 8),
        ]
        #expect(ScribeSpeakerCorrection.corrected(segments: segments, turns: turns).map(\.speaker) == [.you, .you, .you])
    }

    @Test func aLineWithoutAVoiceFollowsItsSpeaker() {
        // "b" was heard as Speaker 2 but its voice is Speaker 1's; the unembedded "c" of Speaker 2 follows it.
        let segments = [segment("a", one, at: 0), segment("b", two, at: 5, for: 2), segment("c", two, at: 8, for: 2)]
        let turns = [turn("a", .system, axis(0)), turn("b", .system, again(axis(0), seed: 7), seconds: 2)]
        #expect(ScribeSpeakerCorrection.corrected(segments: segments, turns: turns).map(\.speaker) == [one, one, one])
    }

    @Test func tooFewOrTooManyTurnsLeaveTheLiveLabels() {
        let single = [segment("a", one)]
        #expect(ScribeSpeakerCorrection.corrected(segments: single, turns: [turn("a", .system, axis(0))]) == single)
        #expect(ScribeSpeakerCorrection.corrected(segments: meeting, turns: []) == meeting)

        let many = (0...ScribeSpeakerCorrection.maxTurns).map { segment("m\($0)", one, at: Double($0)) }
        let turns = many.map { turn($0.id, .system, axis(0)) }
        #expect(ScribeSpeakerCorrection.corrected(segments: many, turns: turns) == many)
    }

    @Test func averageLinkageGroupsByMeanDistance() {
        let items = [axis(0), again(axis(0), seed: 1), axis(1), again(axis(1), seed: 2), axis(2)].map(voice)
        let clusters = ScribeSpeakerCorrection.averageLinkage(indices: Array(items.indices), limit: 0.5) { items[$0] }
        #expect(clusters.sorted { $0[0] < $1[0] } == [[0, 1], [2, 3], [4]])
    }

    @Test func centroidWeighsLongerTurnsMore() throws {
        let long = voice(axis(0))
        let short = voice(axis(1))
        let mean = try #require(ScribeEmbeddingMath.centroid(of: [(long, 9), (short, 1)]))
        #expect(mean.vector[0] > mean.vector[1] * 5)
        #expect(ScribeEmbeddingMath.centroid(of: []) == nil)
        #expect(ScribeEmbeddingMath.centroid(of: [(long, 1), (ScribeVoiceEmbedding(kind: .handBuilt, vector: axis(0)), 1)]) == nil)
    }
}
