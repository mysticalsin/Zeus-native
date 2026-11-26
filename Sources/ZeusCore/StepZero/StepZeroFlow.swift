/// Pure reducer for the step-zero window.
///
/// `begin` deadens Continue for 1.5 seconds. `reduce` then takes one event and
/// returns the next state and the effects. Limits are plain seconds, so a test
/// runs without a clock.
///
/// The window, the watchdog, and the report file stay in their own types.
/// A later session copies the resume flag in. This reducer does not exit.
public enum StepZeroFlow {
    /// Continue stays dead for this long after the window appears. 1500 is 1.5 seconds.
    public static let continueDeadMilliseconds = 1500

    public enum Signing: Equatable, Sendable {
        case developerID
        case adHoc
        case localIdentity
        case unread
    }

    public enum Section: Equatable, Sendable, CaseIterable {
        case putBack
        case systemSource
        case lockScreen
        case killTest
        case earbuds
        case focus
        case soundOutput
        case musicPosition

        public var title: String {
            switch self {
            case .putBack: "Put back"
            case .systemSource: "System source"
            case .lockScreen: "Lock screen"
            case .killTest: "Kill test"
            case .earbuds: "Earbuds"
            case .focus: "Focus"
            case .soundOutput: "Sound output"
            case .musicPosition: "Music position"
            }
        }

        public var parts: [Part] {
            switch self {
            case .putBack: [.putBack]
            case .systemSource: [.sealBeforeSpawn, .helperLine, .systemSourceSkip]
            case .lockScreen: [.lockScreen, .lockLook, .lockPlayerQuiet, .lockPlayerAsk, .lockPlayerScript]
            case .killTest: [.killTest]
            case .earbuds: [.earbudsPaired, .earbudsManager, .earbudsMode]
            case .focus: [.focusRead, .focusTool]
            case .soundOutput: [.soundSwitch, .soundNetwork]
            case .musicPosition: [.musicNotice]
            }
        }
    }

    public enum Kind: Equatable, Sendable {
        case gated
        case hand
    }

    public enum Part: Equatable, Sendable, CaseIterable {
        case putBack
        case sealBeforeSpawn
        case helperLine
        case systemSourceSkip
        case lockScreen
        case lockLook
        case lockPlayerQuiet
        case lockPlayerAsk
        case lockPlayerScript
        case killTest
        case earbudsPaired
        case earbudsManager
        case earbudsMode
        case focusRead
        case focusTool
        case soundSwitch
        case soundNetwork
        case musicNotice

        public var section: Section {
            switch self {
            case .putBack: .putBack
            case .sealBeforeSpawn, .helperLine, .systemSourceSkip: .systemSource
            case .lockScreen, .lockLook, .lockPlayerQuiet, .lockPlayerAsk, .lockPlayerScript: .lockScreen
            case .killTest: .killTest
            case .earbudsPaired, .earbudsManager, .earbudsMode: .earbuds
            case .focusRead, .focusTool: .focus
            case .soundSwitch, .soundNetwork: .soundOutput
            case .musicNotice: .musicPosition
            }
        }

        public var kind: Kind {
            self == .lockLook ? .hand : .gated
        }

        /// `soundSwitch` shares the Core Audio row with `earbudsMode`: one write is two seconds,
        /// and a timeout still owes one restore. `killTest` shares the lock-card row because the
        /// card is up. `focusRead` shares the tool row, the only Focus wait in the table.
        /// `systemSourceSkip` shares the helper-line row. `musicNotice` is question A2's 15 seconds.
        public var row: LimitRow {
            switch self {
            case .putBack: .stopAndRestore
            case .sealBeforeSpawn: .signatureCheck
            case .helperLine, .systemSourceSkip: .helperLine
            case .lockScreen, .killTest: .lockCard
            case .lockLook: .looking
            case .lockPlayerQuiet: .automationQuiet
            case .lockPlayerAsk: .automationAsk
            case .lockPlayerScript: .playerScript
            case .earbudsPaired: .bluetoothClassic
            case .earbudsManager: .bluetoothManager
            case .earbudsMode, .soundSwitch: .coreAudio
            case .focusRead, .focusTool: .toolStart
            case .soundNetwork: .speakerBrowse
            case .musicNotice: .musicNotice
            }
        }

        public var limit: Limit { StepZeroFlow.limit(for: row) }

        public var line: String {
            switch self {
            case .putBack: StepZeroFlow.putBackLine
            case .sealBeforeSpawn: StepZeroFlow.systemSourceLine
            case .helperLine: StepZeroFlow.readNowLine
            case .systemSourceSkip: StepZeroFlow.skipLine
            case .lockScreen: StepZeroFlow.lockLine
            case .lockLook: StepZeroFlow.lockInstruction
            case .lockPlayerQuiet, .lockPlayerAsk, .lockPlayerScript: StepZeroFlow.playerLine
            case .killTest: StepZeroFlow.killLine
            case .earbudsPaired: StepZeroFlow.pairedLine
            case .earbudsManager: StepZeroFlow.managerLine
            case .earbudsMode: StepZeroFlow.modeLine
            case .focusRead: StepZeroFlow.focusLine
            case .focusTool: StepZeroFlow.toolLine
            case .soundSwitch: StepZeroFlow.soundLine
            case .soundNetwork: StepZeroFlow.networkLine
            case .musicNotice: StepZeroFlow.musicLine
            }
        }

        public static func representative(for row: LimitRow) -> Part {
            switch row {
            case .helperLine: .helperLine
            case .bluetoothManager: .earbudsManager
            case .bluetoothClassic: .earbudsPaired
            case .signatureCheck: .sealBeforeSpawn
            case .coreAudio: .earbudsMode
            case .automationQuiet: .lockPlayerQuiet
            case .automationAsk: .lockPlayerAsk
            case .playerScript: .lockPlayerScript
            case .toolStart: .focusTool
            case .stopAndRestore: .putBack
            case .lockCard: .lockScreen
            case .looking: .lockLook
            case .speakerBrowse: .soundNetwork
            case .musicNotice: .musicNotice
            }
        }
    }

    public enum LimitRow: Equatable, Sendable, CaseIterable {
        case helperLine
        case bluetoothManager
        case bluetoothClassic
        case signatureCheck
        case coreAudio
        case automationQuiet
        case automationAsk
        case playerScript
        case toolStart
        case stopAndRestore
        case lockCard
        case looking
        case speakerBrowse
        case musicNotice
    }

    public enum Expiry: Equatable, Sendable {
        case moveOn
        case stop
    }

    public enum Record: Equatable, Sendable {
        case timedOut
        case notMeasured
        case hung
        case refusal
        case stepFailed
        case verbNo
        case cancelled
        case destroyed
    }

    public struct Limit: Equatable, Sendable {
        public var row: LimitRow
        public var seconds: Int
        public var onExpiry: Expiry
        public var record: Record
        public var restoreStillTried: Bool

        public init(
            row: LimitRow,
            seconds: Int,
            onExpiry: Expiry,
            record: Record,
            restoreStillTried: Bool
        ) {
            self.row = row
            self.seconds = seconds
            self.onExpiry = onExpiry
            self.record = record
            self.restoreStillTried = restoreStillTried
        }
    }

    public enum Phase: Equatable, Sendable {
        case notRun
        case asking(Part)
        case running(Part)
        case yourTurn(Part)
        case done
        case partial
        case skipped
        case stopped
    }

    public enum Outcome: Equatable, Sendable {
        case finished
        case skipped
        case timedOut
    }

    public struct State: Equatable, Sendable {
        public var signing: Signing
        public var armed: Bool
        public var owesRestore: Bool
        public var phases: [Section: Phase]
        public var outcomes: [Part: Outcome]
        public var current: Part?

        public init(
            signing: Signing,
            armed: Bool,
            owesRestore: Bool,
            phases: [Section: Phase],
            outcomes: [Part: Outcome],
            current: Part?
        ) {
            self.signing = signing
            self.armed = armed
            self.owesRestore = owesRestore
            self.phases = phases
            self.outcomes = outcomes
            self.current = current
        }

        public func phase(_ section: Section) -> Phase {
            phases[section] ?? .notRun
        }
    }

    public struct Resume: Equatable, Sendable {
        public var owesRestore: Bool

        public init(owesRestore: Bool) {
            self.owesRestore = owesRestore
        }
    }

    public enum HandAnswer: Equatable, Sendable {
        case done
        case start
        case yes
        case no
        case notTried
    }

    public enum Event: Equatable, Sendable {
        case continuePressed
        case skipPressed
        case armed
        case partFinished(Part)
        case partTimedOut(Part)
        case handAnswered(Part, HandAnswer)
        case resumed(Resume)
    }

    public enum JournalStep: Equatable, Sendable {
        case started(Part)
        case finished(Part)
        case timedOut(Part, record: Record, restoreStillTried: Bool)
        case skipped(Part)
        case hand(Part, HandAnswer)
    }

    public enum Effect: Equatable, Sendable {
        case arm(Int)
        case run(Part, Limit)
        case journal(JournalStep)
        case writeReport
    }

    public struct ResultWord: Equatable, Sendable {
        public var word: String
        public var symbol: String

        public init(word: String, symbol: String) {
            self.word = word
            self.symbol = symbol
        }
    }

    public static let putBackLine = "The last run ended early. This puts your earbuds' listening mode back and stops one helper process."
    public static let systemSourceLine = "This reads what any app on this Mac is playing, pauses it, moves the position, and shows the word Zeus in the Mac's own now-playing display for up to three seconds. Each is put back."
    public static let readNowLine = "Read now"
    public static let skipLine = "This skips to the next track and back in your music player. The player may count one skip."
    public static let lockLine = "This puts a small test card on your lock screen while you lock and unlock the Mac. It also asks you to switch user, start the screensaver and sleep the display."
    public static let lockInstruction = "Lock the Mac. Unlock it when the card has shown."
    public static let playerLine = "Next, macOS may ask to let ZEUS control Music and Spotify, so the probe can play, pause and skip from the lock screen. The player may count one skip."
    public static let killLine = "This ends the probe on purpose while the test card and the helper are up. You then start it again."
    public static let pairedLine = "Next, macOS may ask to let ZEUS use Bluetooth. The probe lists the devices paired with this Mac to see whether that needs your permission."
    public static let managerLine = "Next, macOS will ask to let ZEUS use Bluetooth, so the probe can see your earbuds connect and read their battery."
    public static let modeLine = "This changes your earbuds' listening mode for a few seconds and puts it back."
    public static let focusLine = "This reads the two Focus files and keeps yes or no answers only. It asks you to turn a Focus on and off, and to switch Full Disk Access for ZEUS off and on."
    public static let toolLine = "This starts a small system tool that tries to list one protected folder, and keeps only whether it could."
    public static let soundLine = "This moves the Mac's sound to your earbuds for five seconds and puts it back."
    public static let networkLine = "Next, macOS will ask to let ZEUS find devices on your network, so the probe can see how wireless speakers announce themselves."
    public static let musicLine = "This watches the notices Music posts while you play, pause, skip and scrub."

    public static let notRunWord = "Not run"
    public static let runningWord = "Running"
    public static let yourTurnWord = "Your turn"
    public static let doneWord = "Done"
    public static let partialWord = "Partly done"
    public static let skippedWord = "Skipped"
    public static let stoppedWord = "Stopped"

    public static let notRunSymbol = "circle"
    public static let runningSymbol = "arrow.triangle.2.circlepath"
    public static let yourTurnSymbol = "hand.point.up.left"
    public static let doneSymbol = "checkmark.circle"
    public static let partialSymbol = "circle.lefthalf.filled"
    public static let skippedSymbol = "forward"
    public static let stoppedSymbol = "exclamationmark.triangle"

    public static let visibleCopy: [String] = [
        Section.putBack.title, Section.systemSource.title, Section.lockScreen.title, Section.killTest.title,
        Section.earbuds.title, Section.focus.title, Section.soundOutput.title, Section.musicPosition.title,
        putBackLine, systemSourceLine, readNowLine, skipLine, lockLine, lockInstruction, playerLine, killLine,
        pairedLine, managerLine, modeLine, focusLine, toolLine, soundLine, networkLine, musicLine,
        notRunWord, runningWord, yourTurnWord, doneWord, partialWord, skippedWord, stoppedWord,
        notRunSymbol, runningSymbol, yourTurnSymbol, doneSymbol, partialSymbol, skippedSymbol, stoppedSymbol,
    ]

    public static func limit(for row: LimitRow) -> Limit {
        switch row {
        case .helperLine:
            return Limit(row: row, seconds: 5, onExpiry: .moveOn, record: .timedOut, restoreStillTried: false)
        case .bluetoothManager:
            return Limit(row: row, seconds: 10, onExpiry: .moveOn, record: .notMeasured, restoreStillTried: false)
        case .bluetoothClassic:
            return Limit(row: row, seconds: 15, onExpiry: .stop, record: .hung, restoreStillTried: false)
        case .signatureCheck:
            return Limit(row: row, seconds: 10, onExpiry: .stop, record: .refusal, restoreStillTried: false)
        case .coreAudio:
            return Limit(row: row, seconds: 2, onExpiry: .moveOn, record: .stepFailed, restoreStillTried: true)
        case .automationQuiet:
            return Limit(row: row, seconds: 2, onExpiry: .moveOn, record: .timedOut, restoreStillTried: false)
        case .automationAsk:
            return Limit(row: row, seconds: 60, onExpiry: .moveOn, record: .timedOut, restoreStillTried: false)
        case .playerScript:
            return Limit(row: row, seconds: 3, onExpiry: .moveOn, record: .verbNo, restoreStillTried: false)
        case .toolStart:
            return Limit(row: row, seconds: 5, onExpiry: .moveOn, record: .timedOut, restoreStillTried: false)
        case .stopAndRestore:
            return Limit(row: row, seconds: 5, onExpiry: .stop, record: .timedOut, restoreStillTried: false)
        case .lockCard:
            return Limit(row: row, seconds: 120, onExpiry: .moveOn, record: .destroyed, restoreStillTried: false)
        case .looking:
            return Limit(row: row, seconds: 300, onExpiry: .moveOn, record: .destroyed, restoreStillTried: false)
        case .speakerBrowse:
            return Limit(row: row, seconds: 20, onExpiry: .moveOn, record: .cancelled, restoreStillTried: false)
        case .musicNotice:
            return Limit(row: row, seconds: 15, onExpiry: .moveOn, record: .timedOut, restoreStillTried: false)
        }
    }

    public static func result(for phase: Phase) -> ResultWord {
        switch phase {
        case .notRun, .asking:
            return ResultWord(word: notRunWord, symbol: notRunSymbol)
        case .running:
            return ResultWord(word: runningWord, symbol: runningSymbol)
        case .yourTurn:
            return ResultWord(word: yourTurnWord, symbol: yourTurnSymbol)
        case .done:
            return ResultWord(word: doneWord, symbol: doneSymbol)
        case .partial:
            return ResultWord(word: partialWord, symbol: partialSymbol)
        case .skipped:
            return ResultWord(word: skippedWord, symbol: skippedSymbol)
        case .stopped:
            return ResultWord(word: stoppedWord, symbol: stoppedSymbol)
        }
    }

    /// Put back leads only when a previous run left something to restore.
    /// A signing other than `developerID` can reach Put back and System source.
    /// The other rows stay Not run.
    public static func sectionOrder(owesRestore: Bool) -> [Section] {
        var rows: [Section] = [
            .systemSource, .lockScreen, .killTest, .earbuds, .focus, .soundOutput, .musicPosition,
        ]
        if owesRestore { rows.insert(.putBack, at: 0) }
        return rows
    }

    public static func canReach(_ section: Section, signing: Signing) -> Bool {
        switch section {
        case .putBack, .systemSource:
            return true
        case .lockScreen, .killTest, .earbuds, .focus, .soundOutput, .musicPosition:
            return signing == .developerID
        }
    }

    public static func begin(_ signing: Signing) -> (State, [Effect]) {
        var state = empty(signing: signing, owesRestore: false)
        enter(.sealBeforeSpawn, state: &state)
        return (state, [.arm(continueDeadMilliseconds)])
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        switch event {
        case .armed:
            var state = state
            state.armed = true
            return (state, [])

        case .resumed(let resume):
            var fresh = empty(signing: state.signing, owesRestore: resume.owesRestore)
            enter(resume.owesRestore ? .putBack : .sealBeforeSpawn, state: &fresh)
            return (fresh, [])

        case .continuePressed:
            guard state.armed, let part = state.current, part.kind == .gated else { return (state, []) }
            guard canReach(part.section, signing: state.signing) else { return (state, []) }
            guard state.phase(part.section) == .asking(part) else { return (state, []) }
            var state = state
            state.phases[part.section] = .running(part)
            return (state, [.journal(.started(part)), .run(part, part.limit)])

        case .skipPressed:
            guard state.armed, let part = state.current else { return (state, []) }
            guard canReach(part.section, signing: state.signing) else { return (state, []) }
            switch state.phase(part.section) {
            case .asking(part), .yourTurn(part), .running(part):
                break
            default:
                return (state, [])
            }
            var state = state
            state.outcomes[part] = .skipped
            var effects: [Effect] = [.journal(.skipped(part))]
            advance(from: part, state: &state, effects: &effects)
            return (state, effects)

        case .partFinished(let part):
            guard canReach(part.section, signing: state.signing) else { return (state, []) }
            guard state.phase(part.section) == .running(part) else { return (state, []) }
            var state = state
            state.outcomes[part] = .finished
            var effects: [Effect] = [.journal(.finished(part))]
            advance(from: part, state: &state, effects: &effects)
            return (state, effects)

        case .partTimedOut(let part):
            guard canReach(part.section, signing: state.signing) else { return (state, []) }
            switch state.phase(part.section) {
            case .running(part), .yourTurn(part):
                break
            default:
                return (state, [])
            }
            var state = state
            let limit = part.limit
            var effects: [Effect] = [
                .journal(.timedOut(part, record: limit.record, restoreStillTried: limit.restoreStillTried)),
            ]
            switch limit.onExpiry {
            case .stop:
                state.phases[part.section] = .stopped
                state.current = part
                return (state, effects)
            case .moveOn:
                state.outcomes[part] = .timedOut
                advance(from: part, state: &state, effects: &effects)
                return (state, effects)
            }

        case .handAnswered(let part, let answer):
            guard canReach(part.section, signing: state.signing) else { return (state, []) }
            guard state.phase(part.section) == .yourTurn(part) else { return (state, []) }
            var state = state
            state.outcomes[part] = .finished
            var effects: [Effect] = [.journal(.hand(part, answer))]
            advance(from: part, state: &state, effects: &effects)
            return (state, effects)
        }
    }

    private static func empty(signing: Signing, owesRestore: Bool) -> State {
        var phases: [Section: Phase] = [:]
        for section in Section.allCases {
            phases[section] = .notRun
        }
        return State(
            signing: signing,
            armed: false,
            owesRestore: owesRestore,
            phases: phases,
            outcomes: [:],
            current: nil
        )
    }

    private static func enter(_ part: Part, state: inout State) {
        state.current = part
        switch part.kind {
        case .gated:
            state.phases[part.section] = .asking(part)
        case .hand:
            state.phases[part.section] = .yourTurn(part)
        }
    }

    private static func advance(from part: Part, state: inout State, effects: inout [Effect]) {
        let parts = part.section.parts
        guard let index = parts.firstIndex(of: part) else {
            state.phases[part.section] = .stopped
            state.current = part
            return
        }
        if index + 1 < parts.count {
            enter(parts[index + 1], state: &state)
            return
        }
        state.phases[part.section] = terminal(part.section, state.outcomes)
        state.current = nil
        if let following = nextReachable(after: part.section, state: state), let first = following.parts.first {
            enter(first, state: &state)
            return
        }
        if reportIsDue(state) {
            effects.append(.writeReport)
        }
    }

    private static func terminal(_ section: Section, _ outcomes: [Part: Outcome]) -> Phase {
        let parts = section.parts
        if parts.allSatisfy({ outcomes[$0] == .finished }) { return .done }
        if parts.allSatisfy({ outcomes[$0] == .skipped }) { return .skipped }
        return .partial
    }

    private static func nextReachable(after section: Section, state: State) -> Section? {
        let rows = sectionOrder(owesRestore: state.owesRestore)
        guard let index = rows.firstIndex(of: section) else { return nil }
        for candidate in rows.dropFirst(index + 1) where canReach(candidate, signing: state.signing) {
            return candidate
        }
        return nil
    }

    private static func reportIsDue(_ state: State) -> Bool {
        let needed = sectionOrder(owesRestore: state.owesRestore).filter {
            canReach($0, signing: state.signing)
        }
        guard !needed.isEmpty else { return false }
        return needed.allSatisfy { section in
            switch state.phase(section) {
            case .done, .partial, .skipped:
                return true
            case .notRun, .asking, .running, .yourTurn, .stopped:
                return false
            }
        }
    }
}
