import Foundation

// MARK: - Live naming

/// What the live page needs to say about whoever spoke last.
public struct ScribeNowSpeaking: Equatable, Sendable {
    public let speaker: ScribeSpeaker
    /// The best name known right now, or "Identifying this speaker…" while there is none.
    public let displayName: String
    public let isResolved: Bool
    public let source: ScribeNameSource?
}

/// Live call-window naming for one recording: remembers which diarizer cluster each line came from, folds the
/// window polls, and names clusters when the audio and the tile agree. Names apply retroactively to the lines
/// already shown. Pure and deterministic; the controller feeds it and relabels its transcript from the result.
public struct ScribeLiveNaming: Equatable, Sendable {
    public static let identifying = "Identifying this speaker\u{2026}"

    public private(set) var book = ScribeSpeakerBook()
    public private(set) var observations: [MeetingSpeakerObservation] = []
    public var binder = MeetingSpeakerBinder()
    private var clusterByID: [String: String] = [:]
    private var turnByID: [String: MeetingClusterTurn] = [:]
    private var lastEvaluatedCount = 0
    /// Polls kept: about an hour at two a second.
    public static let maxObservations = 7_200

    public init() {}

    /// A cluster the diarizer calls "Speaker N" (not "You", not a saved voice's own name).
    public static func isAnonymous(_ speaker: ScribeSpeaker) -> Bool {
        if case .participant(let label) = speaker { return anonymousLabel(label) }
        return false
    }

    static func anonymousLabel(_ label: String) -> Bool {
        label == "Speaker" || (label.hasPrefix("Speaker ") && Int(label.dropFirst("Speaker ".count)) != nil)
    }

    /// The segment as the page should show it: a cluster with a name wears the name. The cluster is remembered
    /// so a later name can relabel this line too.
    public mutating func ingest(_ segment: ScribeTranscriptSegment) -> ScribeTranscriptSegment {
        guard segment.id.hasPrefix("sys-"), case .participant(let raw) = segment.speaker, Self.anonymousLabel(raw) else {
            return segment
        }
        clusterByID[segment.id] = raw
        if segment.isFinal, segment.end > segment.start {
            turnByID[segment.id] = MeetingClusterTurn(cluster: raw, start: segment.start, end: segment.end)
        }
        guard let identity = book.identity(forOriginal: raw) else { return segment }
        var named = segment
        named.speaker = .participant(identity.name)
        return named
    }

    public mutating func observe(_ observation: MeetingSpeakerObservation) {
        observations.append(observation)
        if observations.count > Self.maxObservations { observations.removeFirst(observations.count - Self.maxObservations) }
    }

    /// The names that changed since the last call: `(originalLabel, name)`. Cheap when nothing new arrived.
    public mutating func evaluate(force: Bool = false) -> [ScribeSpeakerIdentity] {
        guard force || observations.count != lastEvaluatedCount else { return [] }
        lastEvaluatedCount = observations.count
        let before = book.identities
        let bindings = binder.bindings(
            observations: observations, turns: Array(turnByID.values), excluding: book.confirmedNameKeys
        )
        for binding in bindings {
            book.bindAutomatic(label: binding.cluster, name: binding.name, source: .callWindow, confidence: binding.confidence)
        }
        return book.identities.filter { identity in !before.contains(identity) }
    }

    /// The diarizer's final read moved some turns to other voices (segment id to "Speaker N"). Every automatic
    /// name is dropped and worked out again from the same window evidence on the corrected voices.
    public mutating func relabelClusters(_ labels: [String: String]) {
        for (id, label) in labels where clusterByID[id] != nil {
            clusterByID[id] = label
            if var turn = turnByID[id] {
                turn.cluster = label
                turnByID[id] = turn
            }
        }
        book.removeUnconfirmed()
    }

    /// The diarizer's own label for a line, whatever name it wears now.
    public func rawSpeaker(segmentID: String) -> ScribeSpeaker? {
        clusterByID[segmentID].map { ScribeSpeaker.participant($0) }
    }

    /// The person typed a name for a cluster while recording.
    public mutating func setManual(label: String, name: String) { book.setConfirmed(label: label, name: name) }

    /// The speaker to show for a transcript speaker, after retroactive naming.
    public func displayed(_ speaker: ScribeSpeaker, segmentID: String) -> ScribeSpeaker {
        guard let raw = clusterByID[segmentID], let identity = book.identity(forOriginal: raw) else { return speaker }
        return .participant(identity.name)
    }

    /// The live "Now speaking" claim for the newest line.
    public func nowSpeaking(_ segment: ScribeTranscriptSegment?) -> ScribeNowSpeaking? {
        guard let segment else { return nil }
        let speaker = displayed(segment.speaker, segmentID: segment.id)
        switch speaker {
        case .you:
            return ScribeNowSpeaking(speaker: .you, displayName: "You", isResolved: true, source: nil)
        case .unknown:
            return ScribeNowSpeaking(speaker: .unknown, displayName: Self.identifying, isResolved: false, source: nil)
        case .participant(let label):
            if Self.anonymousLabel(label) {
                return ScribeNowSpeaking(speaker: speaker, displayName: Self.identifying, isResolved: false, source: nil)
            }
            let identity = book.identity(named: label)
            return ScribeNowSpeaking(speaker: speaker, displayName: label, isResolved: true, source: identity?.source)
        }
    }
}
