import Foundation

/// The second look at a finished meeting. Live labelling decides each turn as it arrives, with only the voices
/// heard so far; once the transcript is complete every turn's voice is clustered together (average-linkage
/// agglomerative, the same thresholds as the live pass) and turns the live pass split or merged are relabelled.
/// Live labels stay on screen during the call; the recap uses the corrected ones. Pure and deterministic.
///
/// Rules: the microphone and system audio never merge; the label a cluster keeps is the live label with the most
/// talk time in it; when two clusters would keep the same label the larger keeps it and the other becomes a new
/// "Speaker N"; turns without an embedding follow the label their live speaker ended up with.
public enum ScribeSpeakerCorrection {
    /// More turns than this and the pass is skipped (the live labels stand): the clustering is quadratic.
    public static let maxTurns = 600

    public static func corrected(
        segments: [ScribeTranscriptSegment],
        turns: [ScribeTurnEmbedding],
        handBuiltThreshold: Float = ScribeVoiceEmbedding.defaultThreshold(for: .handBuilt),
        wespeakerThreshold: Float = ScribeVoiceEmbedding.defaultThreshold(for: .wespeaker)
    ) -> [ScribeTranscriptSegment] {
        let turnByID = Dictionary(turns.map { ($0.segmentID, $0) }, uniquingKeysWith: { first, _ in first })
        // Turns that still have a segment in the transcript, in transcript order, one per segment.
        var seen: Set<String> = []
        var usable: [(turn: ScribeTurnEmbedding, live: ScribeSpeaker)] = []
        for segment in segments {
            guard seen.insert(segment.id).inserted, let turn = turnByID[segment.id] else { continue }
            usable.append((turn, segment.speaker))
        }
        guard usable.count >= 2, usable.count <= maxTurns else { return segments }

        // Cluster each (source, kind) group on its own.
        struct GroupKey: Hashable { let source: ScribeAudioSource; let kind: ScribeEmbeddingKind }
        var groups: [GroupKey: [Int]] = [:]
        var groupOrder: [GroupKey] = []
        for (index, item) in usable.enumerated() {
            let key = GroupKey(source: item.turn.source, kind: item.turn.embedding.kind)
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append(index)
        }
        var clusters: [[Int]] = []
        for key in groupOrder {
            let limit = key.kind == .handBuilt ? handBuiltThreshold : wespeakerThreshold
            clusters += averageLinkage(indices: groups[key] ?? [], limit: limit) { usable[$0].turn.embedding }
        }

        // Which label each cluster keeps, largest cluster first.
        func talk(_ index: Int) -> TimeInterval { max(usable[index].turn.duration, 0.001) }
        let ordered = clusters.sorted { lhs, rhs in
            let l = lhs.reduce(0) { $0 + talk($1) }
            let r = rhs.reduce(0) { $0 + talk($1) }
            return l != r ? l > r : (lhs.min() ?? 0) < (rhs.min() ?? 0)
        }
        var claimed: Set<ScribeSpeaker> = []
        var nextNumber = nextSpeakerNumber(in: segments)
        var turnLabel: [Int: ScribeSpeaker] = [:]
        for cluster in ordered {
            var votes: [ScribeSpeaker: TimeInterval] = [:]
            var firstSeen: [ScribeSpeaker: Int] = [:]
            for index in cluster {
                votes[usable[index].live, default: 0] += talk(index)
                if firstSeen[usable[index].live] == nil { firstSeen[usable[index].live] = index }
            }
            let ranked = votes.keys.sorted { lhs, rhs in
                votes[lhs] != votes[rhs] ? votes[lhs]! > votes[rhs]! : firstSeen[lhs]! < firstSeen[rhs]!
            }
            let label: ScribeSpeaker
            if let free = ranked.first(where: { !claimed.contains($0) }) {
                label = free
            } else {
                label = .participant("Speaker \(nextNumber)")
                nextNumber += 1
            }
            claimed.insert(label)
            for index in cluster { turnLabel[index] = label }
        }

        // A live speaker's turns without an embedding follow where most of its embedded talk went.
        var talkToLabel: [ScribeSpeaker: [ScribeSpeaker: TimeInterval]] = [:]
        for index in usable.indices {
            guard let label = turnLabel[index] else { continue }
            talkToLabel[usable[index].live, default: [:]][label, default: 0] += talk(index)
        }
        let follow: [ScribeSpeaker: ScribeSpeaker] = talkToLabel.compactMapValues { options in
            options.max { lhs, rhs in lhs.value != rhs.value ? lhs.value < rhs.value : "\(lhs.key)" > "\(rhs.key)" }?.key
        }
        var labelByID: [String: ScribeSpeaker] = [:]
        for (index, item) in usable.enumerated() { labelByID[item.turn.segmentID] = turnLabel[index] }

        return segments.map { segment in
            let label = labelByID[segment.id] ?? follow[segment.speaker]
            guard let label, label != segment.speaker else { return segment }
            var changed = segment
            changed.speaker = label
            return changed
        }
    }

    /// Average-linkage agglomerative clustering: merge the two closest clusters while their mean pairwise
    /// distance is within `limit`. Returns clusters as lists of the given indices, each in ascending order.
    public static func averageLinkage(
        indices: [Int], limit: Float, embedding: (Int) -> ScribeVoiceEmbedding
    ) -> [[Int]] {
        let count = indices.count
        guard count > 1 else { return indices.map { [$0] } }
        let items = indices.map(embedding)
        // Pairwise distances; merged clusters keep the lower slot and the other is retired.
        var distance = [[Float]](repeating: [Float](repeating: 0, count: count), count: count)
        for a in 0..<count {
            for b in (a + 1)..<count {
                let value = items[a].distance(to: items[b])
                distance[a][b] = value
                distance[b][a] = value
            }
        }
        var members: [[Int]] = indices.map { [$0] }
        var alive = [Bool](repeating: true, count: count)
        while true {
            var closest: (a: Int, b: Int, value: Float)?
            for a in 0..<count where alive[a] {
                for b in (a + 1)..<count where alive[b] {
                    if closest == nil || distance[a][b] < closest!.value { closest = (a, b, distance[a][b]) }
                }
            }
            guard let best = closest, best.value <= limit else { break }
            let sizeA = Float(members[best.a].count)
            let sizeB = Float(members[best.b].count)
            for other in 0..<count where alive[other] && other != best.a && other != best.b {
                let merged = (sizeA * distance[best.a][other] + sizeB * distance[best.b][other]) / (sizeA + sizeB)
                distance[best.a][other] = merged
                distance[other][best.a] = merged
            }
            members[best.a] = (members[best.a] + members[best.b]).sorted()
            alive[best.b] = false
        }
        return (0..<count).filter { alive[$0] }.map { members[$0] }
    }

    /// One more than the highest "Speaker N" in use, so a new label never repeats an old one.
    private static func nextSpeakerNumber(in segments: [ScribeTranscriptSegment]) -> Int {
        var highest = 0
        for segment in segments {
            guard case .participant(let label) = segment.speaker, label.hasPrefix("Speaker "),
                  let number = Int(label.dropFirst("Speaker ".count)) else { continue }
            highest = max(highest, number)
        }
        return highest + 1
    }
}
