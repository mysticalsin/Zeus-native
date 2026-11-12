import Foundation
import Testing
import ZeusCore

/// Speaker parity slices S8 and the naming UX (docs/SPEAKER-IDENTIFICATION.md): call-window labels and tiles,
/// spans, votes and the binding gate, the name book, retroactive live naming, block and word reassignment,
/// undo, pruning and the voice sample clip. All timelines are synthetic; no window, audio or Accessibility is read.
@Suite("Scribe speaker parity")
struct ScribeSpeakerParityTests {
    private let session = ScribeSessionID()

    // MARK: Helpers

    private func segment(
        _ id: String, _ speaker: ScribeSpeaker, at start: TimeInterval, for length: TimeInterval = 4, _ text: String = "some words here"
    ) -> ScribeTranscriptSegment {
        ScribeTranscriptSegment(id: id, session: session, speaker: speaker, start: start, end: start + length, text: text, isFinal: true)
    }

    private func speaker(_ number: Int) -> ScribeSpeaker { .participant("Speaker \(number)") }

    /// A poll every half second; `lit` lists (name, from, to) ranges in which that tile is the active speaker.
    private func timeline(
        roster: [String], lit: [(String, TimeInterval, TimeInterval)], upTo end: TimeInterval,
        muted: Set<String> = [], ambiguous: Bool = false, app: MeetingAppKind = .teams
    ) -> [MeetingSpeakerObservation] {
        var result: [MeetingSpeakerObservation] = []
        var time = 0.0
        while time <= end {
            let tiles = roster.map { name -> MeetingParticipantState in
                let isLit = lit.contains { $0.0 == name && time >= $0.1 && time <= $0.2 }
                return MeetingParticipantState(name: name, isSpeaking: isLit, isMuted: muted.contains(name))
            }
            result.append(MeetingSpeakerObservation(time: time, app: app, participants: tiles, isAmbiguous: ambiguous))
            time += 0.5
        }
        return result
    }

    private func turn(_ cluster: String, _ start: TimeInterval, _ end: TimeInterval) -> MeetingClusterTurn {
        MeetingClusterTurn(cluster: cluster, start: start, end: end)
    }

    // MARK: Label parsing

    @Test func parserStripsEnglishAndFrenchSuffixes() {
        #expect(MeetingSpeakerLabelParser.parse("Marie Dubois (Guest)")?.name == "Marie Dubois")
        #expect(MeetingSpeakerLabelParser.parse("Paul Martin (External)")?.name == "Paul Martin")
        #expect(MeetingSpeakerLabelParser.parse("Tony (You)")?.name == "Tony")
        #expect(MeetingSpeakerLabelParser.parse("Tony (You)")?.isSelf == true)
        #expect(MeetingSpeakerLabelParser.parse("Chloé Bernard (Invitée)")?.name == "Chloé Bernard")
        #expect(MeetingSpeakerLabelParser.parse("Luc Petit (Externe)")?.name == "Luc Petit")
        #expect(MeetingSpeakerLabelParser.parse("Tony Walteur (Vous)")?.isSelf == true)
        #expect(MeetingSpeakerLabelParser.parse("Sam (Invité)")?.name == "Sam")
    }

    @Test func parserReadsSpeakingAndMutedSignalsInBothLanguages() throws {
        let english = try #require(MeetingSpeakerLabelParser.parse("Marie Dubois is speaking"))
        #expect(english.name == "Marie Dubois")
        #expect(english.isSpeaking)
        let active = try #require(MeetingSpeakerLabelParser.parse("Sam, active speaker"))
        #expect(active.name == "Sam")
        #expect(active.isSpeaking)
        let muted = try #require(MeetingSpeakerLabelParser.parse("Paul, muted"))
        #expect(muted.name == "Paul")
        #expect(muted.isMuted)
        #expect(!muted.isSpeaking)
        let french = try #require(MeetingSpeakerLabelParser.parse("Chloé Bernard est en train de parler"))
        #expect(french.name == "Chloé Bernard")
        #expect(french.isSpeaking)
        let parle = try #require(MeetingSpeakerLabelParser.parse("Luc parle"))
        #expect(parle.name == "Luc")
        #expect(parle.isSpeaking)
        let coupe = try #require(MeetingSpeakerLabelParser.parse("Amélie (Invitée), micro coupé"))
        #expect(coupe.name == "Amélie")
        #expect(coupe.isMuted)
        let sourdine = try #require(MeetingSpeakerLabelParser.parse("Hugo, en sourdine"))
        #expect(sourdine.name == "Hugo")
        #expect(sourdine.isMuted)
    }

    @Test func unmutedIsNotMutedAndAMutedTileNeverCountsAsSpeaking() throws {
        let unmuted = try #require(MeetingSpeakerLabelParser.parse("Paul, unmuted"))
        #expect(!unmuted.isMuted)
        let both = try #require(MeetingSpeakerLabelParser.parse("Paul is speaking, muted"))
        #expect(both.state.isMuted)
        #expect(!both.state.isSpeaking)
    }

    @Test func parserRejectsWindowControlsAndEmptyNames() {
        #expect(MeetingSpeakerLabelParser.parse("Mute") == nil)
        #expect(MeetingSpeakerLabelParser.parse("Participants") == nil)
        #expect(MeetingSpeakerLabelParser.parse("Partager l'écran") == nil)
        #expect(MeetingSpeakerLabelParser.parse("(Guest)") == nil)
        #expect(MeetingSpeakerLabelParser.parse("   ") == nil)
        #expect(MeetingSpeakerLabelParser.parse("12345") == nil)
    }

    // MARK: Spans

    @Test func pollsFoldIntoSpansAndAGapClosesOne() {
        let lit = timeline(roster: ["Marie", "Paul"], lit: [("Marie", 0, 3), ("Marie", 6, 8)], upTo: 10)
        let spans = MeetingSpeakerSpans.fold(lit)
        #expect(spans.count == 2)
        #expect(spans.allSatisfy { $0.name == "Marie" })
        #expect(spans[0].start < 0.1 && spans[0].end > 3)
        #expect(spans[1].start > 5.5)
    }

    @Test func mutedSelfAndAmbiguousPollsNeverLight() {
        let mutedPolls = timeline(roster: ["Marie", "Paul"], lit: [("Marie", 0, 5)], upTo: 6, muted: ["Marie"])
        #expect(MeetingSpeakerSpans.fold(mutedPolls).isEmpty)
        var selfPolls = timeline(roster: ["Marie", "Tony"], lit: [("Tony", 0, 5)], upTo: 6)
        selfPolls = selfPolls.map { observation in
            var changed = observation
            changed.participants = observation.participants.map { tile in
                var copy = tile
                copy.isSelf = tile.name == "Tony"
                return copy
            }
            return changed
        }
        #expect(MeetingSpeakerSpans.fold(selfPolls).isEmpty)
        let ambiguous = timeline(roster: ["Marie", "Paul"], lit: [("Marie", 0, 5)], upTo: 6, ambiguous: true)
        #expect(MeetingSpeakerSpans.fold(ambiguous).isEmpty)
    }

    // MARK: Binding

    @Test func audioAndTileThatAgreeBindTwoNames() {
        let observations = timeline(roster: ["Marie Dubois", "Paul Martin"], lit: [("Marie Dubois", 0, 10), ("Paul Martin", 12, 22)], upTo: 24)
        let turns = [turn("Speaker 1", 0, 10), turn("Speaker 2", 12, 22)]
        let found = MeetingSpeakerBinder().bindings(observations: observations, turns: turns)
        #expect(found.count == 2)
        #expect(found.first { $0.cluster == "Speaker 1" }?.name == "Marie Dubois")
        #expect(found.first { $0.cluster == "Speaker 2" }?.name == "Paul Martin")
        #expect(found.allSatisfy { $0.confidence > 0.8 })
    }

    @Test func tooLittleOverlapWithholdsTheName() {
        let observations = timeline(roster: ["Marie", "Paul"], lit: [("Marie", 1, 3)], upTo: 12)
        let found = MeetingSpeakerBinder().bindings(observations: observations, turns: [turn("Speaker 1", 0, 10)])
        #expect(found.isEmpty)
    }

    @Test func aCloseRunnerUpWithholdsTheName() {
        let observations = timeline(roster: ["Marie", "Paul"], lit: [("Marie", 0, 6), ("Paul", 4, 10)], upTo: 12)
        let found = MeetingSpeakerBinder().bindings(observations: observations, turns: [turn("Speaker 1", 0, 10)])
        #expect(found.isEmpty)
    }

    @Test func anAmbiguousWindowWithholdsEveryName() {
        let observations = timeline(roster: ["Marie", "Paul"], lit: [("Marie", 0, 10)], upTo: 12, ambiguous: true)
        #expect(MeetingSpeakerBinder().bindings(observations: observations, turns: [turn("Speaker 1", 0, 10)]).isEmpty)
    }

    @Test func aSoloRosterNamesNobody() {
        let observations = timeline(roster: ["Marie"], lit: [("Marie", 0, 10)], upTo: 12)
        #expect(MeetingSpeakerBinder().bindings(observations: observations, turns: [turn("Speaker 1", 0, 10)]).isEmpty)
    }

    @Test func oneNameNeverLandsOnTwoVoices() {
        let observations = timeline(roster: ["Marie", "Paul"], lit: [("Marie", 0, 10), ("Marie", 12, 22)], upTo: 24)
        let turns = [turn("Speaker 1", 0, 10), turn("Speaker 2", 12, 22)]
        let found = MeetingSpeakerBinder().bindings(observations: observations, turns: turns)
        #expect(found.count == 1)
        #expect(found.first?.cluster == "Speaker 1")
    }

    @Test func aMutedTileNeverWinsTheVote() {
        let observations = timeline(roster: ["Marie", "Paul"], lit: [("Marie", 0, 10)], upTo: 12, muted: ["Marie"])
        #expect(MeetingSpeakerBinder().bindings(observations: observations, turns: [turn("Speaker 1", 0, 10)]).isEmpty)
    }

    @Test func aNameAlreadyTakenIsNotBoundAgain() {
        let observations = timeline(roster: ["Marie", "Paul"], lit: [("Marie", 0, 10)], upTo: 12)
        let taken: Set<String> = [ScribeSpeakerNames.key("Marie")]
        #expect(MeetingSpeakerBinder().bindings(observations: observations, turns: [turn("Speaker 1", 0, 10)], excluding: taken).isEmpty)
    }

    // MARK: The name book

    @Test func aTypedNameAlwaysWinsOverAutomaticEvidence() {
        var book = ScribeSpeakerBook()
        book.setConfirmed(label: "Speaker 1", name: "Marie")
        let result = book.bindAutomatic(label: "Speaker 1", name: "Someone Else", source: .callWindow, confidence: 0.99)
        #expect(result == .keptManual)
        #expect(book.identity(forOriginal: "Speaker 1")?.name == "Marie")
        #expect(book.identity(forOriginal: "Speaker 1")?.source == .manual)
    }

    @Test func aDeclinedNameIsNotOfferedAgainForThatVoice() {
        var book = ScribeSpeakerBook()
        book.bindAutomatic(label: "Speaker 2", name: "Paul Martin", source: .callWindow, confidence: 0.9)
        let label = book.decline(name: "Paul Martin")
        #expect(label == "Speaker 2")
        #expect(book.identity(forOriginal: "Speaker 2") == nil)
        let again = book.bindAutomatic(label: "Speaker 2", name: "paul martin", source: .callWindow, confidence: 0.95)
        #expect(again == .declined)
        #expect(book.identity(forOriginal: "Speaker 2") == nil)
    }

    @Test func laterEvidenceCorrectsAnAutomaticNameOnlyWhenClearlyStronger() {
        var book = ScribeSpeakerBook()
        book.bindAutomatic(label: "Speaker 1", name: "Marie", source: .introduction, confidence: 0.5)
        #expect(book.bindAutomatic(label: "Speaker 1", name: "Maria", source: .introduction, confidence: 0.55) == .weaker)
        #expect(book.identity(forOriginal: "Speaker 1")?.name == "Marie")
        #expect(book.bindAutomatic(label: "Speaker 1", name: "Marie Dubois", source: .callWindow, confidence: 0.9) == .bound)
        #expect(book.identity(forOriginal: "Speaker 1")?.name == "Marie Dubois")
        #expect(book.identity(forOriginal: "Speaker 1")?.source == .callWindow)
    }

    @Test func anAcceptedSuggestionIsConfirmedAndKeepsItsSource() {
        var book = ScribeSpeakerBook()
        book.setConfirmed(label: "Speaker 3", name: "Luc Petit", source: .calendar, confidence: 0.7)
        let identity = book.identity(forOriginal: "Speaker 3")
        #expect(identity?.source == .calendar)
        #expect(identity?.confirmed == true)
        #expect(book.bindAutomatic(label: "Speaker 3", name: "Other", source: .callWindow, confidence: 1) == .keptManual)
    }

    @Test func aLowConfidenceAutomaticNameNeedsConfirmation() {
        var book = ScribeSpeakerBook()
        book.bindAutomatic(label: "Speaker 1", name: "Marie", source: .callWindow, confidence: 0.6)
        #expect(book.identity(forOriginal: "Speaker 1")?.needsConfirmation == true)
        book.setConfirmed(label: "Speaker 1", name: "Marie")
        #expect(book.identity(forOriginal: "Speaker 1")?.needsConfirmation == false)
    }

    @Test func theBookRoundTripsThroughAMeetingRecordAndOlderFilesStillLoad() throws {
        var book = ScribeSpeakerBook()
        book.bindAutomatic(label: "Speaker 1", name: "Marie Dubois", source: .callWindow, confidence: 0.9)
        book.setConfirmed(label: "Speaker 2", name: "Paul")
        _ = book.decline(name: "Paul")
        book.recordFolds([ScribeSpeakerFold(segmentID: "sys-3", from: ScribeSpeakerRecordLabel(speaker(4)), into: ScribeSpeakerRecordLabel(speaker(1)))])
        let lines = [segment("sys-0", .participant("Marie Dubois"), at: 0)]
        let withBook = ScribeMeetingRecord(
            id: UUID(), title: "Sync", endedAt: Date(timeIntervalSince1970: 1_000), duration: 60,
            notes: ScribeMeetingNotes(), transcript: lines, speakerBook: book
        )
        let data = try JSONEncoder().encode(withBook)
        let back = try JSONDecoder().decode(ScribeMeetingRecord.self, from: data)
        #expect(back.speakerBook == book)
        let without = ScribeMeetingRecord(
            id: UUID(), title: "Old", endedAt: Date(timeIntervalSince1970: 1_000), duration: 60,
            notes: ScribeMeetingNotes(), transcript: lines
        )
        let oldBack = try JSONDecoder().decode(ScribeMeetingRecord.self, from: JSONEncoder().encode(without))
        #expect(oldBack.speakerBook == nil)
    }

    // MARK: Live naming

    @Test func aNameThatBindsRelabelsEarlierLinesAndLaterOnes() {
        var live = ScribeLiveNaming()
        let first = live.ingest(segment("sys-0", speaker(1), at: 0, for: 10))
        _ = live.ingest(segment("sys-1", speaker(2), at: 12, for: 10))
        #expect(first.speaker == speaker(1))
        for observation in timeline(roster: ["Marie Dubois", "Paul Martin"], lit: [("Marie Dubois", 0, 10), ("Paul Martin", 12, 22)], upTo: 24) {
            live.observe(observation)
        }
        let changed = live.evaluate()
        #expect(changed.count == 2)
        #expect(live.displayed(speaker(1), segmentID: "sys-0") == .participant("Marie Dubois"))
        let later = live.ingest(segment("sys-2", speaker(1), at: 30, for: 3))
        #expect(later.speaker == .participant("Marie Dubois"))
        #expect(live.evaluate().isEmpty)
    }

    @Test func theMicrophoneChannelIsAlwaysYouAndNeverBound() {
        var live = ScribeLiveNaming()
        let mic = live.ingest(segment("mic-0", .you, at: 0, for: 10))
        #expect(mic.speaker == .you)
        let room = live.ingest(segment("mic-1", speaker(5), at: 12, for: 10))
        #expect(room.speaker == speaker(5))
        for observation in timeline(roster: ["Marie", "Paul"], lit: [("Marie", 12, 22)], upTo: 24) { live.observe(observation) }
        #expect(live.evaluate().isEmpty)
        #expect(live.nowSpeaking(mic)?.displayName == "You")
    }

    @Test func nowSpeakingUsesTheBestNameAndAPlaceholderUntilOneBinds() {
        var live = ScribeLiveNaming()
        let line = live.ingest(segment("sys-0", speaker(1), at: 0, for: 10))
        let before = live.nowSpeaking(line)
        #expect(before?.displayName == ScribeLiveNaming.identifying)
        #expect(before?.isResolved == false)
        for observation in timeline(roster: ["Marie Dubois", "Paul"], lit: [("Marie Dubois", 0, 10)], upTo: 12) { live.observe(observation) }
        _ = live.evaluate()
        let after = live.nowSpeaking(line)
        #expect(after?.displayName == "Marie Dubois")
        #expect(after?.isResolved == true)
        #expect(after?.source == .callWindow)
        #expect(live.nowSpeaking(nil) == nil)
    }

    @Test func aTypedNameDuringTheCallIsNeverOverwrittenByTheWindow() {
        var live = ScribeLiveNaming()
        _ = live.ingest(segment("sys-0", speaker(1), at: 0, for: 10))
        live.setManual(label: "Speaker 1", name: "Marie typed")
        for observation in timeline(roster: ["Marie Dubois", "Paul"], lit: [("Marie Dubois", 0, 10)], upTo: 12) { live.observe(observation) }
        _ = live.evaluate()
        #expect(live.displayed(speaker(1), segmentID: "sys-0") == .participant("Marie typed"))
    }

    // MARK: Window tiles

    @Test func genericSignalsGiveTheRosterAndTheActiveSpeaker() {
        let root = MeetingAXNode(role: "AXGroup", children: [
            MeetingAXNode(role: "AXGroup", texts: ["Marie Dubois (Guest) is speaking"]),
            MeetingAXNode(role: "AXGroup", texts: ["Paul Martin, muted"]),
            MeetingAXNode(role: "AXGroup", texts: ["Tony (You)"]),
            MeetingAXNode(role: "AXButton", texts: ["Mute"]),
        ])
        let tiles = MeetingTileExtractor.participants(app: .zoom, root: root)
        #expect(tiles.map(\.name) == ["Marie Dubois", "Paul Martin", "Tony"])
        #expect(tiles[0].isSpeaking)
        #expect(tiles[1].isMuted)
        #expect(tiles[2].isSelf)
    }

    @Test func meetTilesComeFromTheirClassNames() {
        let active = MeetingAXNode(classes: ["x", "abc__video-frame", "abc__video-frame--active"], children: [
            MeetingAXNode(role: "AXImage", texts: ["profile picture of Marie Dubois"]),
        ])
        let quiet = MeetingAXNode(classes: ["abc__video-frame"], children: [
            MeetingAXNode(role: "AXStaticText", texts: ["Paul Martin"]),
        ])
        let root = MeetingAXNode(children: [active, quiet])
        let tiles = MeetingTileExtractor.participants(app: .meet, root: root)
        #expect(tiles.count == 2)
        #expect(tiles.first { $0.name == "Marie Dubois" }?.isSpeaking == true)
        #expect(tiles.first { $0.name == "Paul Martin" }?.isSpeaking == false)
    }

    @Test func slackHuddleTilesCarryActiveAndMutedMarkers() {
        let speaking = MeetingAXNode(classes: ["p-huddle_peer_tile"], children: [
            MeetingAXNode(classes: ["p-huddle_peer_tile__overlay--active_speaker"]),
            MeetingAXNode(texts: ["Sam Lee"]),
        ])
        let muted = MeetingAXNode(classes: ["p-huddle_peer_tile"], children: [
            MeetingAXNode(classes: ["p-huddle_peer_tile__name_overlay--muted"]),
            MeetingAXNode(texts: ["Ana Ruiz"]),
        ])
        let tiles = MeetingTileExtractor.participants(app: .slack, root: MeetingAXNode(children: [speaking, muted]))
        #expect(tiles.first { $0.name == "Sam Lee" }?.isSpeaking == true)
        #expect(tiles.first { $0.name == "Ana Ruiz" }?.isMuted == true)
        #expect(tiles.first { $0.name == "Ana Ruiz" }?.isSpeaking == false)
    }

    @Test func twoMeetingWindowsMakeTheReadingAmbiguous() throws {
        let marie = [MeetingParticipantState(name: "Marie", isSpeaking: true), MeetingParticipantState(name: "Paul")]
        let one = MeetingWindowArbiter.observation(at: 1, readings: [MeetingWindowReading(app: .zoom, windowID: "a", participants: marie)])
        #expect(try #require(one).isAmbiguous == false)
        let two = MeetingWindowArbiter.observation(at: 1, readings: [
            MeetingWindowReading(app: .zoom, windowID: "a", participants: marie),
            MeetingWindowReading(app: .meet, windowID: "b", participants: marie),
        ])
        #expect(try #require(two).isAmbiguous)
        #expect(MeetingWindowArbiter.observation(at: 1, readings: []) == nil)
    }

    // MARK: Edits, undo, pruning, sample

    @Test func reassigningABlockMovesOnlyThatBlock() {
        let lines = [segment("sys-0", speaker(1), at: 0), segment("sys-1", speaker(1), at: 5)]
        let moved = ScribeSpeakerEdits.reassign(segmentID: "sys-1", to: "Paul", in: lines)
        #expect(moved[0].speaker == speaker(1))
        #expect(moved[1].speaker == .participant("Paul"))
        #expect(ScribeSpeakerEdits.reassign(segmentID: "missing", to: "Paul", in: lines) == lines)
        #expect(ScribeSpeakerEdits.reassign(segmentID: "sys-1", to: "  ", in: lines) == lines)
    }

    @Test func assigningSelectedWordsSplitsTheBlockAndKeepsTheTime() {
        let lines = [segment("sys-0", speaker(1), at: 10, for: 10, "one two three four five")]
        let split = ScribeSpeakerEdits.assignWords(segmentID: "sys-0", range: 2..<4, to: "Paul", in: lines)
        #expect(split.count == 3)
        #expect(split[0].text == "one two" && split[0].speaker == speaker(1) && split[0].id == "sys-0")
        #expect(split[1].text == "three four" && split[1].speaker == .participant("Paul"))
        #expect(split[2].text == "five" && split[2].speaker == speaker(1))
        #expect(split[0].start == 10 && split[2].end == 20)
        #expect(split[0].end == split[1].start && split[1].end == split[2].start)
        #expect(Set(split.map(\.id)).count == 3)
        let all = ScribeSpeakerEdits.assignWords(segmentID: "sys-0", range: 0..<5, to: "Paul", in: lines)
        #expect(all.count == 1 && all[0].speaker == .participant("Paul"))
        #expect(ScribeSpeakerEdits.assignWords(segmentID: "sys-0", range: 3..<9, to: "Paul", in: lines) == lines)
        let head = ScribeSpeakerEdits.assignWords(segmentID: "sys-0", range: 0..<2, to: "Paul", in: lines)
        #expect(head.count == 2 && head[0].id == "sys-0" && head[0].speaker == .participant("Paul") && head[1].speaker == speaker(1))
    }

    @Test func undoBringsBackTheStateBeforeTheLastMerge() {
        let lines = [segment("sys-0", speaker(1), at: 0), segment("sys-1", speaker(2), at: 5)]
        var book = ScribeSpeakerBook()
        var history = ScribeSpeakerEditHistory()
        let before = ScribeSpeakerEditState(segments: lines, book: book)
        history.push("Merge", before: before)
        let merged = ScribeSpeakerNames.rename(speaker(2), to: "Speaker 1", in: lines)
        book.setConfirmed(label: "Speaker 2", name: "Speaker 1")
        #expect(merged.allSatisfy { $0.speaker == speaker(1) })
        #expect(history.canUndo)
        #expect(history.lastTitle == "Merge")
        let restored = history.undo()
        #expect(restored == before)
        #expect(restored?.segments[1].speaker == speaker(2))
        #expect(!history.canUndo)
        #expect(history.undo() == nil)
    }

    @Test func theHistoryKeepsOnlyItsCapacity() {
        var history = ScribeSpeakerEditHistory(capacity: 2)
        let state = ScribeSpeakerEditState(segments: [], book: ScribeSpeakerBook())
        history.push("a", before: state)
        history.push("b", before: state)
        history.push("c", before: state)
        #expect(history.entries.map { $0.title } == ["b", "c"])
    }

    private func meetingWithATinyVoice() -> [ScribeTranscriptSegment] {
        [
            segment("sys-0", speaker(1), at: 0, for: 40),
            segment("sys-1", speaker(2), at: 40, for: 40),
            segment("sys-2", speaker(3), at: 80, for: 1, "ok"),
            segment("sys-3", speaker(1), at: 82, for: 30),
            segment("mic-0", .you, at: 112, for: 20),
        ]
    }

    @Test func aTinyVoiceFoldsIntoTheNearestSpeakerAndCanBeRestored() {
        let lines = meetingWithATinyVoice()
        let result = ScribeSpeakerPruning.prune(segments: lines, book: ScribeSpeakerBook())
        #expect(result.foldedSpeakers == [speaker(3)])
        #expect(result.folds.count == 1)
        #expect(result.segments[2].speaker != speaker(3))
        #expect(result.segments[2].speaker == speaker(1) || result.segments[2].speaker == speaker(2))
        #expect(result.segments[0] == lines[0])
        let back = ScribeSpeakerPruning.restore(folds: result.folds, in: result.segments)
        #expect(back == lines)
    }

    @Test func restoringSkipsABlockThePersonChangedSince() {
        let lines = meetingWithATinyVoice()
        let result = ScribeSpeakerPruning.prune(segments: lines, book: ScribeSpeakerBook())
        let edited = ScribeSpeakerEdits.reassign(segmentID: "sys-2", to: "Paul", in: result.segments)
        let back = ScribeSpeakerPruning.restore(folds: result.folds, in: edited)
        #expect(back[2].speaker == .participant("Paul"))
    }

    @Test func aNamedVoiceYouAndShortMeetingsAreNeverPruned() {
        var book = ScribeSpeakerBook()
        book.setConfirmed(label: "Speaker 3", name: "Paul")
        var lines = meetingWithATinyVoice()
        lines[2].speaker = .participant("Paul")
        #expect(ScribeSpeakerPruning.prune(segments: lines, book: book).folds.isEmpty)
        let shortMeeting = [
            segment("sys-0", speaker(1), at: 0, for: 10),
            segment("sys-1", speaker(2), at: 10, for: 1, "ok"),
        ]
        #expect(ScribeSpeakerPruning.prune(segments: shortMeeting, book: ScribeSpeakerBook()).folds.isEmpty)
        let micTiny = [
            segment("sys-0", speaker(1), at: 0, for: 100),
            segment("mic-0", .you, at: 100, for: 1, "hi"),
        ]
        #expect(ScribeSpeakerPruning.prune(segments: micTiny, book: ScribeSpeakerBook()).folds.isEmpty)
    }

    @Test func aTinyVoiceOnTheMicrophoneFoldsOnlyIntoAMicrophoneSpeaker() {
        let lines = [
            segment("sys-0", speaker(1), at: 0, for: 60),
            segment("mic-0", .you, at: 60, for: 40),
            segment("mic-1", speaker(4), at: 100, for: 1, "um"),
        ]
        let result = ScribeSpeakerPruning.prune(segments: lines, book: ScribeSpeakerBook())
        #expect(result.segments[2].speaker == .you)
    }

    @Test func theVoiceSampleIsThreeSecondsFromTheMiddleOfTheLongestBlock() throws {
        let lines = [
            segment("sys-0", speaker(1), at: 0, for: 2),
            segment("sys-1", speaker(1), at: 10, for: 9),
            segment("sys-2", speaker(2), at: 30, for: 20),
        ]
        let clip = try #require(ScribeVoiceSample.clip(for: speaker(1), in: lines))
        #expect(clip.segmentID == "sys-1")
        #expect(clip.duration == 3)
        #expect(clip.start == 13)
        let short = try #require(ScribeVoiceSample.clip(for: speaker(1), in: [segment("sys-0", speaker(1), at: 4, for: 2)]))
        #expect(short.duration == 2 && short.start == 4)
        #expect(ScribeVoiceSample.clip(for: speaker(9), in: lines) == nil)
    }

    @Test func theIdentifyingPlaceholderShowsOnlyForAnUnresolvedVoiceWhileNamingCanStillHappen() {
        #expect(ScribeSpeakerCaption.name(for: speaker(2), identifying: true).isPlaceholder)
        #expect(ScribeSpeakerCaption.name(for: speaker(2), identifying: true).text == ScribeLiveNaming.identifying)
        #expect(!ScribeSpeakerCaption.name(for: speaker(2), identifying: false).isPlaceholder)
        #expect(ScribeSpeakerCaption.name(for: .participant("Marie"), identifying: true).text == "Marie")
        #expect(ScribeSpeakerCaption.name(for: .you, identifying: true).text == "You")
    }

    @Test func theSourceCaptionsAreShortAndHaveNoDashes() {
        for source in ScribeNameSource.allCases {
            #expect(!source.caption.isEmpty)
            #expect(!source.caption.contains("\u{2014}"))
        }
    }
}
