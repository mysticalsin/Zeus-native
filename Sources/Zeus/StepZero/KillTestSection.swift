/// The step-zero kill test section. Pure: it starts no child, ends no process,
/// destroys no space, and keeps no boot mark.
///
/// The caller feeds the two row marks, a lock, a census, the four orphan flags,
/// and two boot marks. A boot mark is compared and the characters are dropped.
/// The journal file, the launch file, and the clean-room comment stay out.
public enum KillTestSection {
    /// The self-kill wait. A shorter wait does not end the process.
    public static let selfKillMilliseconds = 5_000
    /// The hold after unlock. A shorter wait does not destroy the space.
    public static let holdMilliseconds = 60_000

    public enum RowMark: String, Sendable, Equatable {
        case done
        case skipped
        case open
    }

    public enum Variant: String, Sendable, Equatable {
        case selfKill
        case hold
    }

    public enum Answer: String, Sendable, Equatable {
        case yes
        case no
        case notTried
        case unanswered
    }

    public enum PartMark: String, Sendable, Equatable {
        case ran
        case skipped
    }

    /// The four flags of the orphan rule. A path is never accepted.
    public struct OrphanSight: Sendable, Equatable {
        public var vendorInterpreter: Bool
        public var parentIsOne: Bool
        public var sameUser: Bool
        public var libraryMatches: Bool

        public init(vendorInterpreter: Bool, parentIsOne: Bool, sameUser: Bool, libraryMatches: Bool) {
            self.vendorInterpreter = vendorInterpreter
            self.parentIsOne = parentIsOne
            self.sameUser = sameUser
            self.libraryMatches = libraryMatches
        }
    }

    /// True only when every flag holds. One miss is a no.
    public static func orphanHolds(_ sight: OrphanSight) -> Bool {
        sight.vendorInterpreter && sight.parentIsOne && sight.sameUser && sight.libraryMatches
    }

    public struct Fact: Sendable, Equatable {
        public var journalBeforeKill: Bool
        public var orphanAfterKill: Answer
        public var windowGone: Answer
        public var censusLeftover: Bool?
        public var cardGone: Answer
        public var forceQuit: Answer
        public var spaceDestroyed: Bool
        public var bootReads: Answer
        public var bootChanged: Answer

        public init(
            journalBeforeKill: Bool,
            orphanAfterKill: Answer = .unanswered,
            windowGone: Answer = .unanswered,
            censusLeftover: Bool? = nil,
            cardGone: Answer = .unanswered,
            forceQuit: Answer = .unanswered,
            spaceDestroyed: Bool = false,
            bootReads: Answer = .unanswered,
            bootChanged: Answer = .unanswered
        ) {
            self.journalBeforeKill = journalBeforeKill
            self.orphanAfterKill = orphanAfterKill
            self.windowGone = windowGone
            self.censusLeftover = censusLeftover
            self.cardGone = cardGone
            self.forceQuit = forceQuit
            self.spaceDestroyed = spaceDestroyed
            self.bootReads = bootReads
            self.bootChanged = bootChanged
        }
    }

    public enum Effect: Sendable, Equatable {
        case startChild
        case askLock
        case showCard
        case writeJournal
        case endProcess
        case destroySpace
        case askCardGone
    }

    public enum Phase: String, Sendable, Equatable {
        case idle
        case gate
        case locking
        case holding
        case ended
        case asking
        case done
    }

    public enum Event: Sendable, Equatable {
        case begin(systemSource: RowMark, lockScreen: RowMark, variant: Variant)
        case continueAsked
        case skip
        case locked
        case waited(milliseconds: Int)
        case ownerQuit
        case resume(leftover: Bool, orphan: OrphanSight)
        case cardGone(Bool)
        case boot(previous: String, current: String)
    }

    public struct State: Sendable, Equatable {
        public var phase: Phase
        public var variant: Variant?
        public var mark: PartMark?
        public var fact: Fact?
        public var clockMs: Int
        public var journalWritten: Bool

        public init() {
            phase = .idle
            variant = nil
            mark = nil
            fact = nil
            clockMs = 0
            journalWritten = false
        }
    }

    public static func fresh() -> State { State() }

    public static func reduce(_ state: State, _ event: Event) -> (state: State, effects: [Effect]) {
        var state = state
        var effects: [Effect] = []
        switch event {
        case .begin(let systemSource, let lockScreen, let variant):
            begin(systemSource, lockScreen, variant, &state)
        case .continueAsked:
            continueAsked(&state, &effects)
        case .skip:
            skip(&state)
        case .locked:
            locked(&state, &effects)
        case .waited(let milliseconds):
            waited(milliseconds, &state, &effects)
        case .ownerQuit:
            ownerQuit(&state, &effects)
        case .resume(let leftover, let orphan):
            resume(leftover, orphan, &state, &effects)
        case .cardGone(let gone):
            cardGone(gone, &state)
        case .boot(let previous, let current):
            boot(previous, current, &state)
        }
        return (state, effects)
    }

    private static func begin(_ systemSource: RowMark, _ lockScreen: RowMark, _ variant: Variant, _ state: inout State) {
        guard state.phase == .idle, rowsReady(systemSource, lockScreen) else { return }
        state.variant = variant
        state.phase = .gate
    }

    private static func rowsReady(_ systemSource: RowMark, _ lockScreen: RowMark) -> Bool {
        systemSource != .open && lockScreen != .open
    }

    private static func continueAsked(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .gate, let variant = state.variant else { return }
        switch variant {
        case .selfKill:
            state.phase = .locking
            effects.append(.startChild)
            effects.append(.askLock)
        case .hold:
            armHold(&state, &effects)
        }
    }

    private static func skip(_ state: inout State) {
        guard state.phase == .gate else { return }
        state.mark = .skipped
        state.phase = .done
    }

    private static func locked(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .locking, state.variant == .selfKill else { return }
        state.phase = .holding
        state.clockMs = 0
        state.journalWritten = true
        effects.append(.showCard)
        effects.append(.writeJournal)
    }

    private static func armHold(_ state: inout State, _ effects: inout [Effect]) {
        state.phase = .holding
        state.clockMs = 0
        state.journalWritten = true
        effects.append(.showCard)
        effects.append(.writeJournal)
    }

    private static func waited(_ milliseconds: Int, _ state: inout State, _ effects: inout [Effect]) {
        guard milliseconds > 0, state.phase == .holding, let variant = state.variant else { return }
        let sum = state.clockMs.addingReportingOverflow(milliseconds)
        state.clockMs = sum.overflow ? Int.max : sum.partialValue
        switch variant {
        case .selfKill:
            if state.clockMs >= selfKillMilliseconds {
                endSelf(&state, &effects)
            }
        case .hold:
            if state.clockMs >= holdMilliseconds {
                destroy(&state, &effects, quit: .notTried)
            }
        }
    }

    private static func ownerQuit(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .holding, state.variant == .hold else { return }
        destroy(&state, &effects, quit: .yes)
    }

    private static func endSelf(_ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .holding, state.variant == .selfKill, state.journalWritten else { return }
        state.fact = Fact(journalBeforeKill: true)
        state.mark = .ran
        state.phase = .ended
        state.clockMs = 0
        effects.append(.endProcess)
    }

    private static func destroy(_ state: inout State, _ effects: inout [Effect], quit: Answer) {
        guard state.phase == .holding, state.variant == .hold, state.journalWritten else { return }
        state.fact = Fact(journalBeforeKill: true, forceQuit: quit, spaceDestroyed: true)
        state.mark = .ran
        state.phase = .ended
        state.clockMs = 0
        effects.append(.destroySpace)
    }

    private static func resume(_ leftover: Bool, _ orphan: OrphanSight, _ state: inout State, _ effects: inout [Effect]) {
        guard state.phase == .ended, state.journalWritten, var fact = state.fact, fact.journalBeforeKill else { return }
        fact.orphanAfterKill = orphanHolds(orphan) ? .yes : .no
        fact.windowGone = leftover ? .no : .yes
        fact.censusLeftover = leftover
        state.fact = fact
        state.phase = .asking
        effects.append(.askCardGone)
    }

    private static func cardGone(_ gone: Bool, _ state: inout State) {
        guard state.phase == .asking, var fact = state.fact else { return }
        fact.cardGone = gone ? .yes : .no
        state.fact = fact
        state.phase = .done
    }

    private static func boot(_ previous: String, _ current: String, _ state: inout State) {
        guard state.mark == .ran, var fact = state.fact, fact.journalBeforeKill, fact.bootReads == .unanswered else { return }
        if let previous = foldedBoot(previous), let current = foldedBoot(current) {
            fact.bootReads = .yes
            fact.bootChanged = previous == current ? .no : .yes
        } else {
            fact.bootReads = .no
        }
        state.fact = fact
    }

    /// Sixteen hex digits, folded. Anything else is not a mark, and the text is not kept.
    private static func foldedBoot(_ text: String) -> String? {
        guard text.count == 16, text.utf8.count == 16 else { return nil }
        let folded = text.lowercased()
        let hex = folded.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
        return hex ? folded : nil
    }
}
