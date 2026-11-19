import Foundation

/// A plain copy of the part of a call window's Accessibility tree that naming needs. The app builds it (on the
/// main actor, with a node and time budget); everything that reads it is pure and tested here.
public final class MeetingAXNode: Sendable {
    public let role: String
    /// Title, description, value and help text, in that order, empty ones left out.
    public let texts: [String]
    /// DOM class names of a web node (Chromium exposes them), empty elsewhere.
    public let classes: [String]
    public let children: [MeetingAXNode]

    public init(role: String = "", texts: [String] = [], classes: [String] = [], children: [MeetingAXNode] = []) {
        self.role = role
        self.texts = texts
        self.classes = classes
        self.children = children
    }

    /// This node and everything below it, in reading order.
    public var subtree: [MeetingAXNode] { [self] + children.flatMap(\.subtree) }
}

/// Reads participant tiles and who is lit as the active speaker out of a call window's tree.
/// Generic signals work in every app (" is speaking", ", active speaker", "muted" and French). Meet and Slack
/// huddles also carry tile and active-speaker markers in their DOM class names, which give the whole roster.
public enum MeetingTileExtractor {
    private static let picturePrefixes = ["profile picture of ", "photo de profil de ", "photo de profil "]

    public static func participants(app: MeetingAppKind, root: MeetingAXNode) -> [MeetingParticipantState] {
        var order: [String] = []
        var merged: [String: MeetingParticipantState] = [:]
        func add(_ tile: MeetingParticipantState) {
            let key = MeetingSpeakerLabelParser.key(tile.name)
            if var existing = merged[key] {
                existing.isSpeaking = existing.isSpeaking || tile.isSpeaking
                existing.isMuted = existing.isMuted || tile.isMuted
                existing.isSelf = existing.isSelf || tile.isSelf
                // A tile that says someone is speaking is not muted.
                if existing.isSpeaking { existing.isMuted = false }
                merged[key] = existing
            } else {
                order.append(key)
                merged[key] = tile
            }
        }
        for node in root.subtree {
            for text in node.texts {
                guard let tile = MeetingSpeakerLabelParser.parse(text),
                      tile.isSpeaking || tile.isMuted || tile.isSelf else { continue }
                add(tile.state)
            }
        }
        switch app {
        case .meet:
            for tile in domTiles(root, marker: "video-frame", activeMarker: "video-frame--active", mutedMarker: nil) { add(tile) }
        case .slack:
            for tile in domTiles(root, marker: "huddle_peer_tile", activeMarker: "overlay--active_speaker",
                                 mutedMarker: "name_overlay--muted") { add(tile) }
        case .zoom, .teams, .other:
            break
        }
        return order.compactMap { merged[$0] }
    }

    private static func domTiles(
        _ root: MeetingAXNode, marker: String, activeMarker: String, mutedMarker: String?
    ) -> [MeetingParticipantState] {
        var tiles: [MeetingParticipantState] = []
        for node in root.subtree where node.classes.contains(where: { $0.contains(marker) }) {
            let inside = node.subtree
            let texts = inside.flatMap(\.texts)
            guard let name = texts.lazy.compactMap({ tileName($0) }).first else { continue }
            let signalled = texts.compactMap { MeetingSpeakerLabelParser.parse($0) }
            let speaking = inside.contains { $0.classes.contains { $0.contains(activeMarker) } }
                || signalled.contains { $0.isSpeaking }
            let muted = (mutedMarker.map { needle in inside.contains { $0.classes.contains { $0.contains(needle) } } } ?? false)
                || signalled.contains { $0.isMuted }
            let isSelf = signalled.contains { $0.isSelf }
            tiles.append(MeetingParticipantState(name: name, isSpeaking: speaking && !muted, isMuted: muted, isSelf: isSelf))
        }
        return tiles
    }

    /// The person's name in one piece of tile text, with "profile picture of" and role suffixes removed.
    static func tileName(_ text: String) -> String? {
        var body = text
        let lower = body.lowercased()
        for prefix in picturePrefixes where lower.hasPrefix(prefix) { body = String(body.dropFirst(prefix.count)) }
        return MeetingSpeakerLabelParser.parse(body)?.name
    }
}

/// One call window's reading.
public struct MeetingWindowReading: Equatable, Sendable {
    public var app: MeetingAppKind
    public var windowID: String
    public var participants: [MeetingParticipantState]

    public init(app: MeetingAppKind, windowID: String, participants: [MeetingParticipantState]) {
        self.app = app
        self.windowID = windowID
        self.participants = participants
    }
}

/// Decides what a set of window readings may be used for. Rule: no name when two meeting
/// windows are open, when the windows disagree about who is speaking, or when more than one call app is active.
public enum MeetingWindowArbiter {
    public static func observation(at time: TimeInterval, readings: [MeetingWindowReading]) -> MeetingSpeakerObservation? {
        let live = readings.filter { !$0.participants.isEmpty }
        guard let first = live.first else { return nil }
        if live.count == 1 {
            return MeetingSpeakerObservation(time: time, app: first.app, participants: first.participants)
        }
        // Several windows: usable as a roster, never for naming.
        return MeetingSpeakerObservation(time: time, app: first.app, participants: first.participants, isAmbiguous: true)
    }
}
