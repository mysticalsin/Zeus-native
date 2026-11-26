import Foundation

/// Which notch cue an earbud overlay must not cover.
///
/// These are the eight cues `show` treats as essential, plus the permission cue.
public enum EarbudsProtectedCue: Equatable, Sendable, CaseIterable {
    case hint
    case usage
    case focus
    case keepAwake
    case dictation
    case volume
    case brightness
    case keyboardLight
    case permission
}

/// What is already in the notch slot. `other` is any cue that is not protected and is not an earbud cue.
public enum EarbudsCueOccupant: Equatable, Sendable {
    case none
    case other
    case protected(EarbudsProtectedCue)
    case earbuds(id: String, name: String, connected: Bool)
}

/// A request to put an earbud cue in the notch. The printed form keeps the name and the device id out.
public struct EarbudsCueShow: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Kind: Equatable, Sendable {
        case connected
        case disconnected
        case levels
    }

    public var id: String
    public var name: String
    public var kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    public var description: String { "earbuds" }

    public var debugDescription: String { "earbuds" }
}

/// Whether the Canopy earbud overlay may take the notch slot.
///
/// A connect or a disconnect may replace an ordinary cue. A levels update stays on the connected
/// cue of the same device id. A refusal is dropped. Nothing is queued.
public enum EarbudsCuePolicy {
    public static let connectedDuration: TimeInterval = 4
    public static let disconnectedDuration: TimeInterval = 3

    public static func duration(_ kind: EarbudsCueShow.Kind) -> TimeInterval {
        switch kind {
        case .connected, .levels: connectedDuration
        case .disconnected: disconnectedDuration
        }
    }

    public static func mayShow(_ cue: EarbudsCueShow, over current: EarbudsCueOccupant) -> Bool {
        let id = cue.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        if case .protected = current { return false }
        switch cue.kind {
        case .levels:
            guard case .earbuds(let currentID, _, true) = current else { return false }
            return currentID == id
        case .connected, .disconnected:
            return true
        }
    }
}
