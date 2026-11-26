import Foundation

/// The desktop card's beat share and linger clock.
///
/// Phase 4 card beats (`docs/POINTING-ASSISTANT-PLAN.md`). A beat contributes
/// the objects it creates or connects outside capture space. The next admitted
/// beat replaces that set. The caption is the speech text unchanged. After a
/// normal finish, a visible card lingers 25 seconds. Cancel closes it at once.
/// A card the owner closed stays closed until the next turn. This type does not
/// draw, does not read the screen, and does not schedule work.
public enum ExplanationCardBeats {
    /// `ExplanationDesktopCard.beginLinger` default, in seconds.
    public static let lingerSeconds = 25.0
    /// `ExplanationLimits.speech`, counted in UTF-8 bytes.
    public static let speechByteLimit = 1600
    /// `ExplanationSceneReducer.identifier`, counted in UTF-8 bytes.
    public static let identifierByteLimit = 64
    /// `ExplanationLimits.events`.
    public static let maxBeats = 64

    public enum Space: String, Equatable, Sendable {
        case canvas, world, capture
    }

    /// Create and connect add an id when the space is not capture. Every other
    /// operation is `other` and adds nothing, even when it names an id.
    public enum Mark: Equatable, Sendable {
        case create(id: String, space: Space)
        case connect(id: String, space: Space)
        case other(id: String)
    }

    public struct Beat: Equatable, Sendable {
        public var id: String
        public var speech: String
        public var marks: [Mark]

        public init(id: String, speech: String, marks: [Mark] = []) {
            self.id = id
            self.speech = speech
            self.marks = marks
        }
    }

    public struct Share: Equatable, Sendable {
        public var beatID: String
        public var caption: String
        public var objectIDs: Set<String>

        public init(beatID: String, caption: String, objectIDs: Set<String>) {
            self.beatID = beatID
            self.caption = caption
            self.objectIDs = objectIDs
        }
    }

    public enum Phase: Equatable, Sendable {
        case open
        case lingering
        case ended
        case dismissed
    }

    public enum Refusal: Equatable, Sendable {
        case identifier
        case speech
        case duplicate
        case finished
        case dismissed
        case budget
    }

    public enum Outcome: Equatable, Sendable {
        case shown(Share)
        case refused(Refusal)
    }

    public enum Tick: Equatable, Sendable {
        case advanced(remaining: Double)
        case ended
        case refused
        case idle
    }

    /// Ids a beat adds to the card. Capture-space creates and connects are left
    /// out. `other` is left out. A repeated id is stored once. An empty id is
    /// kept when a non-capture create or connect carries it.
    public static func objectIDs(in marks: [Mark]) -> Set<String> {
        var ids = Set<String>()
        for mark in marks {
            switch mark {
            case .create(let id, let space), .connect(let id, let space):
                if space != .capture { ids.insert(id) }
            case .other:
                break
            }
        }
        return ids
    }

    public struct Turn: Equatable, Sendable {
        public private(set) var phase: Phase
        public private(set) var share: Share?
        public private(set) var admitted: [String]
        public private(set) var lingerElapsed: Double

        public init() {
            phase = .open
            share = nil
            admitted = []
            lingerElapsed = 0
        }

        /// Checks run in order: phase, identifier, speech, duplicate, budget.
        /// A refusal leaves the turn unchanged. A shown beat replaces `share`.
        public mutating func admit(_ beat: Beat) -> Outcome {
            if phase == .dismissed { return .refused(.dismissed) }
            if phase != .open { return .refused(.finished) }
            if Self.identifierRefusal(beat.id) { return .refused(.identifier) }
            if Self.speechRefusal(beat.speech) { return .refused(.speech) }
            if admitted.contains(beat.id) { return .refused(.duplicate) }
            if admitted.count >= ExplanationCardBeats.maxBeats { return .refused(.budget) }
            admitted.append(beat.id)
            let share = Share(beatID: beat.id, caption: beat.speech,
                              objectIDs: ExplanationCardBeats.objectIDs(in: beat.marks))
            self.share = share
            return .shown(share)
        }

        /// Linger starts only from an open turn that has a share and a visible card.
        /// Any other call leaves the clock where it is.
        @discardableResult
        public mutating func finish(visible: Bool) -> Phase {
            guard phase == .open else { return phase }
            if visible, share != nil {
                phase = .lingering
                lingerElapsed = 0
            } else {
                phase = .ended
                share = nil
                lingerElapsed = 0
            }
            return phase
        }

        /// Stop or failure. An owner-dismissed card stays dismissed.
        public mutating func cancel() {
            guard phase != .dismissed else { return }
            phase = .ended
            share = nil
            lingerElapsed = 0
        }

        public mutating func dismiss() {
            phase = .dismissed
            share = nil
            lingerElapsed = 0
        }

        /// The next pointing turn. Clears a dismiss, a linger, and the share.
        public mutating func begin() {
            phase = .open
            share = nil
            admitted = []
            lingerElapsed = 0
        }

        /// Moves the linger clock. A non-finite or negative step is refused.
        /// Time is applied only while lingering. Reaching 25 seconds ends the card.
        public mutating func tick(_ seconds: Double) -> Tick {
            guard phase == .lingering else { return .idle }
            guard seconds.isFinite, seconds >= 0 else { return .refused }
            let sum = lingerElapsed + seconds
            if !sum.isFinite || sum >= ExplanationCardBeats.lingerSeconds {
                lingerElapsed = ExplanationCardBeats.lingerSeconds
                phase = .ended
                share = nil
                return .ended
            }
            lingerElapsed = sum
            return .advanced(remaining: ExplanationCardBeats.lingerSeconds - sum)
        }

        private static func identifierRefusal(_ id: String) -> Bool {
            let bytes = Array(id.utf8)
            return !((1...ExplanationCardBeats.identifierByteLimit).contains(bytes.count) && bytes.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
            })
        }

        /// Bounds, then controls, then a blank caption. A caption is blank when
        /// every scalar is in `blanks`. U+200B is not in that set.
        private static func speechRefusal(_ text: String) -> Bool {
            if text.utf8.count > ExplanationCardBeats.speechByteLimit { return true }
            if text.unicodeScalars.contains(where: { scalar in
                (scalar.value < 32 && scalar != "\n" && scalar != "\t") || scalar.value == 127
            }) { return true }
            return text.unicodeScalars.allSatisfy { ExplanationCardBeats.blanks.contains($0.value) }
        }
    }

    /// Spaces and line breaks, named as scalars. U+200B is not a member.
    /// Carriage return, vertical tab, and form feed are controls, refused first.
    private static let blanks: Set<UInt32> = [
        0x09, 0x0A,
        0x20,
        0x85,
        0xA0,
        0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
        0x2028, 0x2029,
        0x202F,
        0x205F,
        0x3000,
    ]
}
