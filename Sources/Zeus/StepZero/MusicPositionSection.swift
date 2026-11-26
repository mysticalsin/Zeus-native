import Foundation

/// The step-zero music position section. Pure: it registers for no notice,
/// reads no player, and keeps no title.
///
/// The caller feeds key names from one notice and the milliseconds it waited.
/// A position key is recorded as present and the characters are dropped. Any
/// other key is ignored. The re-read file and the output section stay out of
/// this file.
public enum MusicPositionSection {
    /// The one notice this section may arm. There is no second.
    public static let noticeName = "com.apple.Music.playerInfo"
    /// A notice after this wait is not within the action.
    public static let windowMilliseconds = 15_000
    /// Notices past this count are not read.
    public static let maxNotices = 64
    /// Keys past this count on one notice are not read.
    public static let maxKeys = 32
    /// A key longer than this is ignored. The value is never taken.
    public static let maxKeyBytes = 64

    public enum Action: String, Sendable, Equatable {
        case play
        case pause
        case trackChange
        case scrub
    }

    public static let script: [Action] = [.play, .pause, .trackChange, .scrub]

    /// The closed position keys. A value for any of them is never accepted.
    public static func isPositionKey(_ key: String) -> Bool {
        switch key {
        case "Playback Position", "Player Position", "Elapsed":
            return true
        default:
            return false
        }
    }

    public enum PartMark: String, Sendable, Equatable {
        case ran
        case skipped
    }

    /// What one action posted. Counts only. No key text.
    public struct Fact: Sendable, Equatable {
        public var posted: Bool
        public var positionKey: Bool
        public var noticesTaken: Int
        public var keysRead: Int

        public init(posted: Bool, positionKey: Bool, noticesTaken: Int, keysRead: Int) {
            self.posted = posted
            self.positionKey = positionKey
            self.noticesTaken = noticesTaken
            self.keysRead = keysRead
        }
    }

    public enum Effect: Sendable, Equatable {
        case arm
        case disarm
    }

    public enum Phase: String, Sendable, Equatable {
        case idle
        case gate
        case watching
        case done
    }

    public enum Event: Sendable, Equatable {
        case begin
        case continueAsked
        case skip
        case notice([String])
        case waited(milliseconds: Int)
    }

    public struct State: Sendable, Equatable {
        public var phase: Phase
        public var cursor: Int
        public var marks: [Action: PartMark]
        public var facts: [Action: Fact]
        public var clockMs: Int
        public var armed: Bool
        public var sawNotice: Bool
        public var sawPosition: Bool
        public var noticesTaken: Int
        public var keysRead: Int

        public init() {
            phase = .idle
            cursor = 0
            marks = [:]
            facts = [:]
            clockMs = 0
            armed = false
            sawNotice = false
            sawPosition = false
            noticesTaken = 0
            keysRead = 0
        }
    }

    public static func fresh() -> State { State() }

    public static func reduce(_ state: State, _ event: Event) -> (state: State, effects: [Effect]) {
        var state = state
        var effects: [Effect] = []
        switch event {
        case .begin:
            begin(&state)
        case .continueAsked:
            continueAsked(&state, &effects)
        case .skip:
            skip(&state)
        case .notice(let keys):
            takeNotice(keys, &state, &effects)
        case .waited(let milliseconds):
            waited(milliseconds, &state, &effects)
        }
        return (state, effects)
    }

    private static func begin(_ state: inout State) {
        guard state.phase == .idle else { return }
        state.cursor = 0
        state.phase = .gate
    }

    private static func continueAsked(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .gate, state.cursor < script.count else { return }
        state.phase = .watching
        state.clockMs = 0
        state.sawNotice = false
        state.sawPosition = false
        state.noticesTaken = 0
        state.keysRead = 0
        state.armed = true
        effects.append(.arm)
    }

    private static func skip(_ state: inout State) {
        guard state.phase == .gate, state.cursor < script.count else { return }
        state.marks[script[state.cursor]] = .skipped
        advance(&state)
    }

    private static func takeNotice(_ keys: [String], _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .watching else { return }
        guard state.noticesTaken < maxNotices else { return }
        state.noticesTaken += 1
        state.sawNotice = true
        var read = 0
        for key in keys {
            if read == maxKeys { break }
            guard key.utf8.count <= maxKeyBytes else { continue }
            read += 1
            state.keysRead += 1
            if isPositionKey(key) {
                state.sawPosition = true
            }
        }
        if state.sawPosition {
            finish(&state, &effects)
        }
    }

    private static func waited(_ milliseconds: Int, _ state: inout State, _ effects: inout [Effect]) {
        guard milliseconds > 0, state.phase == .watching else { return }
        state.clockMs += milliseconds
        if state.clockMs >= windowMilliseconds {
            finish(&state, &effects)
        }
    }

    private static func finish(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .watching, state.cursor < script.count else { return }
        let action = script[state.cursor]
        state.facts[action] = Fact(
            posted: state.sawNotice,
            positionKey: state.sawPosition,
            noticesTaken: state.noticesTaken,
            keysRead: state.keysRead
        )
        state.marks[action] = .ran
        disarm(&state, &effects)
        advance(&state)
    }

    private static func disarm(_ state: inout State, _ effects: inout [Effect]) {
        guard state.armed else { return }
        state.armed = false
        effects.append(.disarm)
    }

    private static func advance(_ state: inout State) {
        state.cursor += 1
        state.clockMs = 0
        state.sawNotice = false
        state.sawPosition = false
        state.noticesTaken = 0
        state.keysRead = 0
        state.armed = false
        if state.cursor >= script.count {
            state.phase = .done
        } else {
            state.phase = .gate
        }
    }
}
