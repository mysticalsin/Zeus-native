import Foundation
import Testing
@testable import ZeusCore

@Suite("Explanation real-media playback and presentation")
struct ExplanationPlaybackTests {
    private struct Fixture {
        let session = UUID(), turn = UUID(), scene = UUID()
        func playback(_ mode: ExplanationPlayback.Mode = .audible) throws -> ExplanationPlayback {
            try .init(sessionID: session, turnID: turn, sceneID: scene, baseRevision: 0, mode: mode)
        }
        func event(_ index: Int = 0, cues: [ExplanationCue] = [], final: Bool = true) -> ExplanationEvent {
            .init(sessionID: session, turnID: turn, sceneID: scene, sequence: index, baseRevision: index, revision: index + 1,
                  beatID: "beat\(index)", speech: .init(chunkID: "chunk\(index)", text: "An explanation."), cues: cues, isFinal: final)
        }
        func audio(_ index: Int = 0, duration: Double = 2, alignment: [ExplanationAlignmentMark] = []) -> ExplanationAudioChunk {
            .init(sessionID: session, turnID: turn, sceneID: scene, beatID: "beat\(index)", chunkID: "chunk\(index)",
                  duration: duration, sampleRate: 24_000, alignment: alignment)
        }
        var baseline: ExplanationScene { .init(sessionID: session, sceneID: scene) }
    }
    private func object(_ id: String = "object") -> ExplanationObject {
        .init(id: id, geometry: .init(kind: .roundedRectangle, size: .init(x: 10, y: 10)), accessibleDescription: "A rectangle")
    }
    private func starts(_ effects: [ExplanationPlaybackEffect]) -> Int {
        effects.filter { if case .startBeat = $0 { true } else { false } }.count
    }
    private func reveals(_ effects: [ExplanationPlaybackEffect]) -> [ExplanationCueAdmission] {
        effects.compactMap { if case .reveal(let cue) = $0 { cue } else { nil } }
    }
    private func finishes(_ effects: [ExplanationPlaybackEffect]) -> Int {
        effects.filter { if case .finishBeat = $0 { true } else { false } }.count
    }
    @Test func synthesisReadinessDoesNotReserveRevisionOrRevealBeforeRealPlayback() throws {
        let f = Fixture(); var p = try f.playback()
        _ = try p.enqueue(f.event(cues: [.init(id: "create", operations: [.create(object())])]))
        let ready = try p.prepare(f.audio())
        #expect(starts(ready) == 0 && reveals(ready).isEmpty)
        #expect(p.state == .awaitingStart)
        let ticket = try #require(p.ticket)
        let begun = try p.observe(.init(ticketID: ticket.id, position: 0, state: .playing))
        #expect(starts(begun) == 1 && reveals(begun).count == 1)
        #expect(starts(try p.observe(.init(ticketID: ticket.id, position: 0.1, state: .playing))) == 0)
    }
    @Test func outOfOrderSynthesisCannotOvertakeAnEarlierBeat() throws {
        let f = Fixture(); var p = try f.playback()
        _ = try p.enqueue(f.event(final: false)); _ = try p.enqueue(f.event(1))
        #expect(try p.prepare(f.audio(1)).isEmpty)
        #expect(p.ticket == nil)
        _ = try p.prepare(f.audio()); let first = try #require(p.ticket)
        #expect(first.beatID == "beat0")
        _ = try p.observe(.init(ticketID: first.id, position: 0, state: .playing))
        let ended = try p.observe(.init(ticketID: first.id, position: 2, state: .finished))
        #expect(finishes(ended) == 1 && p.ticket?.beatID == "beat1")
        #expect(presentationFinishPrecedesNextAudio(ended))
    }
    private func presentationFinishPrecedesNextAudio(_ effects: [ExplanationPlaybackEffect]) -> Bool {
        guard let finish = effects.firstIndex(where: { if case .finishBeat = $0 { true } else { false } }),
              let play = effects.firstIndex(where: { if case .audio(.play) = $0 { true } else { false } }) else { return false }
        return finish < play
    }
    @Test func wordCuesUseActualAlignmentAndBeatDoesNotCompleteAtReadingEstimate() throws {
        let f = Fixture(); var p = try f.playback()
        let event = f.event(cues: [.init(id: "word", anchor: .word(0), operations: [.create(object())]),
                                  .init(id: "end", anchor: .end, operations: [.highlight(id: "object", highlighted: true)])])
        _ = try p.enqueue(event); _ = try p.prepare(f.audio(alignment: [.init(wordIndex: 0, start: 0.75, end: 1)]))
        let ticket = try #require(p.ticket)
        #expect(reveals(try p.observe(.init(ticketID: ticket.id, position: 0.74, state: .playing))).isEmpty)
        #expect(reveals(try p.observe(.init(ticketID: ticket.id, position: 0.75, state: .playing))).first?.presentationTime == 0.75)
        let atEnd = try p.observe(.init(ticketID: ticket.id, position: 2, state: .playing))
        #expect(reveals(atEnd).count == 1 && finishes(atEnd) == 0 && p.state == .playing)
        #expect(finishes(try p.observe(.init(ticketID: ticket.id, position: 2, state: .finished))) == 1)
        #expect(p.state == .completed)
    }
    @Test func absentOrPartialAlignmentUsesBeatBoundaryWithoutInventingWordTimes() throws {
        let f = Fixture(); var p = try f.playback()
        _ = try p.enqueue(f.event(cues: [.init(id: "first", anchor: .word(0), operations: [.create(object())]),
                                       .init(id: "second", anchor: .word(1), operations: [.highlight(id: "object", highlighted: true)])]))
        _ = try p.prepare(f.audio(alignment: [.init(wordIndex: 0, start: 1, end: 1.5)]))
        let effects = try p.observe(.init(ticketID: #require(p.ticket).id, position: 0, state: .playing))
        #expect(reveals(effects).map(\.presentationTime) == [0, 0])
    }
    @Test func pausedAndOldTicketsCannotAdvanceResumeOrSeek() throws {
        let f = Fixture(); var p = try f.playback()
        _ = try p.enqueue(f.event()); _ = try p.prepare(f.audio())
        let old = try #require(p.ticket)
        _ = try p.observe(.init(ticketID: old.id, position: 0.4, state: .playing)); _ = p.pause()
        #expect(try p.observe(.init(ticketID: old.id, position: 1.5, state: .playing)).isEmpty)
        #expect(p.position == 0.4)
        let paused = try p.observe(.init(ticketID: old.id, position: 0.42, state: .paused))
        #expect(p.position == 0.42 && reveals(paused).isEmpty && starts(paused) == 0)
        _ = try p.setRate(2); _ = p.resume(); let resumed = try #require(p.ticket)
        #expect(resumed.id != old.id)
        #expect(try p.observe(.init(ticketID: old.id, position: 2, state: .finished)).isEmpty)
        _ = try p.observe(.init(ticketID: resumed.id, position: 0.42, state: .playing))
        #expect(p.position == 0.42 && p.rate == 2)
        _ = try p.seek(beatID: "beat0", position: 0.2)
        #expect(try p.observe(.init(ticketID: resumed.id, position: 2, state: .finished)).isEmpty)
    }
    @Test func cancelledTurnIsTerminalAndCannotBeRevivedByAudioOrModelEvents() throws {
        let f = Fixture(); var p = try f.playback()
        _ = try p.enqueue(f.event()); let chunk = f.audio(); _ = try p.prepare(chunk)
        let ticket = try #require(p.ticket); _ = p.cancel()
        #expect(try p.observe(.init(ticketID: ticket.id, position: 1, state: .playing)).isEmpty)
        #expect(throws: ExplanationFailure.cancelled) { try p.prepare(chunk) }
        #expect(throws: ExplanationFailure.cancelled) { try p.enqueue(f.event()) }
        #expect(p.resume().isEmpty && p.cancel().isEmpty)
    }
    @Test func mutedBeatsAdvanceOnlyExplicitlyIncludingSpokenOnlyReservations() throws {
        let f = Fixture(); var p = try f.playback(.captions)
        #expect(try p.enqueue(f.event(final: false)).isEmpty)
        _ = try p.enqueue(f.event(1, cues: [.init(id: "visual", operations: [.create(object())])]))
        #expect(p.state == .awaitingCaptionAdvance && p.ticket == nil)
        let spokenOnly = try p.advanceCaption()
        #expect(starts(spokenOnly) == 1 && finishes(spokenOnly) == 1 && reveals(spokenOnly).isEmpty)
        let visual = try p.advanceCaption()
        #expect(starts(visual) == 1 && finishes(visual) == 1 && reveals(visual).count == 1)
        #expect(p.state == .completed && p.ticket == nil)
    }
    @Test func captionCompletionPreservesActualPartiallyPlayedTimeAndLateSynthesisCannotRewriteIt() throws {
        let f = Fixture(); var p = try f.playback()
        _ = try p.enqueue(f.event(final: false)); _ = try p.enqueue(f.event(1, final: false)); _ = try p.enqueue(f.event(2))
        _ = try p.prepare(f.audio())
        _ = try p.observe(.init(ticketID: #require(p.ticket).id, position: 1, state: .playing))
        _ = try p.setMode(.captions); _ = try p.advanceCaption()
        #expect(p.presentationTime == 1)
        _ = try p.advanceCaption() // Entirely silent beat contributes zero.
        #expect(p.presentationTime == 1)
        _ = try p.prepare(f.audio(1, duration: 10)) // A late completion cannot add ten seconds.
        #expect(p.presentationTime == 1)
        _ = try p.prepare(f.audio(2)); _ = try p.setMode(.audible)
        _ = try p.observe(.init(ticketID: #require(p.ticket).id, position: 0.5, state: .playing))
        #expect(p.presentationTime == 1.5)
    }
    @Test func manualCaptionReplayUsesActualChunkEndForEndCuesWithoutCanonicalAdmission() throws {
        let f = Fixture(); var p = try f.playback(.captions)
        _ = try p.enqueue(f.event(cues: [.init(id: "end", anchor: .end, operations: [.create(object())])]))
        _ = try p.prepare(f.audio(duration: 3)); _ = try p.seek(beatID: "beat0", position: 0)
        let effects = try p.advanceCaption()
        #expect(starts(effects) == 0 && reveals(effects).isEmpty && finishes(effects) == 0)
        let replayScenes = effects.compactMap { effect -> ExplanationScene? in
            if case .replay(let events, let cues, let time) = effect {
                #expect(time == 3 && cues.first?.presentationTime == 3)
                return try? ExplanationPresentation.replay(from: f.baseline, events: events, cues: cues, at: time)
            }
            return nil
        }
        let replay = try #require(replayScenes.first)
        #expect(replay.objects["object"] != nil && p.state == .completed)
    }
    @Test func invalidIdentityGapDuplicateAndMediaPositionLeaveStateUnchanged() throws {
        let f = Fixture(); var p = try f.playback()
        #expect(throws: ExplanationFailure.sequenceGap) { try p.enqueue(f.event(1)) }
        _ = try p.enqueue(f.event()); #expect(try p.enqueue(f.event()).isEmpty)
        var conflicting = f.event(); conflicting.speech.text = "Changed"
        #expect(throws: ExplanationFailure.conflictingDuplicate) { try p.enqueue(conflicting) }
        var wrong = f.audio(); wrong.turnID = UUID()
        #expect(throws: ExplanationFailure.staleIdentity) { try p.prepare(wrong) }
        _ = try p.prepare(f.audio()); let ticket = try #require(p.ticket), before = p
        #expect(throws: ExplanationFailure.self) { try p.observe(.init(ticketID: ticket.id, position: .nan, state: .playing)) }
        #expect(p == before)
        #expect(throws: ExplanationFailure.self) { try p.observe(.init(ticketID: ticket.id, position: 2, state: .finished)) }
        #expect(throws: ExplanationFailure.self) { try p.setRate(.infinity) }
    }
    @Test func replayRetainsSpokenOnlyRevisionsAndNeverEmitsCanonicalAdmissions() throws {
        let f = Fixture(); var p = try f.playback()
        _ = try p.enqueue(f.event(final: false)); let visual = f.event(1, cues: [.init(id: "create", operations: [.create(object())])])
        _ = try p.enqueue(visual); _ = try p.prepare(f.audio()); _ = try p.prepare(f.audio(1))
        let effects = try p.seek(beatID: "beat1", position: 0.5)
        #expect(starts(effects) == 0 && reveals(effects).isEmpty && finishes(effects) == 0)
        let replay = try #require(effects.compactMap { effect -> ExplanationScene? in
            if case .replay(let events, let cues, let time) = effect {
                return try? ExplanationPresentation.replay(from: f.baseline, events: events, cues: cues, at: time)
            }
            return nil
        }.first)
        #expect(replay.revision == 2 && replay.objects["object"] != nil)
    }
    @Test func unchangedReplayPrefixEmitsOnlyLightweightFramesUntilActualCueBoundary() throws {
        let f = Fixture(); var p = try f.playback()
        let event = f.event(cues: [.init(id: "first", operations: [.create(object())]),
            .init(id: "later", anchor: .word(0), operations: [.highlight(id: "object", highlighted: true)])])
        _ = try p.enqueue(event); _ = try p.prepare(f.audio(alignment: [.init(wordIndex: 0, start: 1, end: 1.2)]))
        let first = try p.seek(beatID: "beat0", position: 0)
        #expect(first.contains { if case .replay = $0 { true } else { false } })
        let ticket = try #require(p.ticket)
        #expect(try p.observe(.init(ticketID: ticket.id, position: 0.25, state: .playing)) == [.replayFrame(presentationTime: 0.25)])
        #expect(try p.observe(.init(ticketID: ticket.id, position: 0.75, state: .playing)) == [.replayFrame(presentationTime: 0.75)])
        let boundary = try p.observe(.init(ticketID: ticket.id, position: 1, state: .playing))
        #expect(boundary.contains { if case .replay(_, let cues, _) = $0 { cues.count == 2 } else { false } })
        #expect(try p.observe(.init(ticketID: ticket.id, position: 1.5, state: .playing)) == [.replayFrame(presentationTime: 1.5)])
    }
    @Test func seekingExactMediaEndNeverRequestsZeroLengthPlaybackOrCanonicalCompletion() throws {
        let f = Fixture(); var playback = try f.playback()
        _ = try playback.enqueue(f.event(cues: [.init(id: "end", anchor: .end, operations: [.create(object())])]))
        _ = try playback.prepare(f.audio(duration: 2))
        let effects = try playback.seek(beatID: "beat0", position: 2)
        #expect(playback.state == .completed && playback.ticket == nil && playback.presentationTime == 2)
        #expect(starts(effects) == 0 && reveals(effects).isEmpty && finishes(effects) == 0)
        #expect(!effects.contains { if case .audio(.play) = $0 { true } else { false } })
        #expect(effects.contains { if case .replay(_, let cues, let time) = $0 { cues.count == 1 && time == 2 } else { false } })
    }
    @Test func currentBeatPreviewCompletesWithoutWaitingForAcceptedFutureAudioAndReplayResetsLimit() throws {
        let f = Fixture(); var playback = try f.playback()
        _ = try playback.enqueue(f.event(final: false)); _ = try playback.enqueue(f.event(1))
        _ = try playback.prepare(f.audio()) // Future event accepted, its synthesis is still unavailable.
        _ = try playback.seek(beatID: "beat0", position: 1, stopAfterBeat: true)
        let ticket = try #require(playback.ticket)
        _ = try playback.observe(.init(ticketID: ticket.id, position: 1, state: .playing))
        let ended = try playback.observe(.init(ticketID: ticket.id, position: 2, state: .finished))
        #expect(playback.state == .completed && playback.currentEvent == nil && playback.ticket == nil)
        #expect(starts(ended) == 0 && reveals(ended).isEmpty && finishes(ended) == 0)
        _ = try playback.setMode(.captions)
        let noAdvance = try playback.advanceCaption()
        #expect(playback.state == .completed && noAdvance.isEmpty)
        _ = try playback.setMode(.audible)
        _ = try playback.replay() // Full replay explicitly clears the one-beat preview bound.
        let replay = try #require(playback.ticket)
        _ = try playback.observe(.init(ticketID: replay.id, position: 0, state: .playing))
        _ = try playback.observe(.init(ticketID: replay.id, position: 2, state: .finished))
        #expect(playback.state == .buffering && playback.currentEvent?.beatID == "beat1")
        _ = try playback.prepare(f.audio(1))
        #expect(playback.ticket?.beatID == "beat1")
    }
    @Test func animationOverlapBeginsAtSampledPoseAndInterruptionCanFreezeIt() throws {
        let f = Fixture(); var presentation = try ExplanationPresentation(scene: f.baseline)
        let event = f.event(cues: [.init(id: "initial", operations: [.create(object()),
            .animate(id: "object", animation: .init(property: .position, to: .init(x: 100, y: 0), duration: 10, curve: .linear))]),
            .init(id: "overlap", anchor: .word(0), operations: [.animate(id: "object", animation: .init(property: .position, to: .init(x: 200, y: 0), duration: 10, curve: .linear))])])
        try presentation.apply(.init(event: event, cueIndex: 0, presentationTime: 0))
        #expect(try presentation.sample(at: 5).objects["object"]?.transform.position.x == 50)
        try presentation.apply(.init(event: event, cueIndex: 1, presentationTime: 5))
        let frozen = try presentation.sample(at: 10)
        #expect(frozen.objects["object"]?.transform.position.x == 125)
        let stopped = try ExplanationPresentation(scene: ExplanationSceneReducer.restoring(frozen, atRevision: 2))
        #expect(try stopped.sample(at: 100).objects["object"]?.transform.position.x == 125)
    }
    @Test func zeroDurationAndReducedMotionSnapToFiniteFinalPose() throws {
        let f = Fixture(); var p = try ExplanationPresentation(scene: f.baseline)
        var rectangle = object(); rectangle.reveal = 0
        let event = f.event(cues: [.init(id: "instant", operations: [.create(rectangle),
            .animate(id: "object", animation: .init(property: .position, to: .init(x: 100, y: 0), duration: 0)),
            .animate(id: "object", animation: .init(property: .strokeReveal, to: .init(x: 1, y: 0), duration: 10))])])
        try p.apply(.init(event: event, cueIndex: 0, presentationTime: 0))
        #expect(try p.sample(at: 0).objects["object"]?.transform.position.x == 100)
        #expect(try p.sample(at: 0).objects["object"]?.reveal == 0)
        #expect(try p.sample(at: 0, reduceMotion: true).objects["object"]?.reveal == 1)
    }
    @Test func actualShortAudioBoundsLongAnimationWithoutFabricatingCompletionTime() throws {
        let f = Fixture(); var playback = try f.playback(), presentation = try ExplanationPresentation(scene: f.baseline)
        let event = f.event(cues: [.init(id: "move", operations: [.create(object()),
            .animate(id: "object", animation: .init(property: .position, to: .init(x: 100, y: 0), duration: 10, curve: .linear))])])
        _ = try playback.enqueue(event); _ = try playback.prepare(f.audio(duration: 2))
        let ticket = try #require(playback.ticket)
        let begun = try playback.observe(.init(ticketID: ticket.id, position: 0, state: .playing))
        let cue = try #require(reveals(begun).first)
        #expect(cue.remainingMediaDuration == 2)
        try presentation.apply(cue)
        #expect(try presentation.sample(at: 1).objects["object"]?.transform.position.x == 50)
        let finished = try playback.observe(.init(ticketID: ticket.id, position: 2, state: .finished))
        #expect(playback.state == .completed && finishes(finished) == 1)
        #expect(try presentation.sample(at: 2).objects["object"]?.transform.position.x == 100)
        let replay = try playback.seek(beatID: "beat0", position: 1)
        let replayCues = replay.compactMap { effect -> [ExplanationCueAdmission]? in
            if case .replay(_, let cues, _) = effect { cues } else { nil }
        }.first
        #expect(replayCues?.first?.remainingMediaDuration == 2)
    }
    @Test func reducedMotionAndManualCaptionsPreserveStaticRevealWhileSnappingAdmittedMotion() throws {
        let f = Fixture(); var playback = try f.playback(.captions), presentation = try ExplanationPresentation(scene: f.baseline)
        var hidden = object("hidden"); hidden.reveal = 0
        let event = f.event(cues: [.init(id: "move", operations: [.create(hidden), .create(object()),
            .animate(id: "object", animation: .init(property: .position, to: .init(x: 100, y: 0), duration: 10, curve: .linear))])])
        _ = try playback.enqueue(event)
        let effects = try playback.advanceCaption()
        let cue = try #require(reveals(effects).first)
        #expect(cue.remainingMediaDuration == 0)
        try presentation.apply(cue)
        #expect(try presentation.sample(at: 0).objects["object"]?.transform.position.x == 100)
        #expect(try presentation.sample(at: 0, reduceMotion: true).objects["hidden"]?.reveal == 0)
        let before = presentation
        #expect(throws: ExplanationFailure.self) {
            try presentation.apply(.init(event: event, cueIndex: 0, presentationTime: 0, remainingMediaDuration: .infinity))
        }
        #expect(presentation == before)
    }
    @Test func validAnimationEndpointsCannotExposeUnsafeComposedMidpoint() throws {
        let f = Fixture()
        var baseline = f.baseline
        let group = ExplanationObject(id: "group", geometry: .init(kind: .group),
            transform: .init(scale: .init(x: 100, y: 100, z: 1)), accessibleDescription: "A group")
        var child = object(); child.parentID = "group"; child.transform.scale = .init(x: 0.01, y: 0.01, z: 1)
        baseline.objects = [group.id: group, child.id: child]
        var presentation = try ExplanationPresentation(scene: baseline)
        let event = f.event(cues: [.init(id: "inverse-scale", operations: [
            .animate(id: "group", animation: .init(property: .scale, to: .init(x: 0.01, y: 0.01, z: 1), duration: 10, curve: .linear)),
            .animate(id: "object", animation: .init(property: .scale, to: .init(x: 100, y: 100, z: 1), duration: 10, curve: .linear))])])
        try presentation.apply(.init(event: event, cueIndex: 0, presentationTime: 0))
        #expect(try presentation.sample(at: 0).objects["group"]?.transform.scale.x == 100)
        #expect(throws: ExplanationFailure.self) { try presentation.sample(at: 5) }
        #expect(try presentation.sample(at: 10).objects["object"]?.transform.scale.x == 100)
        #expect(try presentation.sample(at: 5, reduceMotion: true).objects["object"]?.transform.scale.x == 100)
    }
    @Test func atomicCueForwardReferencesRenderAndInvalidCueLeavesPresentationUntouched() throws {
        let f = Fixture(); var p = try ExplanationPresentation(scene: f.baseline)
        let connector = ExplanationObject(id: "line", geometry: .init(kind: .connector, fromID: "a", toID: "b"), accessibleDescription: "Connects two shapes")
        let event = f.event(cues: [.init(id: "atomic", operations: [.connect(connector), .create(object("a")), .create(object("b"))])])
        try p.apply(.init(event: event, cueIndex: 0, presentationTime: 0))
        #expect(p.targetScene.objects.count == 3)
        let before = p
        let bad = f.event(1, cues: [.init(id: "invalid", operations: [.move(id: "a", position: .init(x: 20, y: 0)), .remove(id: "missing")])])
        #expect(throws: ExplanationFailure.self) { try p.apply(.init(event: bad, cueIndex: 0, presentationTime: 1)) }
        #expect(p == before)
    }
    @Test func replayCacheExtendsCuePrefixThenRebuildsAfterBackwardSeek() throws {
        let f = Fixture()
        let event = f.event(cues: [.init(id: "first", operations: [.create(object()),
            .animate(id: "object", animation: .init(property: .position, to: .init(x: 100, y: 0), duration: 10, curve: .linear))]),
            .init(id: "overlap", anchor: .word(0), operations: [
                .animate(id: "object", animation: .init(property: .position, to: .init(x: 200, y: 0), duration: 10, curve: .linear))])])
        let first = ExplanationCueAdmission(event: event, cueIndex: 0, presentationTime: 0)
        let second = ExplanationCueAdmission(event: event, cueIndex: 1, presentationTime: 5)
        var cache = try ExplanationReplayPresentation(scene: f.baseline)
        #expect(try cache.sample(events: [event], cues: [first], at: 4).objects["object"]?.transform.position.x == 40)
        #expect(try cache.sample(events: [event], cues: [first, second], at: 10).objects["object"]?.transform.position.x == 125)
        #expect(try cache.sample(at: 11).objects["object"]?.transform.position.x == 140)
        #expect(try cache.sample(events: [event], cues: [first], at: 2).objects["object"]?.transform.position.x == 20)
        #expect(try cache.sample(events: [event], cues: [first, second], at: 10, reduceMotion: true).objects["object"]?.transform.position.x == 200)
    }
    @Test func replayCachePreservesZeroCueRevisionsAndRejectsMalformedUpdateAtomically() throws {
        let f = Fixture(), spoken = Fixture() // A foreign identity must never enter the cache.
        let first = f.event(final: false), last = f.event(1, cues: [.init(id: "create", operations: [.create(object())])])
        let cue = ExplanationCueAdmission(event: last, cueIndex: 0, presentationTime: 2)
        var cache = try ExplanationReplayPresentation(scene: f.baseline)
        #expect(try cache.sample(events: [first], cues: [], at: 1).revision == 1)
        let completed = try cache.sample(events: [first, last], cues: [cue], at: 2)
        #expect(completed.revision == 2 && completed.objects["object"] != nil)
        let before = cache
        #expect(throws: ExplanationFailure.self) { try cache.sample(events: [first, last], cues: [cue], at: 1) }
        #expect(throws: ExplanationFailure.self) { try cache.sample(events: [spoken.event()], cues: [], at: 3) }
        #expect(throws: ExplanationFailure.self) { try cache.sample(events: [first, last], cues: [cue, cue], at: 3) }
        #expect(cache == before)
        #expect(try cache.sample(events: [], cues: [], at: 0) == f.baseline)
    }
    @Test func replayCacheChangedPayloadRebuildsInsteadOfRetainingPriorObjects() throws {
        let f = Fixture(); var cache = try ExplanationReplayPresentation(scene: f.baseline)
        let old = f.event(cues: [.init(id: "create", operations: [.create(object("old"))])])
        let replacement = f.event(cues: [.init(id: "create", operations: [.create(object("replacement"))])])
        _ = try cache.sample(events: [old], cues: [.init(event: old, cueIndex: 0, presentationTime: 0)], at: 0)
        let changed = try cache.sample(events: [replacement], cues: [.init(event: replacement, cueIndex: 0, presentationTime: 0)], at: 0)
        #expect(changed.objects["old"] == nil && changed.objects["replacement"] != nil)
    }
}
