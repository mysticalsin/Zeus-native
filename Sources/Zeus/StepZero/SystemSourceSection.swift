import Foundation

/// The step-zero system-source order. Pure: it reads no clock, starts no process, and publishes nothing itself.
///
/// The caller feeds facts that a decoder already accepted, plus the owner's answers and the seconds it waited.
/// Media commands are 0 play, 1 pause, 4 next, and 5 previous. Seek is its own ask. The child's standard error
/// is the null device. The canary file that talks to the system display stays out of this file.
public enum SystemSourceSection {
    /// Play, pause, next, and previous. Seek is not one of these numbers.
    public enum MediaCommand {
        public static let play = 0
        public static let pause = 1
        public static let next = 4
        public static let previous = 5
    }

    /// Next is withheld until the position reads this many seconds. The part waits at most `skipWaitLimitSeconds`.
    public static let nextNotBeforeSeconds = 21
    public static let skipWaitLimitSeconds = 25
    /// After a pause, this many seconds of still playing asks the owner to pause.
    public static let pauseGiveUpSeconds = 2
    /// The canary may be published while the service still reports playing only after this wait.
    public static let stillPlayingSeconds = 5
    public static let caseCount = 4

    /// The spawner sends the child's standard error here. This section never opens that stream.
    public static let childStandardError = ChildError.nullDevice

    public enum ChildError: Sendable, Equatable {
        case nullDevice
    }

    public enum Attempt: String, Sendable, Equatable, CaseIterable {
        case none
        case homeUserTmp
        case sessionSet
    }

    public enum Needs: String, Sendable, Equatable {
        case none
        case homeUserTmp
        case sessionSet
        case unknown
    }

    public enum AppClass: String, Sendable, Equatable {
        case player
        case browser
        case video
        case call
        case other
    }

    public enum Answer: String, Sendable, Equatable {
        case yes
        case no
        case notMeasured
        case timedOut
        case notTried
    }

    public enum Precondition: String, Sendable, Equatable {
        case nothingPlaying
        case pausedByProbe
        case pausedByOwner
        case stillPlaying
    }

    public enum Gate: String, Sendable, Equatable {
        case present
        case absent
        case unknown
    }

    public enum Art: String, Sendable, Equatable {
        case jpeg
        case png
        case other
    }

    public enum BundleCall: String, Sendable, Equatable {
        case client
        case pid
        case none
        case unknown
    }

    public enum Part: String, Sendable, Equatable {
        case idle
        case item
        case plain
        case symbols
        case transport
        case seek
        case canary
        case skip
        case artwork
        case cases
        case exit
        case done
    }

    /// A fact the decoder already closed. No title, token, bundle id, or other run-time text fits in a fact.
    public enum Fact: Sendable, Equatable {
        case playing(Bool)
        case nothing
        case elapsed(Int)
        case appClass(AppClass)
        case yes
        case no
        case seen(Bool)
        case same(Bool)
        case title(Bool)
        case art(Art)
        case gate(Gate)
        case missing(Int)
        case notify(Bool)
        case bundleCall(BundleCall)
        case cpu(Int)
        case rate(Int)
        case exited(Int)
    }

    public enum Ask: Sendable, Equatable {
        case read
        case command(Int)
        case seek(seconds: Int)
        case plainRead
        case sameApp
        case closeInput
    }

    public enum OwnerAsk: String, Sendable, Equatable {
        case pause
        case pressPlay
        case electedChanged
        case readNow
    }

    public enum Journal: String, Sendable, Equatable {
        case pause
        case play
        case seek
        case seekBack
        case next
        case previous
        case canary
        case closeInput
        case timedOut
    }

    public enum Effect: Sendable, Equatable {
        case spawn(Attempt)
        case ask(Ask)
        case publishCanary
        case clearCanary
        case askOwner(OwnerAsk)
        case journal(Journal)
        case stopChild
    }

    public enum Cursor: Sendable, Equatable {
        case idle
        case awaitItem
        case awaitPlain
        case awaitSymbols
        case awaitPauseAck
        case awaitPlayRestore
        case awaitSeekAck
        case awaitSeekRestore
        case awaitCanaryRead
        case awaitCanaryPause
        case awaitCanaryWindow
        case awaitOwnerPause
        case awaitStillPlaying
        case awaitCanarySeen
        case awaitSame
        case awaitElected
        case awaitPlayKey
        case awaitPlayKeyRead
        case awaitKeyRestore
        case awaitSkipElapsed
        case awaitNextAck
        case awaitPrevious
        case awaitArtwork
        case awaitCase
        case awaitExit
        case done
        case stopped
    }

    public enum Event: Sendable, Equatable {
        case begin
        case fact(Fact)
        case waited(seconds: Int)
        case timedOut
        case ownerPaused
        case ownerDidNotPause
        case ownerPressedPlay
        case ownerElected(Bool)
        case ownerNotTried
    }

    public struct State: Sendable, Equatable {
        public var cursor: Cursor = .idle
        public var attempt: Attempt = .none
        public var itemSeen: Answer = .notMeasured
        public var needs: Needs = .unknown
        public var playing: Bool = false
        public var beganPlaying: Bool = false
        public var position: Int = 0
        public var beganElapsed: Int = 0
        public var hasBeganElapsed: Bool = false
        public var appClass: AppClass = .other
        public var plainGate: Gate = .unknown
        public var precondition: Precondition?
        public var canaryPublished: Bool = false
        public var canaryCleared: Bool = false
        public var stillPlayingWaitRan: Bool = false
        public var restoredElected: Answer = .notMeasured
        public var restoredPlay: Answer = .notMeasured
        public var pauseAnswer: Answer = .notMeasured
        public var playAnswer: Answer = .notMeasured
        public var seekAnswer: Answer = .notMeasured
        public var nextAnswer: Answer = .notMeasured
        public var previousAnswer: Answer = .notMeasured
        public var lineAnswer: Answer = .notMeasured
        public var timedOut: Bool = false
        public var enteredSymbols: Bool = false
        public var commands: [Int] = []
        public var seeks: [Int] = []
        public var pauseWindow: Int = 0
        public var stillWindow: Int = 0
        public var skipWait: Int = 0
        public var caseIndex: Int = 0
        public var missingCount: Int?
        public var notifySeen: Bool?
        public var bundleCall: BundleCall?
        public var pollCPU: Int?
        public var artwork: Art?
        public var exitMilliseconds: Int?
        public var frozenPart: Part = .item

        public init() {}

        public var part: Part {
            if cursor == .stopped { return frozenPart }
            switch cursor {
            case .idle: return .idle
            case .awaitItem: return .item
            case .awaitPlain: return .plain
            case .awaitSymbols: return .symbols
            case .awaitPauseAck, .awaitPlayRestore: return .transport
            case .awaitSeekAck, .awaitSeekRestore: return .seek
            case .awaitCanaryRead, .awaitCanaryPause, .awaitCanaryWindow, .awaitOwnerPause,
                 .awaitStillPlaying, .awaitCanarySeen, .awaitSame, .awaitElected, .awaitPlayKey,
                 .awaitPlayKeyRead, .awaitKeyRestore:
                return .canary
            case .awaitSkipElapsed, .awaitNextAck, .awaitPrevious: return .skip
            case .awaitArtwork: return .artwork
            case .awaitCase: return .cases
            case .awaitExit: return .exit
            case .done: return .done
            case .stopped: return frozenPart
            }
        }
    }

    public static func fresh() -> State { State() }

    /// The only door a child line has. A nil from `decode` is not a fact and is not an answer.
    public static func accept(line: String, decode: (String) -> Fact?) -> Fact? {
        decode(line)
    }

    public static func reduce(_ state: State, _ event: Event) -> (state: State, effects: [Effect]) {
        var state = state
        var effects: [Effect] = []
        switch event {
        case .begin:
            guard state.cursor == .idle else { break }
            state.cursor = .awaitItem
            effects.append(.spawn(.none))
            ask(.read, &state, &effects)
        case .timedOut:
            timeOut(&state, &effects)
        case .waited(let seconds) where seconds > 0:
            wait(seconds, &state, &effects)
        case .waited:
            break
        case .ownerPaused:
            guard state.cursor == .awaitOwnerPause else { break }
            state.precondition = .pausedByOwner
            state.playing = false
            publish(&state, &effects)
        case .ownerDidNotPause:
            guard state.cursor == .awaitOwnerPause else { break }
            state.stillWindow = 0
            state.cursor = .awaitStillPlaying
        case .ownerPressedPlay:
            guard state.cursor == .awaitPlayKey else { break }
            state.cursor = .awaitPlayKeyRead
            ask(.read, &state, &effects)
        case .ownerElected(let ok):
            guard state.cursor == .awaitElected else { break }
            state.restoredElected = ok ? .yes : .no
            askPlayKey(&state, &effects)
        case .ownerNotTried:
            guard state.cursor == .awaitCase else { break }
            advanceCase(&state, &effects)
        case .fact(let fact):
            absorb(fact, &state)
            apply(fact, &state, &effects)
        }
        return (state, effects)
    }

    private static func absorb(_ fact: Fact, _ state: inout State) {
        switch fact {
        case .playing(let on):
            state.playing = on
        case .appClass(let kind):
            state.appClass = kind
        case .elapsed(let seconds):
            state.position = max(0, seconds)
            if state.cursor == .awaitItem, !state.hasBeganElapsed {
                state.beganElapsed = state.position
                state.hasBeganElapsed = true
            }
        case .missing(let count):
            state.missingCount = max(0, count)
        case .notify(let on):
            state.notifySeen = on
        case .bundleCall(let call):
            state.bundleCall = call
        case .cpu(let milliseconds):
            state.pollCPU = max(0, milliseconds)
        case .art(let art):
            state.artwork = art
        case .gate(let gate):
            if state.cursor == .awaitPlain { state.plainGate = gate }
        default:
            break
        }
    }

    private static func apply(_ fact: Fact, _ state: inout State, _ effects: inout [Effect]) {
        switch state.cursor {
        case .awaitItem:
            applyItem(fact, &state, &effects)
        case .awaitPlain:
            switch fact {
            case .gate, .nothing:
                if state.itemSeen == .no {
                    goExit(&state, &effects)
                } else {
                    goSymbols(&state, &effects)
                }
            default:
                break
            }
        case .awaitSymbols:
            if case .nothing = fact { goTransport(&state, &effects) }
        case .awaitPauseAck:
            if succeeded(fact, playingMeansDone: false) {
                state.pauseAnswer = .yes
                if state.beganPlaying {
                    state.cursor = .awaitPlayRestore
                    command(MediaCommand.play, journal: .play, &state, &effects)
                } else {
                    goSeek(&state, &effects)
                }
            }
        case .awaitPlayRestore:
            if succeeded(fact, playingMeansDone: true) { goSeek(&state, &effects) }
        case .awaitSeekAck:
            if succeeded(fact, playingMeansDone: true) {
                state.cursor = .awaitSeekRestore
                journaledSeek(.seekBack, state.beganElapsed, &state, &effects)
            }
        case .awaitSeekRestore:
            if succeeded(fact, playingMeansDone: true) { goCanary(&state, &effects) }
        case .awaitCanaryRead:
            if !state.playing || isNothing(fact) {
                state.precondition = .nothingPlaying
                state.playing = false
                publish(&state, &effects)
            } else if case .playing(true) = fact {
                state.cursor = .awaitCanaryPause
                command(MediaCommand.pause, journal: .pause, &state, &effects)
            }
        case .awaitCanaryPause:
            if succeeded(fact, playingMeansDone: false) {
                state.precondition = .pausedByProbe
                state.playing = false
                publish(&state, &effects)
            } else if case .playing(true) = fact {
                state.pauseWindow = 0
                state.cursor = .awaitCanaryWindow
            }
        case .awaitCanaryWindow:
            if succeeded(fact, playingMeansDone: false) {
                state.precondition = .pausedByProbe
                state.playing = false
                publish(&state, &effects)
            }
        case .awaitStillPlaying:
            if succeeded(fact, playingMeansDone: false) {
                state.precondition = .pausedByOwner
                state.playing = false
                publish(&state, &effects)
            }
        case .awaitCanarySeen:
            if case .seen = fact { leaveCanary(&state, &effects) }
            else if case .yes = fact { leaveCanary(&state, &effects) }
            else if case .nothing = fact { leaveCanary(&state, &effects) }
        case .awaitSame:
            if case .same(let same) = fact {
                if same {
                    state.restoredElected = .yes
                    askPlayKey(&state, &effects)
                } else {
                    state.cursor = .awaitElected
                    effects.append(.askOwner(.electedChanged))
                }
            }
        case .awaitPlayKeyRead:
            if case .playing = fact { restorePlay(&state, &effects) }
        case .awaitKeyRestore:
            if succeeded(fact, playingMeansDone: state.beganPlaying) {
                if state.playing == state.beganPlaying { state.restoredPlay = .yes }
                goSkip(&state, &effects)
            }
        case .awaitSkipElapsed:
            if case .elapsed = fact { sendNextIfReady(&state, &effects) }
        case .awaitNextAck:
            if succeeded(fact, playingMeansDone: true) {
                state.nextAnswer = .yes
                state.cursor = .awaitPrevious
                command(MediaCommand.previous, journal: .previous, &state, &effects)
            }
        case .awaitPrevious:
            if succeeded(fact, playingMeansDone: true) {
                state.previousAnswer = .yes
                goArtwork(&state, &effects)
            }
        case .awaitArtwork:
            if case .art = fact { goCases(&state, &effects) }
            else if case .nothing = fact { goCases(&state, &effects) }
        case .awaitExit:
            if case .exited(let milliseconds) = fact {
                state.exitMilliseconds = max(0, milliseconds)
                state.cursor = .done
            } else if case .nothing = fact {
                state.cursor = .done
            }
        default:
            break
        }
    }

    private static func applyItem(_ fact: Fact, _ state: inout State, _ effects: inout [Effect]) {
        switch fact {
        case .playing(true), .title(true):
            state.itemSeen = .yes
            state.needs = needs(for: state.attempt)
            state.beganPlaying = state.playing
            goPlain(&state, &effects)
        case .nothing, .playing(false):
            missItem(&state, &effects)
        default:
            break
        }
    }

    private static func missItem(_ state: inout State, _ effects: inout [Effect]) {
        switch state.attempt {
        case .none:
            state.attempt = .homeUserTmp
            effects.append(.spawn(.homeUserTmp))
            ask(.read, &state, &effects)
        case .homeUserTmp:
            state.attempt = .sessionSet
            effects.append(.spawn(.sessionSet))
            ask(.read, &state, &effects)
        case .sessionSet:
            state.itemSeen = .no
            state.needs = .unknown
            goPlain(&state, &effects)
        }
    }

    private static func needs(for attempt: Attempt) -> Needs {
        switch attempt {
        case .none: return .none
        case .homeUserTmp: return .homeUserTmp
        case .sessionSet: return .sessionSet
        }
    }

    private static func wait(_ seconds: Int, _ state: inout State, _ effects: inout [Effect]) {
        switch state.cursor {
        case .awaitCanaryPause, .awaitCanaryWindow:
            state.pauseWindow += seconds
            if state.pauseWindow >= pauseGiveUpSeconds {
                state.cursor = .awaitOwnerPause
                effects.append(.askOwner(.pause))
            }
        case .awaitStillPlaying:
            state.stillWindow += seconds
            if state.stillWindow >= stillPlayingSeconds {
                state.stillPlayingWaitRan = true
                state.precondition = .stillPlaying
                publish(&state, &effects)
            }
        case .awaitSkipElapsed:
            state.skipWait += seconds
            if state.position >= nextNotBeforeSeconds {
                sendNext(&state, &effects)
            } else if state.skipWait >= skipWaitLimitSeconds {
                state.nextAnswer = .notMeasured
                state.previousAnswer = .notMeasured
                goArtwork(&state, &effects)
            }
        default:
            break
        }
    }

    private static func timeOut(_ state: inout State, _ effects: inout [Effect]) {
        guard state.cursor != .idle, state.cursor != .done, state.cursor != .stopped else { return }
        let part = state.part
        if isCanary(state.cursor) || state.canaryPublished {
            clearCanary(&state, &effects)
        }
        state.frozenPart = part
        state.timedOut = true
        state.lineAnswer = .timedOut
        if part == .item { state.itemSeen = .timedOut }
        effects.append(.journal(.timedOut))
        effects.append(.stopChild)
        state.cursor = .stopped
    }

    private static func goPlain(_ state: inout State, _ effects: inout [Effect]) {
        state.cursor = .awaitPlain
        ask(.plainRead, &state, &effects)
    }

    private static func goSymbols(_ state: inout State, _ effects: inout [Effect]) {
        state.enteredSymbols = true
        state.cursor = .awaitSymbols
        ask(.read, &state, &effects)
    }

    private static func goTransport(_ state: inout State, _ effects: inout [Effect]) {
        guard state.itemSeen == .yes else {
            goSeek(&state, &effects)
            return
        }
        state.cursor = .awaitPauseAck
        command(MediaCommand.pause, journal: .pause, &state, &effects)
    }

    private static func goSeek(_ state: inout State, _ effects: inout [Effect]) {
        guard state.appClass == .player else {
            state.seekAnswer = .notMeasured
            goCanary(&state, &effects)
            return
        }
        state.cursor = .awaitSeekAck
        journaledSeek(.seek, state.hasBeganElapsed ? state.beganElapsed : state.position, &state, &effects)
    }

    private static func goCanary(_ state: inout State, _ effects: inout [Effect]) {
        state.cursor = .awaitCanaryRead
        ask(.read, &state, &effects)
    }

    private static func goSkip(_ state: inout State, _ effects: inout [Effect]) {
        guard state.appClass == .player else {
            state.nextAnswer = .notMeasured
            state.previousAnswer = .notMeasured
            goArtwork(&state, &effects)
            return
        }
        if state.position >= nextNotBeforeSeconds {
            sendNext(&state, &effects)
        } else {
            state.cursor = .awaitSkipElapsed
            ask(.read, &state, &effects)
        }
    }

    private static func sendNextIfReady(_ state: inout State, _ effects: inout [Effect]) {
        guard state.position >= nextNotBeforeSeconds else { return }
        sendNext(&state, &effects)
    }

    private static func sendNext(_ state: inout State, _ effects: inout [Effect]) {
        guard !state.commands.contains(MediaCommand.next) else { return }
        state.cursor = .awaitNextAck
        command(MediaCommand.next, journal: .next, &state, &effects)
    }

    private static func goArtwork(_ state: inout State, _ effects: inout [Effect]) {
        state.cursor = .awaitArtwork
        ask(.read, &state, &effects)
    }

    private static func goCases(_ state: inout State, _ effects: inout [Effect]) {
        state.caseIndex = 0
        state.cursor = .awaitCase
        effects.append(.askOwner(.readNow))
    }

    private static func advanceCase(_ state: inout State, _ effects: inout [Effect]) {
        state.caseIndex += 1
        if state.caseIndex >= caseCount {
            goExit(&state, &effects)
        } else {
            effects.append(.askOwner(.readNow))
        }
    }

    private static func goExit(_ state: inout State, _ effects: inout [Effect]) {
        state.cursor = .awaitExit
        effects.append(.journal(.closeInput))
        ask(.closeInput, &state, &effects)
    }

    private static func publish(_ state: inout State, _ effects: inout [Effect]) {
        let allowed = !state.playing
            || state.precondition == .nothingPlaying
            || state.precondition == .pausedByProbe
            || state.precondition == .pausedByOwner
            || (state.precondition == .stillPlaying && state.stillPlayingWaitRan)
        guard allowed, !state.canaryPublished else { return }
        state.canaryPublished = true
        effects.append(.journal(.canary))
        effects.append(.publishCanary)
        state.cursor = .awaitCanarySeen
    }

    private static func leaveCanary(_ state: inout State, _ effects: inout [Effect]) {
        clearCanary(&state, &effects)
        state.cursor = .awaitSame
        ask(.sameApp, &state, &effects)
    }

    private static func clearCanary(_ state: inout State, _ effects: inout [Effect]) {
        guard !state.canaryCleared else { return }
        state.canaryCleared = true
        effects.append(.clearCanary)
    }

    private static func askPlayKey(_ state: inout State, _ effects: inout [Effect]) {
        state.cursor = .awaitPlayKey
        effects.append(.askOwner(.pressPlay))
    }

    private static func restorePlay(_ state: inout State, _ effects: inout [Effect]) {
        if state.playing == state.beganPlaying {
            state.restoredPlay = .yes
            goSkip(&state, &effects)
            return
        }
        state.cursor = .awaitKeyRestore
        if state.beganPlaying {
            command(MediaCommand.play, journal: .play, &state, &effects)
        } else {
            command(MediaCommand.pause, journal: .pause, &state, &effects)
        }
    }

    private static func command(_ number: Int, journal: Journal, _ state: inout State, _ effects: inout [Effect]) {
        effects.append(.journal(journal))
        ask(.command(number), &state, &effects)
    }

    private static func journaledSeek(_ journal: Journal, _ seconds: Int, _ state: inout State, _ effects: inout [Effect]) {
        effects.append(.journal(journal))
        ask(.seek(seconds: max(0, seconds)), &state, &effects)
    }

    private static func ask(_ ask: Ask, _ state: inout State, _ effects: inout [Effect]) {
        switch ask {
        case .command(let number):
            state.commands.append(number)
        case .seek(let seconds):
            state.seeks.append(seconds)
        default:
            break
        }
        effects.append(.ask(ask))
    }

    private static func succeeded(_ fact: Fact, playingMeansDone: Bool) -> Bool {
        switch fact {
        case .yes: return true
        case .playing(let on): return on == playingMeansDone
        default: return false
        }
    }

    private static func isNothing(_ fact: Fact) -> Bool {
        if case .nothing = fact { return true }
        return false
    }

    private static func isCanary(_ cursor: Cursor) -> Bool {
        switch cursor {
        case .awaitCanaryRead, .awaitCanaryPause, .awaitCanaryWindow, .awaitOwnerPause,
             .awaitStillPlaying, .awaitCanarySeen, .awaitSame, .awaitElected, .awaitPlayKey,
             .awaitPlayKeyRead, .awaitKeyRestore:
            return true
        default:
            return false
        }
    }
}
