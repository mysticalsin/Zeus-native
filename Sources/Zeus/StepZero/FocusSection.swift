import Foundation

/// The step-zero focus section. Pure: it opens no store, starts no tool, and keeps no name.
///
/// The caller feeds the grant, the record bytes, and the milliseconds it waited. Three fields of a
/// live record become yes or no, and the strings are dropped. A history list is not read. The
/// reader file, the watch file, and the focus lint stay out of this file.
public enum FocusSection {
    /// One store file. Larger input is refused before a parse.
    public static let maxBytes = 4 * 1024 * 1024
    /// Live records past this count are not read.
    public static let maxRecords = 64
    /// The stamp check. A folder source misses a file rewritten in place, so this still runs.
    public static let pollMilliseconds = 250
    /// Change windows, counted from the owner's press.
    public static let earlyWindowMilliseconds = 2_000
    public static let midWindowMilliseconds = 10_000
    public static let lateWindowMilliseconds = 30_000
    /// One tool. Only the exit status comes back.
    public static let toolLimitMilliseconds = 5_000
    /// One grant flip. The run still ends on the grant it started with when this expires.
    public static let grantWatchMilliseconds = 30_000
    /// The only object key this section reads. Every other key, including a history list, is skipped.
    public static let liveRecordsKey = "storeAssertionRecords"

    /// Presence only. A name, a symbol string, and a person list have no field here.
    public struct Fact: Sendable, Equatable {
        public var hasModeId: Bool
        public var hasName: Bool
        public var hasSymbol: Bool

        public init(hasModeId: Bool, hasName: Bool, hasSymbol: Bool) {
            self.hasModeId = hasModeId
            self.hasName = hasName
            self.hasSymbol = hasSymbol
        }
    }

    public enum DecodeResult: Sendable, Equatable {
        case live([Fact])
        case off
        case tooLarge
        case malformed
    }

    public enum Grant: String, Sendable, Equatable {
        case on
        case off
    }

    public enum SeenBy: String, Sendable, Equatable {
        case fileEvent
        case folderEvent
        case poll
    }

    public enum ChangeWindow: String, Sendable, Equatable {
        case w2s
        case w10s
        case w30s
        case none
    }

    public enum WriteShape: String, Sendable, Equatable {
        case replaced
        case inPlace
        case unknown
    }

    public enum Answer: String, Sendable, Equatable {
        case yes
        case no
        case notTried
    }

    public enum ChildRead: String, Sendable, Equatable {
        case yes
        case no
        case noGrant
        case timedOut
    }

    public enum Errno: String, Sendable, Equatable {
        case denied
        case missing
        case other
    }

    public enum StoreFile: String, Sendable, Equatable {
        case assertions
        case configurations
    }

    public enum Step: String, Sendable, Equatable {
        case files
        case watch
        case counts
        case inodes
        case schedule
        case phone
        case mirror
        case tool
        case flipOff
        case errno
        case prompt
        case flipOn
    }

    /// The grant at the start picks the order. Off reads the error first, then turns on.
    /// On measures first, turns off, reads the error, and turns back on. Both end where they began.
    public static func script(starting grant: Grant) -> [Step] {
        let measure: [Step] = [.files, .watch, .counts, .inodes, .schedule, .phone, .mirror, .tool]
        switch grant {
        case .on:
            return measure + [.flipOff, .errno, .prompt, .flipOn]
        case .off:
            return [.errno, .prompt, .flipOn] + measure + [.flipOff]
        }
    }

    public static func changeWindow(milliseconds: Int) -> ChangeWindow {
        if milliseconds <= earlyWindowMilliseconds { return .w2s }
        if milliseconds <= midWindowMilliseconds { return .w10s }
        if milliseconds <= lateWindowMilliseconds { return .w30s }
        return .none
    }

    public static func writeShape(before: UInt64?, after: UInt64?) -> WriteShape {
        guard let before, let after else { return .unknown }
        return before == after ? .inPlace : .replaced
    }

    /// Exit status only. There is no text argument.
    public static func childRead(exit: Int) -> ChildRead {
        exit == 0 ? .yes : .no
    }

    /// Decodes at most three presence bits per live record. The bytes are not returned.
    public static func decode(_ data: Data) -> DecodeResult {
        if data.count > maxBytes { return .tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed
        }
        guard let raw = object[liveRecordsKey] else { return .off }
        if raw is NSNull { return .off }
        guard let records = raw as? [Any] else { return .malformed }
        if records.isEmpty { return .off }
        var facts: [Fact] = []
        for record in records {
            if facts.count == maxRecords { break }
            guard let row = record as? [String: Any] else { continue }
            facts.append(
                Fact(
                    hasModeId: present(row["modeId"]),
                    hasName: present(row["name"]),
                    hasSymbol: present(row["symbol"])
                )
            )
        }
        if facts.isEmpty { return .off }
        return .live(facts)
    }

    public enum Effect: Sendable, Equatable {
        case readGrant
        case readStore(StoreFile)
        case armFileSource
        case armFolderSource
        case pollStamp
        case reopenFileSource
        case stopWatch
        case readCounts
        case compareInodes
        case readSchedule
        case readPhone
        case readMirror
        case readSelf
        case runTool
        case readErrno
        case askPrompt
        case setGrant(Grant)
    }

    public enum Phase: String, Sendable, Equatable {
        case idle
        case awaitGrant
        case gate
        case awaitFiles
        case watching
        case awaitCounts
        case awaitInodes
        case awaitSchedule
        case awaitPhone
        case awaitMirror
        case awaitSelf
        case awaitTool
        case awaitFlip
        case awaitErrno
        case awaitPrompt
        case done
    }

    public enum Event: Sendable, Equatable {
        case begin
        case grant(Grant)
        case continueAsked
        case files(assertions: Bool, configurations: Bool)
        case pressStart
        case fileRewritten
        case fileReplaced
        case folderEvent
        case sources(file: Bool, folder: Bool)
        case stampChanged
        case waited(milliseconds: Int)
        case counts(modes: Int, withName: Int, withSymbol: Int, symbolsResolve: Int)
        case inodes(before: UInt64?, after: UInt64?)
        case schedule(Answer)
        case phone(Answer)
        case mirror(recordWhileNoFocus: Bool, carriesModeId: Bool)
        case withinSecond(Bool)
        case record(Data)
        case selfCanRead(Bool)
        case tool(exit: Int)
        case errno(Errno)
        case prompt(seen: Bool, listed: Bool)
        case grantFlipped(Grant)
    }

    public struct State: Sendable, Equatable {
        public var phase: Phase
        public var script: [Step]
        public var cursor: Int
        public var grantAtStart: Grant?
        public var grantNow: Grant?
        public var endedGrant: Grant?
        public var grantLive: Bool?
        public var assertionsExist: Bool?
        public var configurationsExist: Bool?
        public var facts: [Fact]
        public var decode: DecodeResult?
        public var pressed: Bool
        public var changeSeen: Bool
        public var seenBy: SeenBy?
        public var changedWithin: ChangeWindow?
        public var withinASecond: Bool?
        public var clockMs: Int
        public var fileSource: Bool
        public var folderSource: Bool
        public var reopened: Bool
        public var modes: Int?
        public var withName: Int?
        public var withSymbol: Int?
        public var symbolsResolve: Int?
        public var write: WriteShape?
        public var schedule: Answer?
        public var phone: Answer?
        public var recordWhileNoFocus: Bool?
        public var carriesModeId: Bool?
        public var selfCanRead: Bool?
        public var childCanRead: ChildRead?
        public var errno: Errno?
        public var promptSeen: Bool?
        public var listed: Bool?

        public init() {
            phase = .idle
            script = []
            cursor = 0
            grantAtStart = nil
            grantNow = nil
            endedGrant = nil
            grantLive = nil
            assertionsExist = nil
            configurationsExist = nil
            facts = []
            decode = nil
            pressed = false
            changeSeen = false
            seenBy = nil
            changedWithin = nil
            withinASecond = nil
            clockMs = 0
            fileSource = false
            folderSource = false
            reopened = false
            modes = nil
            withName = nil
            withSymbol = nil
            symbolsResolve = nil
            write = nil
            schedule = nil
            phone = nil
            recordWhileNoFocus = nil
            carriesModeId = nil
            selfCanRead = nil
            childCanRead = nil
            errno = nil
            promptSeen = nil
            listed = nil
        }
    }

    public static func fresh() -> State { State() }

    public static func reduce(_ state: State, _ event: Event) -> (state: State, effects: [Effect]) {
        var state = state
        var effects: [Effect] = []
        switch event {
        case .begin:
            begin(&state, &effects)
        case .grant(let grant):
            grantRead(grant, &state, &effects)
        case .continueAsked:
            continueAsked(&state, &effects)
        case .files(let assertions, let configurations):
            files(assertions, configurations, &state, &effects)
        case .pressStart:
            pressStart(&state)
        case .fileRewritten:
            seeFile(replaced: false, &state, &effects)
        case .fileReplaced:
            seeFile(replaced: true, &state, &effects)
        case .folderEvent:
            break
        case .sources(let file, let folder):
            sources(file, folder, &state)
        case .stampChanged:
            stampChanged(&state)
        case .waited(let milliseconds):
            waited(milliseconds, &state, &effects)
        case .counts(let modes, let withName, let withSymbol, let symbolsResolve):
            counts(modes, withName, withSymbol, symbolsResolve, &state, &effects)
        case .inodes(let before, let after):
            inodes(before, after, &state, &effects)
        case .schedule(let answer):
            schedule(answer, &state, &effects)
        case .phone(let answer):
            phone(answer, &state, &effects)
        case .mirror(let recordWhileNoFocus, let carriesModeId):
            mirror(recordWhileNoFocus, carriesModeId, &state, &effects)
        case .withinSecond(let answer):
            withinSecond(answer, &state, &effects)
        case .record(let data):
            record(data, &state)
        case .selfCanRead(let value):
            selfCanRead(value, &state, &effects)
        case .tool(let exit):
            tool(exit, &state, &effects)
        case .errno(let errno):
            errnoRead(errno, &state, &effects)
        case .prompt(let seen, let listed):
            prompt(seen, listed, &state, &effects)
        case .grantFlipped(let grant):
            grantFlipped(grant, &state, &effects)
        }
        return (state, effects)
    }

    private static func present(_ value: Any?) -> Bool {
        guard let text = value as? String else { return false }
        return text.isEmpty == false
    }

    private static func begin(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .idle else { return }
        state.phase = .awaitGrant
        effects.append(.readGrant)
    }

    private static func grantRead(_ grant: Grant, _ state: inout State, _: inout [Effect]) {
        guard state.phase == .awaitGrant else { return }
        state.grantAtStart = grant
        state.grantNow = grant
        state.script = script(starting: grant)
        state.cursor = 0
        enter(&state)
    }

    private static func continueAsked(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .gate, state.cursor < state.script.count else { return }
        switch state.script[state.cursor] {
        case .files:
            state.phase = .awaitFiles
            effects.append(.readStore(.assertions))
            effects.append(.readStore(.configurations))
        case .watch:
            state.phase = .watching
            state.clockMs = 0
            state.pressed = false
            state.changeSeen = false
            state.seenBy = nil
            state.changedWithin = nil
            state.fileSource = true
            state.folderSource = true
            state.reopened = false
            effects.append(.armFileSource)
            effects.append(.armFolderSource)
            effects.append(.pollStamp)
        case .counts:
            state.phase = .awaitCounts
            effects.append(.readCounts)
        case .inodes:
            state.phase = .awaitInodes
            effects.append(.compareInodes)
        case .schedule:
            state.phase = .awaitSchedule
            effects.append(.readSchedule)
        case .phone:
            state.phase = .awaitPhone
            effects.append(.readPhone)
        case .mirror:
            state.phase = .awaitMirror
            effects.append(.readMirror)
        case .tool:
            if state.grantNow != .on {
                state.childCanRead = .noGrant
                complete(&state, &effects)
                return
            }
            state.phase = .awaitSelf
            state.clockMs = 0
            effects.append(.readSelf)
        case .flipOff:
            state.phase = .awaitFlip
            state.clockMs = 0
            effects.append(.setGrant(.off))
        case .flipOn:
            state.phase = .awaitFlip
            state.clockMs = 0
            effects.append(.setGrant(.on))
        case .errno:
            state.phase = .awaitErrno
            effects.append(.readErrno)
        case .prompt:
            state.phase = .awaitPrompt
            effects.append(.askPrompt)
        }
    }

    private static func files(
        _ assertions: Bool,
        _ configurations: Bool,
        _ state: inout State,
        _ effects: inout [Effect]
    ) {
        guard state.phase == .awaitFiles else { return }
        state.assertionsExist = assertions
        state.configurationsExist = configurations
        complete(&state, &effects)
    }

    private static func pressStart(_ state: inout State) {
        guard state.phase == .watching, state.pressed == false else { return }
        state.pressed = true
        state.clockMs = 0
    }

    private static func sources(_ file: Bool, _ folder: Bool, _ state: inout State) {
        guard state.phase == .watching else { return }
        state.fileSource = file
        state.folderSource = folder
    }

    private static func seeFile(replaced: Bool, _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .watching, state.pressed, state.changeSeen == false else { return }
        if replaced {
            if state.fileSource {
                note(.fileEvent, &state)
                effects.append(.reopenFileSource)
                state.reopened = true
            } else if state.folderSource {
                note(.folderEvent, &state)
                effects.append(.reopenFileSource)
                state.reopened = true
            }
            return
        }
        if state.fileSource {
            note(.fileEvent, &state)
        }
    }

    private static func stampChanged(_ state: inout State) {
        guard state.phase == .watching, state.pressed, state.changeSeen == false else { return }
        guard state.clockMs >= pollMilliseconds else { return }
        note(.poll, &state)
    }

    private static func note(_ seen: SeenBy, _ state: inout State) {
        state.changeSeen = true
        state.seenBy = seen
        state.changedWithin = changeWindow(milliseconds: state.clockMs)
    }

    private static func waited(_ milliseconds: Int, _ state: inout State, _ effects: inout [Effect]) {
        guard milliseconds > 0 else { return }
        switch state.phase {
        case .watching, .awaitTool, .awaitFlip:
            state.clockMs += milliseconds
            applyClock(&state, &effects)
        default:
            break
        }
    }

    private static func applyClock(_ state: inout State, _ effects: inout [Effect]) {
        switch state.phase {
        case .awaitTool:
            if state.clockMs >= toolLimitMilliseconds, state.childCanRead == nil {
                state.childCanRead = .timedOut
                complete(&state, &effects)
            }
        case .awaitFlip:
            if state.clockMs >= grantWatchMilliseconds {
                state.grantLive = false
                complete(&state, &effects)
            }
        default:
            break
        }
    }

    private static func counts(
        _ modes: Int,
        _ withName: Int,
        _ withSymbol: Int,
        _ symbolsResolve: Int,
        _ state: inout State,
        _ effects: inout [Effect]
    ) {
        guard state.phase == .awaitCounts else { return }
        guard modes >= 0, withName >= 0, withSymbol >= 0, symbolsResolve >= 0 else { return }
        state.modes = modes
        state.withName = withName
        state.withSymbol = withSymbol
        state.symbolsResolve = symbolsResolve
        complete(&state, &effects)
    }

    private static func inodes(
        _ before: UInt64?,
        _ after: UInt64?,
        _ state: inout State,
        _ effects: inout [Effect]
    ) {
        guard state.phase == .awaitInodes else { return }
        state.write = writeShape(before: before, after: after)
        complete(&state, &effects)
    }

    private static func schedule(_ answer: Answer, _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .awaitSchedule else { return }
        state.schedule = answer
        complete(&state, &effects)
    }

    private static func phone(_ answer: Answer, _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .awaitPhone else { return }
        state.phone = answer
        complete(&state, &effects)
    }

    private static func mirror(
        _ recordWhileNoFocus: Bool,
        _ carriesModeId: Bool,
        _ state: inout State,
        _ effects: inout [Effect]
    ) {
        guard state.phase == .awaitMirror else { return }
        state.recordWhileNoFocus = recordWhileNoFocus
        state.carriesModeId = carriesModeId
        complete(&state, &effects)
    }

    private static func withinSecond(_ answer: Bool, _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .watching else { return }
        state.withinASecond = answer
        effects.append(.stopWatch)
        complete(&state, &effects)
    }

    private static func record(_ data: Data, _ state: inout State) {
        guard state.phase == .watching || state.phase == .awaitFiles else { return }
        let decoded = decode(data)
        state.decode = decoded
        if case .live(let facts) = decoded {
            state.facts = facts
        } else {
            state.facts = []
        }
    }

    private static func selfCanRead(_ value: Bool, _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .awaitSelf else { return }
        state.selfCanRead = value
        state.phase = .awaitTool
        state.clockMs = 0
        effects.append(.runTool)
    }

    private static func tool(_ exit: Int, _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .awaitTool, state.childCanRead == nil else { return }
        state.childCanRead = childRead(exit: exit)
        complete(&state, &effects)
    }

    private static func errnoRead(_ errno: Errno, _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .awaitErrno else { return }
        state.errno = errno
        complete(&state, &effects)
    }

    private static func prompt(
        _ seen: Bool,
        _ listed: Bool,
        _ state: inout State,
        _ effects: inout [Effect]
    ) {
        guard state.phase == .awaitPrompt else { return }
        state.promptSeen = seen
        state.listed = listed
        complete(&state, &effects)
    }

    private static func grantFlipped(_ grant: Grant, _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .awaitFlip, state.cursor < state.script.count else { return }
        let expected: Grant = state.script[state.cursor] == .flipOn ? .on : .off
        guard grant == expected else { return }
        state.grantNow = grant
        state.grantLive = true
        complete(&state, &effects)
    }

    private static func complete(_ state: inout State, _ effects: inout [Effect]) {
        state.cursor += 1
        state.clockMs = 0
        enter(&state)
    }

    private static func enter(_ state: inout State) {
        while state.cursor < state.script.count {
            if shouldSkip(state.script[state.cursor], state) {
                state.cursor += 1
                continue
            }
            state.phase = .gate
            return
        }
        state.phase = .done
        state.endedGrant = state.grantNow
    }

    private static func shouldSkip(_ step: Step, _ state: State) -> Bool {
        switch step {
        case .errno, .prompt:
            return state.grantNow != .off
        case .flipOff:
            return state.grantNow == .off
        case .flipOn:
            return state.grantNow == .on
        case .files, .watch, .counts, .inodes, .schedule, .phone, .mirror, .tool:
            return false
        }
    }
}
