/// The cached Apple Events consent answer for one target app, with a generation.
///
/// A background `ask: false` check and an explicit Allow click both write the same cache entry. The check
/// can start before the click and finish after it, and its answer ("would require consent") then
/// overwrote the grant the click had just stored, and the persisted grant was deleted until the next
/// refresh. Each entry now carries a generation. The generation moves when a prompt begins and when it
/// is answered, every check remembers the generation it started in, and a result from an older
/// generation is dropped.
public enum AutomationConsentCache {
    /// OSStatus values, spelled out so the model needs no CoreServices.
    public static let noError: Int32 = 0
    public static let notPermitted: Int32 = -1743
    public static let wouldRequireConsent: Int32 = -1744

    /// Seconds a resolved answer stays fresh, and how long a "still deciding" answer waits before a recheck.
    public static let resolvedTTL: Double = 20
    public static let pendingRecheck: Double = 5

    public enum Entry: Equatable, Sendable {
        case resolved(code: Int32, at: Double)
        case pending(at: Double)
    }

    public struct State: Equatable, Sendable {
        public var generation: UInt64 = 0
        public var entry: Entry?
        /// One background check at a time.
        public var checking = false

        public init() {}

        public enum Status: Equatable, Sendable {
            case granted
            case denied(code: Int32)
            case pending
        }

        /// What callers see right now. An expired answer reads as pending until the next check lands.
        public func status(now: Double) -> Status {
            guard let entry else { return .pending }
            switch entry {
            case .resolved(let code, let at):
                guard now - at < AutomationConsentCache.resolvedTTL else { return .pending }
                return code == AutomationConsentCache.noError ? .granted : .denied(code: code)
            case .pending:
                return .pending
            }
        }
    }

    public enum Event: Equatable, Sendable {
        /// Someone read the status and a check may be needed.
        case checkWanted(now: Double)
        /// The check that started in `generation` has not answered within its time bound.
        case checkSlow(generation: UInt64, now: Double)
        /// The check thread ended. `code` is nil when it never produced an answer.
        case checkEnded(generation: UInt64, code: Int32?, now: Double)
        /// The consent sheet is about to be raised for this app.
        case promptBegan
        /// The person answered the consent sheet.
        case promptAnswered(code: Int32, now: Double)
    }

    public enum Effect: Equatable, Sendable {
        /// Run the non-prompting check; report it with the same generation.
        case startCheck(generation: UInt64)
        /// Persist the grant: it survives the app quitting.
        case rememberGrant
        /// macOS reports it revoked or never given.
        case forgetGrant
    }

    public static func reduce(_ state: State, _ event: Event) -> (State, [Effect]) {
        var next = state
        switch event {
        case .checkWanted(let now):
            guard !state.checking else { return (state, []) }
            if let entry = state.entry {
                switch entry {
                case .resolved(_, let at) where now - at < resolvedTTL: return (state, [])
                case .pending(let at) where now - at < pendingRecheck: return (state, [])
                default: break
                }
            }
            next.checking = true
            return (next, [.startCheck(generation: state.generation)])

        case .checkSlow(let generation, let now):
            guard generation == state.generation else { return (state, []) }
            next.entry = .pending(at: now)
            return (next, [])

        case .checkEnded(let generation, let code, let now):
            next.checking = false
            guard generation == state.generation, let code else { return (next, []) }
            next.entry = .resolved(code: code, at: now)
            return (next, effects(for: code))

        case .promptBegan:
            next.generation &+= 1
            return (next, [])

        case .promptAnswered(let code, let now):
            next.generation &+= 1
            next.entry = .resolved(code: code, at: now)
            return (next, effects(for: code))
        }
    }

    private static func effects(for code: Int32) -> [Effect] {
        if code == noError { return [.rememberGrant] }
        if code == notPermitted || code == wouldRequireConsent { return [.forgetGrant] }
        return []
    }
}
