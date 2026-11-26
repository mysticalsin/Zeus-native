import Foundation

/// Decides how a pointing explanation recovers when the output device changes,
/// the network drops, or the selected model is unavailable.
///
/// The caller feeds events. This value does not open a connection, sleep, or
/// read a system clock. An output-device change stops the current beat and
/// asks for a new player at the beat start. Ticks apply only while a player
/// is actually playing, so a missing device cannot keep a silent clock.
/// A network loss or an unavailable model is a visible failure: the committed
/// scene stays, and an uncommitted partial is dropped.
///
/// The network and model sentences use the same wording as `PointingFailureKind`.
public struct PointingFailureRecovery: Equatable, Sendable {
    /// Playback resumes here after an output-device change. Never the old elapsed time.
    public static let beatStart: Double = 0
    public static let outputDeviceNotice = "Sound output changed. This sentence is starting again from the beginning."

    public static func networkNotice(provider: String) -> String {
        "No connection to \(provider). Check your network and try again."
    }

    public static func modelNotice(provider: String) -> String {
        "\(provider) does not offer the selected model. Pick another model in Settings."
    }

    public struct Scene: Equatable, Sendable {
        public let id: String
        public let generation: Int
        public let objectIDs: [String]

        public init(id: String, generation: Int, objectIDs: [String]) {
            self.id = id
            self.generation = generation
            self.objectIDs = objectIDs
        }
    }

    public struct Beat: Equatable, Sendable {
        public let id: String
        public let index: Int

        public init(id: String, index: Int) {
            self.id = id
            self.index = index
        }
    }

    public enum Failure: Equatable, Sendable {
        case network
        case modelUnavailable
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case playing(beat: Beat, deviceID: String, elapsed: Double)
        case awaitingRebuild(beat: Beat, deviceID: String)
        case failed(Failure)
    }

    public enum Notice: Equatable, Sendable {
        case none
        case outputDeviceChanged(String)
        case network(String)
        case modelUnavailable(String)
    }

    public enum Order: Equatable, Sendable {
        case none
        case stop
        /// Build a new player and start `beat` at `at`. `at` is the beat start.
        case rebuildAndResume(beat: Beat, deviceID: String, at: Double)
    }

    public enum Outcome: Equatable, Sendable {
        case accepted
        case ignored
        case rejectedEmpty
        case rejectedClock
        case rejectedFailed
        case rejectedSameDevice
        case rejectedScene
    }

    public struct Decision: Equatable, Sendable {
        public let outcome: Outcome
        public let phase: Phase
        public let order: Order
        public let notice: Notice
        public let committedScene: Scene?
        public let partialObjectIDs: [String]

        public init(outcome: Outcome, phase: Phase, order: Order, notice: Notice, committedScene: Scene?, partialObjectIDs: [String]) {
            self.outcome = outcome
            self.phase = phase
            self.order = order
            self.notice = notice
            self.committedScene = committedScene
            self.partialObjectIDs = partialObjectIDs
        }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var committedScene: Scene?
    public private(set) var partialObjectIDs: [String] = []
    public private(set) var deviceID: String?

    public init() {}

    /// Stores a scene that has already been applied. A later failure keeps this value.
    /// A committed scene replaces any staged partial. A blank id, a blank object id,
    /// or a generation older than the one already stored is refused.
    public mutating func commit(_ scene: Scene) -> Decision {
        if case .failed = phase { return decision(outcome: .rejectedFailed) }
        guard let id = normalized(scene.id) else { return decision(outcome: .rejectedEmpty) }
        guard scene.generation >= 0 else { return decision(outcome: .rejectedScene) }
        guard let objectIDs = normalizedIDs(scene.objectIDs, allowEmpty: true) else {
            return decision(outcome: .rejectedEmpty)
        }
        if let committedScene, scene.generation < committedScene.generation {
            return decision(outcome: .rejectedScene)
        }
        committedScene = Scene(id: id, generation: scene.generation, objectIDs: objectIDs)
        partialObjectIDs = []
        return decision(outcome: .accepted)
    }

    /// An in-flight cue that is not yet part of the committed scene.
    public mutating func stagePartial(objectIDs: [String]) -> Decision {
        if case .failed = phase { return decision(outcome: .rejectedFailed) }
        guard let ids = normalizedIDs(objectIDs, allowEmpty: false) else {
            return decision(outcome: .rejectedEmpty)
        }
        partialObjectIDs = ids
        return decision(outcome: .accepted)
    }

    /// Starts a beat on `deviceID`. Elapsed begins at the beat start.
    /// The same beat id does not reset the clock. A beat is not swapped while a rebuild is pending.
    public mutating func beginBeat(_ beat: Beat, deviceID: String) -> Decision {
        guard let id = normalized(beat.id), let device = normalized(deviceID) else {
            return decision(outcome: .rejectedEmpty)
        }
        guard beat.index >= 0 else { return decision(outcome: .rejectedScene) }
        let clean = Beat(id: id, index: beat.index)
        switch phase {
        case .failed:
            return decision(outcome: .rejectedFailed)
        case .awaitingRebuild:
            return decision(outcome: .ignored)
        case .playing(let current, _, _):
            if current.id == clean.id { return decision(outcome: .ignored) }
            phase = .playing(beat: clean, deviceID: device, elapsed: Self.beatStart)
            self.deviceID = device
            return decision(outcome: .accepted)
        case .idle:
            phase = .playing(beat: clean, deviceID: device, elapsed: Self.beatStart)
            self.deviceID = device
            return decision(outcome: .accepted)
        }
    }

    /// Moves the live clock only while a player is actually playing.
    /// A missing, backwards, or non-finite elapsed does not move it.
    public mutating func tick(elapsed: Double) -> Decision {
        guard case .playing(let beat, let device, let current) = phase else {
            return decision(outcome: .ignored)
        }
        guard elapsed.isFinite, elapsed >= Self.beatStart, elapsed >= current else {
            return decision(outcome: .rejectedClock)
        }
        guard elapsed != current else { return decision(outcome: .ignored) }
        phase = .playing(beat: beat, deviceID: device, elapsed: elapsed)
        return decision(outcome: .accepted)
    }

    /// The output device changed. Stop the current beat and resume it from the start on `deviceID`.
    public mutating func outputDeviceChanged(to deviceID: String) -> Decision {
        if case .failed = phase { return decision(outcome: .rejectedFailed) }
        guard let device = normalized(deviceID) else { return decision(outcome: .rejectedEmpty) }
        switch phase {
        case .idle:
            self.deviceID = device
            return decision(outcome: .accepted)
        case .playing(let beat, let current, _):
            guard current != device else { return decision(outcome: .rejectedSameDevice) }
            return scheduleRebuild(beat: beat, deviceID: device)
        case .awaitingRebuild(let beat, let pending):
            guard pending != device else { return decision(outcome: .ignored) }
            return scheduleRebuild(beat: beat, deviceID: device)
        case .failed:
            return decision(outcome: .rejectedFailed)
        }
    }

    /// The rebuilt player is ready. Playback is at the beat start on the pending device.
    public mutating func playerRebuilt() -> Decision {
        guard case .awaitingRebuild(let beat, let device) = phase else {
            return decision(outcome: .ignored)
        }
        phase = .playing(beat: beat, deviceID: device, elapsed: Self.beatStart)
        deviceID = device
        return decision(outcome: .accepted)
    }

    public mutating func networkLost(provider: String) -> Decision {
        fail(.network, provider: provider) { .network(Self.networkNotice(provider: $0)) }
    }

    public mutating func modelUnavailable(provider: String) -> Decision {
        fail(.modelUnavailable, provider: provider) { .modelUnavailable(Self.modelNotice(provider: $0)) }
    }

    private mutating func scheduleRebuild(beat: Beat, deviceID: String) -> Decision {
        phase = .awaitingRebuild(beat: beat, deviceID: deviceID)
        self.deviceID = deviceID
        return decision(
            outcome: .accepted,
            order: .rebuildAndResume(beat: beat, deviceID: deviceID, at: Self.beatStart),
            notice: .outputDeviceChanged(Self.outputDeviceNotice)
        )
    }

    private mutating func fail(_ failure: Failure, provider: String, notice: (String) -> Notice) -> Decision {
        if case .failed = phase { return decision(outcome: .ignored) }
        guard let name = normalized(provider) else { return decision(outcome: .rejectedEmpty) }
        let stop = isAudible
        phase = .failed(failure)
        partialObjectIDs = []
        return decision(outcome: .accepted, order: stop ? .stop : .none, notice: notice(name))
    }

    private var isAudible: Bool {
        switch phase {
        case .playing, .awaitingRebuild: return true
        case .idle, .failed: return false
        }
    }

    private func decision(outcome: Outcome, order: Order = .none, notice: Notice = .none) -> Decision {
        Decision(
            outcome: outcome,
            phase: phase,
            order: order,
            notice: notice,
            committedScene: committedScene,
            partialObjectIDs: partialObjectIDs
        )
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedIDs(_ ids: [String], allowEmpty: Bool) -> [String]? {
        if ids.isEmpty { return allowEmpty ? [] : nil }
        var trimmed: [String] = []
        trimmed.reserveCapacity(ids.count)
        for id in ids {
            guard let clean = normalized(id) else { return nil }
            trimmed.append(clean)
        }
        return trimmed
    }
}
