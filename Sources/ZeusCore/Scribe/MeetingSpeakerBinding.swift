import Foundation

/// One poll of the call window. `isAmbiguous` is set by the reader when the reading cannot be trusted for naming:
/// two meeting windows open, windows that disagree on who speaks, or more than one call app active.
public struct MeetingSpeakerObservation: Equatable, Sendable {
    public var time: TimeInterval
    public var app: MeetingAppKind
    public var participants: [MeetingParticipantState]
    public var isAmbiguous: Bool

    public init(time: TimeInterval, app: MeetingAppKind, participants: [MeetingParticipantState], isAmbiguous: Bool = false) {
        self.time = time
        self.app = app
        self.participants = participants
        self.isAmbiguous = isAmbiguous
    }

    public var rosterSize: Int { participants.count }
}

/// A stretch of time one participant's tile was lit as the active speaker.
public struct MeetingSpeakerSpan: Equatable, Sendable {
    public var name: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var length: TimeInterval { max(0, end - start) }
}

/// Folds polls into spans. A participant speaks from the first to the last poll that lit them; a gap longer than
/// `maxGap` closes the span. Muted tiles never light, the person at the keyboard never gets a span (the microphone
/// channel is theirs), and an ambiguous poll adds nothing.
public enum MeetingSpeakerSpans {
    public static let maxGap: TimeInterval = 1.5
    /// A poll shows the tile lit at one instant; it stands for this much time on each side.
    public static let pollHold: TimeInterval = 0.25

    public static func fold(
        _ observations: [MeetingSpeakerObservation], maxGap: TimeInterval = maxGap, hold: TimeInterval = pollHold
    ) -> [MeetingSpeakerSpan] {
        var open: [String: (name: String, start: TimeInterval, last: TimeInterval)] = [:]
        var done: [MeetingSpeakerSpan] = []
        for observation in observations.sorted(by: { $0.time < $1.time }) {
            guard !observation.isAmbiguous else { continue }
            let lit = observation.participants.filter { $0.isSpeaking && !$0.isMuted && !$0.isSelf }
            let litKeys = Set(lit.map { MeetingSpeakerLabelParser.key($0.name) })
            for (key, span) in open where !litKeys.contains(key) && observation.time - span.last > maxGap {
                done.append(MeetingSpeakerSpan(name: span.name, start: span.start - hold, end: span.last + hold))
                open[key] = nil
            }
            for tile in lit {
                let key = MeetingSpeakerLabelParser.key(tile.name)
                if let span = open[key] {
                    if observation.time - span.last > maxGap {
                        done.append(MeetingSpeakerSpan(name: span.name, start: span.start - hold, end: span.last + hold))
                        open[key] = (tile.name, observation.time, observation.time)
                    } else {
                        open[key] = (span.name, span.start, observation.time)
                    }
                } else {
                    open[key] = (tile.name, observation.time, observation.time)
                }
            }
        }
        for span in open.values {
            done.append(MeetingSpeakerSpan(name: span.name, start: span.start - hold, end: span.last + hold))
        }
        return done.sorted { $0.start != $1.start ? $0.start < $1.start : $0.name < $1.name }
    }

    /// Time ranges in which polls were ambiguous; each runs from one ambiguous poll to the next poll.
    public static func ambiguousRanges(_ observations: [MeetingSpeakerObservation], pollGap: TimeInterval = 1.5) -> [ClosedRange<TimeInterval>] {
        let sorted = observations.sorted { $0.time < $1.time }
        var ranges: [ClosedRange<TimeInterval>] = []
        for (index, observation) in sorted.enumerated() where observation.isAmbiguous {
            let next = index + 1 < sorted.count ? sorted[index + 1].time : observation.time + pollGap
            ranges.append(observation.time...max(observation.time, min(next, observation.time + pollGap)))
        }
        return ranges
    }
}

/// A speech turn of one diarizer cluster on the system channel.
public struct MeetingClusterTurn: Equatable, Sendable {
    public var cluster: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(cluster: String, start: TimeInterval, end: TimeInterval) {
        self.cluster = cluster
        self.start = start
        self.end = end
    }
}

/// How much of each cluster's talk each participant's lit tile covered.
public enum MeetingSpeakerVotes {
    public struct Tally: Equatable, Sendable {
        public var name: String
        /// Overlap seconds, each span weighted by how long it lasted (a flicker counts for less).
        public var seconds: Double
    }

    public static let tolerance: TimeInterval = 0.4
    /// A span this long or longer counts in full.
    public static let fullWeightSpan: TimeInterval = 1.0

    /// `cluster -> nameKey -> tally`. A turn that overlaps an ambiguous poll is left out whole.
    public static func tally(
        turns: [MeetingClusterTurn],
        spans: [MeetingSpeakerSpan],
        ambiguous: [ClosedRange<TimeInterval>] = [],
        tolerance: TimeInterval = tolerance
    ) -> [String: [String: Tally]] {
        var result: [String: [String: Tally]] = [:]
        for turn in turns where turn.end > turn.start {
            if ambiguous.contains(where: { $0.lowerBound < turn.end && $0.upperBound > turn.start }) { continue }
            for span in spans {
                let low = max(turn.start, span.start - tolerance)
                let high = min(turn.end, span.end + tolerance)
                let overlap = high - low
                guard overlap > 0 else { continue }
                let weight = min(1, span.length / fullWeightSpan)
                let key = MeetingSpeakerLabelParser.key(span.name)
                var row = result[turn.cluster, default: [:]]
                var entry = row[key] ?? Tally(name: span.name, seconds: 0)
                entry.seconds += overlap * max(weight, 0.25)
                row[key] = entry
                result[turn.cluster] = row
            }
        }
        return result
    }
}

/// A name the call window earned for a cluster.
public struct MeetingClusterBinding: Equatable, Sendable {
    public var cluster: String
    public var name: String
    public var confidence: Double
    public var seconds: Double
}

/// The per-cluster timeline winner and the gate that decides whether it is allowed to name a voice.
/// A name binds only when the audio and the tile agree: enough overlap, a clear majority, a clear lead over the
/// runner-up, and the match is mutual (the cluster is also that person's best cluster). Pure.
public struct MeetingSpeakerBinder: Equatable, Sendable {
    public var minimumSeconds: Double = 4
    public var minimumShare: Double = 0.6
    public var minimumLead: Double = 2
    /// Roster tiles in the window. 1 means nobody else is on the call: nothing to bind.
    public var minimumRoster = 2

    public init() {}

    public func bindings(
        observations: [MeetingSpeakerObservation], turns: [MeetingClusterTurn], excluding taken: Set<String> = []
    ) -> [MeetingClusterBinding] {
        guard (observations.map(\.rosterSize).max() ?? 0) >= minimumRoster else { return [] }
        let spans = MeetingSpeakerSpans.fold(observations)
        let tally = MeetingSpeakerVotes.tally(
            turns: turns, spans: spans, ambiguous: MeetingSpeakerSpans.ambiguousRanges(observations)
        )
        // Each person's best cluster, for the mutual check.
        var bestClusterOfName: [String: (cluster: String, seconds: Double)] = [:]
        for (cluster, row) in tally {
            for (key, entry) in row where entry.seconds > (bestClusterOfName[key]?.seconds ?? 0)
                || (entry.seconds == bestClusterOfName[key]?.seconds && cluster < (bestClusterOfName[key]?.cluster ?? "~")) {
                bestClusterOfName[key] = (cluster, entry.seconds)
            }
        }
        var found: [MeetingClusterBinding] = []
        for (cluster, row) in tally {
            let ranked = row.sorted { $0.value.seconds != $1.value.seconds ? $0.value.seconds > $1.value.seconds : $0.key < $1.key }
            guard let top = ranked.first, !taken.contains(top.key) else { continue }
            let total = row.values.reduce(0) { $0 + $1.seconds }
            let second = ranked.dropFirst().first?.value.seconds ?? 0
            let share = total > 0 ? top.value.seconds / total : 0
            guard top.value.seconds >= minimumSeconds, share >= minimumShare,
                  second == 0 || top.value.seconds >= minimumLead * second,
                  bestClusterOfName[top.key]?.cluster == cluster else { continue }
            let lead = second == 0 ? 1 : min(1, 1 - second / top.value.seconds)
            let evidence = min(1, top.value.seconds / 12)
            let confidence = min(1, 0.5 * share + 0.3 * lead + 0.2 * evidence)
            found.append(MeetingClusterBinding(cluster: cluster, name: top.value.name, confidence: confidence, seconds: top.value.seconds))
        }
        return found.sorted { $0.cluster < $1.cluster }
    }
}
