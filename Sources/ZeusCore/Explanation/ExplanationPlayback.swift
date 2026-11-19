import Foundation

/// One app-issued playback attempt, distinct from the reusable audio artifact.
/// Resume/seek create a new ticket so an old delegate callback cannot advance it.
public struct ExplanationPlaybackTicket: Equatable, Sendable {
    public let id: UUID
    public let audioID: UUID
    public let sessionID: UUID
    public let turnID: UUID
    public let sceneID: UUID
    public let beatID: String
    public init(id: UUID = UUID(), audio: ExplanationAudioChunk) {
        self.id = id; audioID = audio.id; sessionID = audio.sessionID; turnID = audio.turnID
        sceneID = audio.sceneID; beatID = audio.beatID
    }
}

public enum ExplanationPlaybackCommand: Equatable, Sendable {
    case play(ticket: ExplanationPlaybackTicket, audio: ExplanationAudioChunk, position: Double, rate: Double)
    case pause(ticketID: UUID)
    case stop(ticketID: UUID)
    case setRate(ticketID: UUID, rate: Double)
}

public struct ExplanationPlaybackObservation: Equatable, Sendable {
    public enum State: Equatable, Sendable { case playing, paused, finished, failed(String) }
    public var ticketID: UUID
    public var position: Double
    public var state: State
    public init(ticketID: UUID, position: Double, state: State) {
        self.ticketID = ticketID; self.position = position; self.state = state
    }
}

public struct ExplanationCueAdmission: Equatable, Sendable {
    public let event: ExplanationEvent
    public let cueIndex: Int
    /// Actual preceding chunk durations plus this cue's resolved media offset.
    public let presentationTime: Double
    /// App-owned actual chunk time remaining at this cue. Nil is reserved for
    /// direct presentation fixtures without a media artifact; captions use zero.
    public let remainingMediaDuration: Double?
    public var cue: ExplanationCue { event.cues[cueIndex] }
    public init(event: ExplanationEvent, cueIndex: Int, presentationTime: Double, remainingMediaDuration: Double? = nil) {
        self.event = event; self.cueIndex = cueIndex; self.presentationTime = presentationTime
        self.remainingMediaDuration = remainingMediaDuration
    }
}

/// Apply effects in order. In particular, finish the prior history admission before
/// starting the next audio command. Replay never emits canonical start/reveal/finish effects.
public enum ExplanationPlaybackEffect: Equatable, Sendable {
    case audio(ExplanationPlaybackCommand)
    case startBeat(ExplanationEvent)
    case reveal(ExplanationCueAdmission)
    case finishBeat(ExplanationEvent)
    case frame(presentationTime: Double)
    case replay(events: [ExplanationEvent], cues: [ExplanationCueAdmission], presentationTime: Double)
    case replayFrame(presentationTime: Double)
}

/// Pure clock consumer. It owns neither a microphone, audio player, wall clock, nor scene store.
/// The coordinator validates each event against its projected scene before enqueueing it.
public struct ExplanationPlayback: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case audible, captions }
    public enum State: Equatable, Sendable {
        case buffering, awaitingStart, playing, paused, awaitingCaptionAdvance, completed, cancelled, failed(String)
    }
    public let sessionID: UUID
    public let turnID: UUID
    public let sceneID: UUID
    public let baseRevision: Int
    public private(set) var mode: Mode
    public private(set) var state: State
    public private(set) var rate: Double = 1
    public private(set) var position: Double = 0
    public private(set) var isReplay = false
    public private(set) var ticket: ExplanationPlaybackTicket?
    public private(set) var events: [ExplanationEvent] = []
    private var audio: [String: ExplanationAudioChunk] = [:]
    private var cueTimes: [String: [Double]] = [:]
    private struct ReplayPrefix: Equatable, Sendable { let beat: Int; let cues: Int }
    private var replayPrefix: ReplayPrefix?
    private var replayLimit: Int?
    private var started = Set<String>()
    private var revealed: [String: Int] = [:]
    private var completedDurations: [String: Double] = [:]
    private var index = 0
    private var bytes = 0
    private var finalReceived = false

    public init(sessionID: UUID, turnID: UUID, sceneID: UUID, baseRevision: Int, mode: Mode = .audible) throws {
        guard (0...ExplanationLimits.revision).contains(baseRevision) else { throw ExplanationFailure.revisionConflict }
        self.sessionID = sessionID; self.turnID = turnID; self.sceneID = sceneID; self.baseRevision = baseRevision
        self.mode = mode; state = mode == .captions ? .awaitingCaptionAdvance : .buffering
    }

    public var currentEvent: ExplanationEvent? {
        if isReplay, let replayLimit, index >= replayLimit { return nil }
        return events.indices.contains(index) ? events[index] : nil
    }
    public var preparedBeatIDs: Set<String> { Set(audio.keys) }
    public var presentationTime: Double { offset(before: index) + position }

    /// Identical transport retries are inert. No gap, replacement, or post-final event is accepted.
    public mutating func enqueue(_ event: ExplanationEvent) throws -> [ExplanationPlaybackEffect] {
        try requireLive()
        guard !isReplay else { throw ExplanationFailure.streamFinished }
        try ExplanationSceneReducer.validate(event)
        guard matches(event) else { throw ExplanationFailure.staleIdentity }
        if events.indices.contains(event.sequence) {
            guard events[event.sequence] == event else { throw ExplanationFailure.conflictingDuplicate }
            return []
        }
        guard !finalReceived else { throw ExplanationFailure.streamFinished }
        guard event.sequence == events.count else { throw ExplanationFailure.sequenceGap }
        guard event.baseRevision == (events.last?.revision ?? baseRevision) else { throw ExplanationFailure.revisionConflict }
        guard events.count < ExplanationLimits.events,
              !events.contains(where: { $0.beatID == event.beatID || $0.speech.chunkID == event.speech.chunkID }) else {
            throw ExplanationFailure.conflictingDuplicate
        }
        let size = try JSONEncoder().encode(event).count
        guard size <= ExplanationLimits.frameBytes, bytes + size <= ExplanationLimits.turnBytes else {
            throw ExplanationFailure.limitExceeded("playback event buffer")
        }
        events.append(event); bytes += size; finalReceived = event.isFinal
        return requestStart()
    }

    /// Synthesis may complete out of order, but only the head beat can start. Metadata
    /// is bounded by the accepted turn; the native adapter separately bounds actual audio bytes.
    public mutating func prepare(_ chunk: ExplanationAudioChunk) throws -> [ExplanationPlaybackEffect] {
        try requireLive()
        try ExplanationSceneReducer.validate(chunk)
        guard chunk.sessionID == sessionID, chunk.turnID == turnID, chunk.sceneID == sceneID,
              let event = events.first(where: { $0.beatID == chunk.beatID }), event.speech.chunkID == chunk.chunkID else {
            throw ExplanationFailure.staleIdentity
        }
        if let prior = audio[chunk.beatID] {
            guard prior == chunk else { throw ExplanationFailure.conflictingDuplicate }
            return []
        }
        guard !audio.values.contains(where: { $0.id == chunk.id }),
              audio.values.reduce(0, { $0 + $1.duration }) + chunk.duration <= 900 else {
            throw ExplanationFailure.limitExceeded("prepared audio duration")
        }
        // A partial provider alignment never invents missing word positions. Fall back
        // for the entire beat, preserving declared cue order at the beat boundary.
        cueTimes[chunk.beatID] = resolvedTimes(event, chunk: chunk)
        audio[chunk.beatID] = chunk
        return requestStart()
    }

    public mutating func observe(_ observation: ExplanationPlaybackObservation) throws -> [ExplanationPlaybackEffect] {
        guard let ticket, ticket.id == observation.ticketID, let event = currentEvent,
              let chunk = audio[event.beatID], !terminal else { return [] }
        if case .failed(let reason) = observation.state {
            state = .failed(String(reason.prefix(256))); self.ticket = nil
            return [.audio(.stop(ticketID: ticket.id))]
        }
        guard observation.position.isFinite, observation.position >= 0,
              observation.position <= chunk.duration + 1 / chunk.sampleRate else {
            throw ExplanationFailure.invalid("playback position")
        }
        // Accept the player's final authoritative pause position, but never let a
        // queued playing/finished callback reveal another cue after Pause.
        if state == .paused {
            guard observation.state == .paused else { return [] }
            guard observation.position >= position else { throw ExplanationFailure.invalid("playback position regressed") }
            position = min(observation.position, chunk.duration)
            if isReplay {
                return [replayEffect()]
            }
            return [.frame(presentationTime: presentationTime)]
        }
        guard observation.position >= position else { throw ExplanationFailure.invalid("playback position regressed") }
        if observation.state == .paused { state = .paused; position = observation.position; return [] }
        if observation.state == .finished {
            guard state == .playing, observation.position >= chunk.duration else {
                throw ExplanationFailure.invalid("completion without observed playback")
            }
        }
        position = min(observation.position, chunk.duration)
        state = .playing
        var effects: [ExplanationPlaybackEffect] = []
        if isReplay {
            effects.append(replayEffect())
        } else {
            if started.insert(event.beatID).inserted { effects.append(.startBeat(event)) }
            let times = times(for: event)
            var next = revealed[event.beatID] ?? 0
            while next < times.count, times[next] <= position {
                effects.append(.reveal(.init(event: event, cueIndex: next, presentationTime: offset(before: index) + times[next],
                                            remainingMediaDuration: max(0, chunk.duration - times[next]))))
                next += 1
            }
            revealed[event.beatID] = next
            effects.append(.frame(presentationTime: presentationTime))
        }
        if observation.state == .finished {
            if !isReplay { effects.append(.finishBeat(event)) }
            if !isReplay { completedDurations[event.beatID] = chunk.duration }
            self.ticket = nil; index += 1; position = 0; state = .buffering
            effects += requestStart()
        }
        return effects
    }

    public mutating func pause() -> [ExplanationPlaybackEffect] {
        guard !terminal, mode == .audible, state != .paused else { return [] }
        state = .paused
        return ticket.map { [.audio(.pause(ticketID: $0.id))] } ?? []
    }

    public mutating func resume() -> [ExplanationPlaybackEffect] {
        guard !terminal, state == .paused else { return [] }
        let effects = ticket.map { [ExplanationPlaybackEffect.audio(.stop(ticketID: $0.id))] } ?? []
        ticket = nil; state = .buffering
        return effects + requestStart()
    }

    public mutating func setRate(_ value: Double) throws -> [ExplanationPlaybackEffect] {
        try requireLive()
        guard value.isFinite, (0.5...2).contains(value) else { throw ExplanationFailure.invalid("playback rate") }
        rate = value
        return ticket.map { [.audio(.setRate(ticketID: $0.id, rate: value))] } ?? []
    }

    public mutating func setMode(_ value: Mode) throws -> [ExplanationPlaybackEffect] {
        try requireLive()
        guard mode != value else { return [] }
        var effects = ticket.map { [ExplanationPlaybackEffect.audio(.stop(ticketID: $0.id))] } ?? []
        ticket = nil; mode = value
        state = value == .captions ? .awaitingCaptionAdvance : .buffering
        effects += requestStart()
        return effects
    }

    /// Muted mode has no estimated reading duration. One explicit action displays and
    /// completes one beat; animations snap rather than running on a fabricated audio clock.
    public mutating func advanceCaption() throws -> [ExplanationPlaybackEffect] {
        try requireLive()
        guard mode == .captions, let event = currentEvent else { return [] }
        var effects: [ExplanationPlaybackEffect] = []
        if isReplay {
            // An explicit replay step can jump to the real chunk end; it must not
            // attach future end cues to an earlier presentation time.
            position = audio[event.beatID]?.duration ?? 0
            effects.append(replayEffect())
        } else {
            if started.insert(event.beatID).inserted { effects.append(.startBeat(event)) }
            for cue in (revealed[event.beatID] ?? 0)..<event.cues.count {
                effects.append(.reveal(.init(event: event, cueIndex: cue, presentationTime: presentationTime, remainingMediaDuration: 0)))
            }
            revealed[event.beatID] = event.cues.count
            effects.append(.frame(presentationTime: presentationTime))
            effects.append(.finishBeat(event))
        }
        // A beat that began audibly keeps its observed elapsed media time when
        // switched to manual captions. A wholly silent beat contributes zero.
        if !isReplay { completedDurations[event.beatID] = position }
        index += 1; position = 0
        state = .awaitingCaptionAdvance
        effects += requestStart()
        return effects
    }

    /// Seeking is explicitly a read-only presentation. The coordinator cancels model
    /// generation/admission first; none of these effects recommit already applied edits.
    /// `stopAfterBeat` bounds a current-beat preview when future synthesis was cancelled.
    public mutating func seek(beatID: String, position target: Double, stopAfterBeat: Bool = false) throws -> [ExplanationPlaybackEffect] {
        try requireLive()
        guard let targetIndex = events.firstIndex(where: { $0.beatID == beatID }),
              let chunk = audio[beatID], target.isFinite, target >= 0, target <= chunk.duration,
              events.prefix(targetIndex).allSatisfy({ audio[$0.beatID] != nil }) else {
            throw ExplanationFailure.invalid("unavailable seek target")
        }
        var effects = ticket.map { [ExplanationPlaybackEffect.audio(.stop(ticketID: $0.id))] } ?? []
        ticket = nil; index = targetIndex; position = target; isReplay = true
        replayLimit = stopAfterBeat ? targetIndex + 1 : nil
        state = mode == .captions ? .awaitingCaptionAdvance : .buffering
        effects.append(replayEffect(force: true))
        if target == chunk.duration {
            // An explicit seek to the exact end is a read-only end frame, not a
            // request to play zero remaining samples or fabricate a playback callback.
            index += 1; position = 0
        }
        effects += requestStart()
        return effects
    }

    public mutating func replay() throws -> [ExplanationPlaybackEffect] {
        guard let first = events.first else { return [] }
        return try seek(beatID: first.beatID, position: 0)
    }

    /// Terminal for this turn. A new turn uses a new scheduler and the preserved canonical scene.
    public mutating func cancel() -> [ExplanationPlaybackEffect] {
        guard state != .cancelled else { return [] }
        let effects = ticket.map { [ExplanationPlaybackEffect.audio(.stop(ticketID: $0.id))] } ?? []
        ticket = nil; state = .cancelled
        return effects
    }

    private var terminal: Bool {
        switch state { case .cancelled, .failed: true; default: false }
    }
    private func requireLive() throws { if terminal { throw ExplanationFailure.cancelled } }
    private func matches(_ event: ExplanationEvent) -> Bool {
        event.sessionID == sessionID && event.turnID == turnID && event.sceneID == sceneID
    }
    private mutating func requestStart() -> [ExplanationPlaybackEffect] {
        guard !terminal, ticket == nil, state != .paused else { return [] }
        if isReplay, let replayLimit, index >= replayLimit {
            state = .completed
            return []
        }
        guard let event = currentEvent else {
            state = finalReceived ? .completed : (mode == .captions ? .awaitingCaptionAdvance : .buffering)
            return []
        }
        guard mode == .audible else { state = .awaitingCaptionAdvance; return [] }
        guard let chunk = audio[event.beatID] else { state = .buffering; return [] }
        let ticket = ExplanationPlaybackTicket(audio: chunk)
        self.ticket = ticket; state = .awaitingStart
        return [.audio(.play(ticket: ticket, audio: chunk, position: position, rate: rate))]
    }
    private func offset(before position: Int) -> Double {
        events.prefix(position).reduce(0) {
            $0 + (isReplay ? (audio[$1.beatID]?.duration ?? 0) : (completedDurations[$1.beatID] ?? audio[$1.beatID]?.duration ?? 0))
        }
    }
    private func resolvedTimes(_ event: ExplanationEvent, chunk: ExplanationAudioChunk?) -> [Double] {
        let marks = Dictionary(uniqueKeysWithValues: (chunk?.alignment ?? []).map { ($0.wordIndex, $0.start) })
        let aligned = event.cues.allSatisfy { $0.anchor.kind != .word || marks[$0.anchor.wordIndex ?? -1] != nil }
        return event.cues.map { cue in
            switch cue.anchor.kind {
            case .start: return 0
            case .end: return chunk?.duration ?? 0
            case .word: return aligned ? (marks[cue.anchor.wordIndex ?? -1] ?? 0) : 0
            }
        }
    }
    private func times(for event: ExplanationEvent) -> [Double] {
        cueTimes[event.beatID] ?? Array(repeating: 0, count: event.cues.count)
    }
    private mutating func replayEffect(force: Bool = false) -> ExplanationPlaybackEffect {
        let count = currentEvent.map { times(for: $0).prefix(while: { $0 <= position }).count } ?? 0
        let prefix = ReplayPrefix(beat: index, cues: count)
        if !force, replayPrefix == prefix { return .replayFrame(presentationTime: presentationTime) }
        replayPrefix = prefix
        return .replay(events: Array(events.prefix(index + 1)), cues: replayCues(through: index, position: position),
                       presentationTime: presentationTime)
    }
    private func replayCues(through target: Int, position: Double) -> [ExplanationCueAdmission] {
        var result: [ExplanationCueAdmission] = []
        for i in 0...target where events.indices.contains(i) {
            let event = events[i], times = times(for: event)
            for (cue, time) in times.enumerated() where i < target || time <= position {
                result.append(.init(event: event, cueIndex: cue, presentationTime: offset(before: i) + time,
                                    remainingMediaDuration: max(0, (audio[event.beatID]?.duration ?? 0) - time)))
            }
        }
        return result
    }
}

/// Deterministic presentation of admitted operations. The semantic targets remain
/// separate from sampled poses. On interruption the coordinator freezes `sample`
/// into history at a NEW revision before starting another turn or applying a user edit.
public struct ExplanationPresentation: Equatable, Sendable {
    public private(set) var targetScene: ExplanationScene
    private var registry: ExplanationRegistry
    private struct Transition: Equatable, Sendable {
        var id: String
        var animation: ExplanationAnimation
        var from: ExplanationVector3
        var began: Double
    }
    private var transitions: [String: Transition] = [:]

    public init(scene: ExplanationScene, registry: ExplanationRegistry = .empty) throws {
        try ExplanationSceneReducer.validate(scene, registry: registry)
        targetScene = scene; self.registry = registry
    }

    public mutating func begin(_ event: ExplanationEvent, registry: ExplanationRegistry = .empty) throws {
        try ExplanationSceneReducer.validate(event)
        guard event.sessionID == targetScene.sessionID, event.sceneID == targetScene.sceneID else {
            throw ExplanationFailure.staleIdentity
        }
        guard event.baseRevision == targetScene.revision || event.revision == targetScene.revision else {
            throw ExplanationFailure.revisionConflict
        }
        targetScene = try ExplanationSceneReducer.restoring(targetScene, atRevision: event.revision, registry: registry)
        self.registry = registry
    }

    /// Atomic per cue, including overlapping animations. A replacement animation begins
    /// at the currently sampled pose rather than the previous animation's future target.
    public mutating func apply(_ admission: ExplanationCueAdmission, registry: ExplanationRegistry = .empty) throws {
        guard admission.event.cues.indices.contains(admission.cueIndex), admission.presentationTime.isFinite,
              admission.presentationTime >= 0 else { throw ExplanationFailure.invalid("presentation cue") }
        if let remaining = admission.remainingMediaDuration {
            guard remaining.isFinite, (0...300).contains(remaining) else { throw ExplanationFailure.invalid("presentation media bound") }
        }
        try ExplanationSceneReducer.validate(admission.event)
        guard admission.event.sessionID == targetScene.sessionID, admission.event.sceneID == targetScene.sceneID else {
            throw ExplanationFailure.staleIdentity
        }
        var next = self
        var pose = try sample(at: admission.presentationTime)
        // The whole cue is the graph transaction. Forward references within it
        // are valid; no intermediate graph is rendered or persisted.
        let final = try ExplanationSceneReducer.applyingOperations(admission.cue.operations, to: targetScene,
            resultingRevision: admission.event.revision, registry: registry)
        for operation in admission.cue.operations {
            switch operation {
            case .animate(let id, var animation):
                guard let object = pose.objects[id] else { throw ExplanationFailure.invalid("animation object missing") }
                // Clamp to measured remaining speech time. A final beat therefore
                // completes its admitted visual transitions before its real clock stops.
                if let remaining = admission.remainingMediaDuration { animation.duration = min(animation.duration, remaining) }
                let key = Self.key(id, animation.property)
                if animation.duration == 0 {
                    next.transitions.removeValue(forKey: key)
                    Self.set(animation.to, property: animation.property, object: &pose.objects[id]!)
                } else {
                    next.transitions[key] = .init(id: id, animation: animation, from: Self.value(object, animation.property),
                                                   began: admission.presentationTime)
                }
            case .create(let object), .connect(let object): pose.objects[object.id] = object
            case .move(let id, let position):
                pose.objects[id]?.transform.position = position
                next.transitions.removeValue(forKey: Self.key(id, .position))
            case .update(let id, let patch):
                if let transform = patch.transform {
                    pose.objects[id]?.transform = transform
                    for property in [ExplanationAnimation.Property.position, .rotation, .scale] {
                        next.transitions.removeValue(forKey: Self.key(id, property))
                    }
                }
                if let style = patch.style {
                    pose.objects[id]?.style = style
                    next.transitions.removeValue(forKey: Self.key(id, .opacity))
                }
            case .remove(let id):
                var removed: Set<String> = [id]
                for _ in 0..<pose.objects.count {
                    let children = pose.objects.values.filter { $0.parentID.map { removed.contains($0) } ?? false }.map(\.id)
                    let prior = removed.count; removed.formUnion(children)
                    if removed.count == prior { break }
                }
                for id in removed { pose.objects.removeValue(forKey: id) }
                next.transitions = next.transitions.filter { !removed.contains($0.value.id) }
            case .group(let id, let members):
                for member in members { pose.objects[member]?.parentID = id }
            case .clear: next.transitions.removeAll(); pose.objects.removeAll()
            default: break
            }
        }
        next.targetScene = final
        next.registry = registry
        next.transitions = next.transitions.filter { final.objects[$0.value.id] != nil }
        self = next
    }

    public func sample(at mediaTime: Double, reduceMotion: Bool = false) throws -> ExplanationScene {
        guard mediaTime.isFinite, mediaTime >= 0 else { throw ExplanationFailure.invalid("presentation time") }
        var scene = targetScene
        guard !reduceMotion else {
            // Semantic targets already contain admitted animation endpoints. A
            // static reveal=0 is intentional and must not be forced visible here.
            try ExplanationSceneReducer.validate(scene, registry: registry)
            return scene
        }
        for transition in transitions.values {
            guard var object = scene.objects[transition.id] else { continue }
            var t = min(1, max(0, (mediaTime - transition.began) / transition.animation.duration))
            if transition.animation.curve == .easeInOut { t = t * t * (3 - 2 * t) }
            let from = transition.from, to = transition.animation.to
            let value = ExplanationVector3(x: from.x + (to.x - from.x) * t,
                y: from.y + (to.y - from.y) * t, z: from.z + (to.z - from.z) * t)
            switch transition.animation.property {
            case .position: object.transform.position = value
            case .rotation: object.transform.rotation = value
            case .scale: object.transform.scale = value
            case .opacity: object.style.opacity = value.x
            case .strokeReveal: object.reveal = value.x
            }
            scene.objects[transition.id] = object
        }
        // Individually valid endpoints do not guarantee a bounded interpolated
        // parent/child composition. Never hand an unsafe sampled scene to native matrices.
        try ExplanationSceneReducer.validate(scene, registry: registry)
        return scene
    }

    public static func replay(from baseline: ExplanationScene, events: [ExplanationEvent], cues: [ExplanationCueAdmission], at mediaTime: Double,
                              reduceMotion: Bool = false, registry: ExplanationRegistry = .empty) throws -> ExplanationScene {
        guard events.count <= ExplanationLimits.events, cues.count <= ExplanationLimits.events * ExplanationLimits.cuesPerEvent else {
            throw ExplanationFailure.limitExceeded("presentation replay")
        }
        var presentation = try Self(scene: baseline, registry: registry)
        var previous = 0.0, nextCue = 0
        var priorSequence: Int?
        for event in events {
            if let priorSequence, event.sequence != priorSequence + 1 { throw ExplanationFailure.sequenceGap }
            try presentation.begin(event, registry: registry)
            priorSequence = event.sequence
            var cueIndex = 0
            while nextCue < cues.count, cues[nextCue].event.beatID == event.beatID {
                let cue = cues[nextCue]
                guard cue.event == event, cue.cueIndex == cueIndex,
                      cue.presentationTime >= previous, cue.presentationTime <= mediaTime else {
                    throw ExplanationFailure.invalid("replay cue order")
                }
                try presentation.apply(cue, registry: registry)
                previous = cue.presentationTime; nextCue += 1; cueIndex += 1
            }
            if event.beatID != events.last?.beatID, cueIndex != event.cues.count {
                throw ExplanationFailure.invalid("incomplete previous replay beat")
            }
        }
        guard nextCue == cues.count else { throw ExplanationFailure.invalid("orphan replay cue") }
        return try presentation.sample(at: mediaTime, reduceMotion: reduceMotion)
    }

    private static func set(_ value: ExplanationVector3, property: ExplanationAnimation.Property, object: inout ExplanationObject) {
        switch property {
        case .position: object.transform.position = value
        case .rotation: object.transform.rotation = value
        case .scale: object.transform.scale = value
        case .opacity: object.style.opacity = value.x
        case .strokeReveal: object.reveal = value.x
        }
    }
    private static func key(_ id: String, _ property: ExplanationAnimation.Property) -> String { id + "/" + property.rawValue }
    private static func value(_ object: ExplanationObject, _ property: ExplanationAnimation.Property) -> ExplanationVector3 {
        switch property {
        case .position: object.transform.position
        case .rotation: object.transform.rotation
        case .scale: object.transform.scale
        case .opacity: .init(x: object.style.opacity, y: 0)
        case .strokeReveal: .init(x: object.reveal, y: 0)
        }
    }
}

/// Incremental read-only replay. A display tick samples the cached transitions;
/// unchanged prefixes never run graph reducers again. A backwards seek, changed
/// event/cue prefix, or changed app resource authority rebuilds from the baseline.
/// Validation and updates are atomic: a malformed update cannot poison the cache.
public struct ExplanationReplayPresentation: Equatable, Sendable {
    private let baseline: ExplanationScene
    private var presentation: ExplanationPresentation
    private var registry: ExplanationRegistry
    private var events: [ExplanationEvent] = []
    private var cues: [ExplanationCueAdmission] = []
    private var counts: [Int] = []

    public init(scene: ExplanationScene, registry: ExplanationRegistry = .empty) throws {
        baseline = scene; self.registry = registry
        presentation = try .init(scene: scene, registry: registry)
    }

    public mutating func sample(events incomingEvents: [ExplanationEvent], cues incomingCues: [ExplanationCueAdmission],
                                at mediaTime: Double, reduceMotion: Bool = false,
                                registry incomingRegistry: ExplanationRegistry = .empty) throws -> ExplanationScene {
        guard mediaTime.isFinite, mediaTime >= 0,
              incomingEvents.count <= ExplanationLimits.events,
              incomingCues.count <= ExplanationLimits.events * ExplanationLimits.cuesPerEvent else {
            throw ExplanationFailure.invalid("replay update bounds")
        }
        let extendsPrefix = incomingRegistry == registry && incomingEvents.starts(with: events) && incomingCues.starts(with: cues)
        var next = extendsPrefix ? self : try Self(scene: baseline, registry: incomingRegistry)
        let priorEventCount = next.events.count
        var cueCursor = next.cues.count
        var previousTime = next.cues.last?.presentationTime ?? 0
        guard previousTime <= mediaTime else { throw ExplanationFailure.invalid("replay time precedes cues") }

        // The last cached beat may acquire more cues; all earlier beats are complete.
        for eventIndex in max(0, priorEventCount - 1)..<incomingEvents.count {
            let event = incomingEvents[eventIndex]
            if eventIndex >= priorEventCount {
                if let prior = next.events.last, event.sequence != prior.sequence + 1 { throw ExplanationFailure.sequenceGap }
                try next.presentation.begin(event, registry: incomingRegistry)
                next.events.append(event); next.counts.append(0)
            }
            while cueCursor < incomingCues.count, incomingCues[cueCursor].event.beatID == event.beatID {
                let cue = incomingCues[cueCursor]
                guard cue.event == event, cue.cueIndex == next.counts[eventIndex],
                      cue.presentationTime.isFinite, cue.presentationTime >= previousTime,
                      cue.presentationTime <= mediaTime else { throw ExplanationFailure.invalid("replay cue order") }
                try next.presentation.apply(cue, registry: incomingRegistry)
                next.cues.append(cue); next.counts[eventIndex] += 1
                previousTime = cue.presentationTime; cueCursor += 1
            }
            if eventIndex < incomingEvents.count - 1, next.counts[eventIndex] != event.cues.count {
                throw ExplanationFailure.invalid("incomplete previous replay beat")
            }
        }
        guard cueCursor == incomingCues.count else { throw ExplanationFailure.invalid("orphan replay cue") }
        let scene = try next.presentation.sample(at: mediaTime, reduceMotion: reduceMotion)
        self = next
        return scene
    }

    /// Use only after the coordinator has supplied every cue due at this media time.
    public func sample(at mediaTime: Double, reduceMotion: Bool = false) throws -> ExplanationScene {
        guard mediaTime >= (cues.last?.presentationTime ?? 0) else { throw ExplanationFailure.invalid("replay time precedes cues") }
        return try presentation.sample(at: mediaTime, reduceMotion: reduceMotion)
    }
}
