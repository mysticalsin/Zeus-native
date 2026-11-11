import Foundation

/// Local estimate-based guard for paid Jev calls. The input-only rate below is a project tariff
/// assumption, not a provider-enforced billing limit; output pricing and model-specific rates are
/// not represented here. Provider-side spend controls are authoritative.
public struct JevBudget: Codable, Equatable, Sendable {
    public static let dollarsPerMillionInput = 0.042
    /// Unset means no paid calls at all.
    public var monthlyCap: Double?
    public private(set) var month: String
    public private(set) var spent: Double
    public private(set) var calls: Int
    public private(set) var inputTokens: Int

    public init(monthlyCap: Double?, now: Date = Date()) {
        self.monthlyCap = monthlyCap
        month = Self.monthKey(now)
        spent = 0; calls = 0; inputTokens = 0
    }

    public static func monthKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    public static func cost(inputTokens: Int) -> Double { Double(inputTokens) * dollarsPerMillionInput / 1_000_000 }

    /// Starts a fresh month when the calendar has moved on.
    public mutating func roll(now: Date = Date()) {
        let key = Self.monthKey(now)
        guard key != month else { return }
        month = key; spent = 0; calls = 0; inputTokens = 0
    }

    /// Whether a call of about `estimatedTokens` input tokens may go out now.
    public mutating func allows(estimatedTokens: Int, now: Date = Date()) -> Bool {
        allows(estimatedTokens: estimatedTokens, reservedTokens: 0, now: now)
    }

    /// Whether a call may go out after accounting for other in-flight calls on the same guard.
    public mutating func allows(estimatedTokens: Int, reservedTokens: Int, now: Date = Date()) -> Bool {
        roll(now: now)
        guard let cap = monthlyCap, cap > 0, estimatedTokens >= 0, reservedTokens >= 0 else { return false }
        let (totalTokens, overflow) = estimatedTokens.addingReportingOverflow(reservedTokens)
        guard !overflow else { return false }
        return spent + Self.cost(inputTokens: totalTokens) <= min(cap, JevBudgetStore.maxCap)
    }

    public mutating func record(inputTokens tokens: Int, now: Date = Date()) {
        roll(now: now)
        inputTokens += tokens
        calls += 1
        spent += Self.cost(inputTokens: tokens)
    }

    public var isCapped: Bool { guard let cap = monthlyCap else { return true }; return spent >= cap }

    /// "Jev $0.03 of $10" for the Usage tab.
    public var summary: String {
        guard let cap = monthlyCap else { return "Jev off (no monthly estimate cap set)" }
        return String(format: "Jev $%.2f of $%.0f", spent, cap)
    }
}

private final class JevBudgetProcessLock: @unchecked Sendable {
    let value = NSLock()
    var activeReservations = Set<UUID>()
}

/// A test-only byte store. Access is protected by `JevBudgetStore.processLock`.
private final class JevBudgetMemoryStorage: @unchecked Sendable {
    var data: Data?
}

/// Stores the local budget and one pending request in UserDefaults; the lock coordinates this process only.
public struct JevBudgetStore: Sendable {
    public static let key = "jev.budget"
    public static let defaultCap = 10.0
    /// The local ceiling no setting can raise: US$10 a month.
    public static let maxCap = 10.0
    /// Coordinates JevBudgetStore instances in this process. UserDefaults has no cross-process CAS.
    private static let processLock = JevBudgetProcessLock()
    let suite: String?
    private let memoryStorage: JevBudgetMemoryStorage?

    public init(suite: String? = nil) {
        self.suite = suite
        memoryStorage = nil
    }

    private init(memoryStorage: JevBudgetMemoryStorage) {
        suite = nil
        self.memoryStorage = memoryStorage
    }

    #if DEBUG
    /// Creates a volatile-only store for the debug Jev Settings harness. It never reads or writes
    /// any UserDefaults domain, including the app's normal `app.zeus.mac` preferences.
    public static func inMemoryForTesting() -> JevBudgetStore {
        JevBudgetStore(memoryStorage: JevBudgetMemoryStorage())
    }

    /// Seeds only synthetic usage and an uncertain request in the volatile test store.
    @discardableResult
    public func seedReconciliationFixtureForTesting(now: Date = Date()) -> Bool {
        guard memoryStorage != nil else { return false }
        Self.processLock.value.lock(); defer { Self.processLock.value.unlock() }
        var budget = JevBudget(monthlyCap: Self.defaultCap, now: now)
        budget.roll(now: now)
        let snapshot = LedgerSnapshot(
            budget: budget,
            pending: PendingReservation(id: UUID(), estimatedInputTokens: 100, requiresReconciliation: true)
        )
        return saveSnapshotUnlocked(snapshot)
    }

    var isVolatileForTesting: Bool { memoryStorage != nil }
    #endif

    var defaults: UserDefaults { suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    private struct PendingReservation: Codable {
        let id: UUID
        let estimatedInputTokens: Int
        var requiresReconciliation: Bool
    }

    private struct LedgerSnapshot: Codable {
        var budget: JevBudget
        var pending: PendingReservation?
        /// True once a cap choice was saved on purpose, including "no cap" (Remove). Older payloads
        /// lack it, so a stored nil cap without it means the owner never chose and gets the default.
        var capChosen: Bool?

        /// Applies the default cap to a ledger whose owner never chose one. Never changes a chosen cap.
        func withDefaultCapIfNeverChosen() -> LedgerSnapshot {
            guard capChosen != true, budget.monthlyCap == nil else { return self }
            var copy = self
            copy.budget.monthlyCap = JevBudgetStore.defaultCap
            return copy
        }
    }

    enum ReservationAttempt {
        case reserved(JevBudget)
        case capReached(JevBudget)
        case inFlight
        case reconciliationRequired
    }

    public enum ReservationStatus: Equatable, Sendable {
        case clear, inFlight, reconciliationRequired
    }

    public enum ReservationResolution: Equatable, Sendable {
        case billed(inputTokens: Int)
        case confirmedUnbilled
    }

    public func load() -> JevBudget {
        Self.processLock.value.lock(); defer { Self.processLock.value.unlock() }
        return loadUnlocked()
    }

    private func loadUnlocked() -> JevBudget {
        readSnapshotUnlocked().snapshot.budget
    }

    private func readSnapshotUnlocked() -> (snapshot: LedgerSnapshot, isCorrupt: Bool) {
        guard let data = storedDataUnlocked() else {
            return (LedgerSnapshot(budget: JevBudget(monthlyCap: Self.defaultCap), pending: nil), false)
        }
        if let snapshot = try? JSONDecoder().decode(LedgerSnapshot.self, from: data) {
            return (snapshot.withDefaultCapIfNeverChosen(), false)
        }
        // Migrate the old single-budget payload without losing existing month-to-date usage.
        if let budget = try? JSONDecoder().decode(JevBudget.self, from: data) {
            return (LedgerSnapshot(budget: budget, pending: nil).withDefaultCapIfNeverChosen(), false)
        }
        return (LedgerSnapshot(budget: JevBudget(monthlyCap: Self.defaultCap), pending: nil), true)
    }

    @discardableResult
    private func saveSnapshotUnlocked(_ snapshot: LedgerSnapshot) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        if let memoryStorage {
            memoryStorage.data = data
            return true
        }
        defaults.set(data, forKey: Self.key)
        return defaults.synchronize()
    }

    private func storedDataUnlocked() -> Data? {
        if let memoryStorage { return memoryStorage.data }
        return defaults.data(forKey: Self.key)
    }

    public func save(_ budget: JevBudget) {
        Self.processLock.value.lock(); defer { Self.processLock.value.unlock() }
        var read = readSnapshotUnlocked()
        guard !read.isCorrupt else { return }
        read.snapshot.budget = budget
        read.snapshot.capChosen = true
        saveSnapshotUnlocked(read.snapshot)
    }

    /// Updates only the cap on the latest stored budget, so a guard with a stale snapshot cannot
    /// overwrite usage recorded by another request since that guard was created.
    func updateCap(_ cap: Double?) -> JevBudget? {
        Self.processLock.value.lock(); defer { Self.processLock.value.unlock() }
        var read = readSnapshotUnlocked()
        guard !read.isCorrupt else { return nil }
        read.snapshot.budget.monthlyCap = cap.map { min(max($0, 0), Self.maxCap) }
        read.snapshot.capChosen = true
        guard saveSnapshotUnlocked(read.snapshot) else { return nil }
        return read.snapshot.budget
    }

    /// Reserves one Jev request within this process against the stored local estimate.
    /// A pending record from another guard blocks calls until its billing outcome is reconciled.
    func reserve(id: UUID, estimatedInputTokens: Int, now: Date = Date()) -> ReservationAttempt {
        Self.processLock.value.lock(); defer { Self.processLock.value.unlock() }
        var read = readSnapshotUnlocked()
        guard !read.isCorrupt else { return .reconciliationRequired }
        if var pending = read.snapshot.pending {
            if Self.processLock.activeReservations.contains(pending.id) { return .inFlight }
            if !pending.requiresReconciliation {
                pending.requiresReconciliation = true
                read.snapshot.pending = pending
                saveSnapshotUnlocked(read.snapshot)
            }
            return .reconciliationRequired
        }

        var current = read.snapshot.budget
        current.roll(now: now)
        guard current.allows(estimatedTokens: estimatedInputTokens, now: now) else {
            read.snapshot.budget = current
            saveSnapshotUnlocked(read.snapshot)
            return .capReached(current)
        }

        let pending = PendingReservation(id: id, estimatedInputTokens: estimatedInputTokens, requiresReconciliation: false)
        read.snapshot.budget = current
        read.snapshot.pending = pending
        guard saveSnapshotUnlocked(read.snapshot) else {
            read.snapshot.pending?.requiresReconciliation = true
            saveSnapshotUnlocked(read.snapshot)
            return .reconciliationRequired
        }
        Self.processLock.activeReservations.insert(id)
        return .reserved(current)
    }

    /// Commits actual provider-reported usage and clears the reservation as one locked update.
    func settle(id: UUID, actualInputTokens: Int, now: Date = Date()) -> JevBudget? {
        guard actualInputTokens >= 0 else { return nil }
        Self.processLock.value.lock(); defer { Self.processLock.value.unlock() }
        var read = readSnapshotUnlocked()
        guard !read.isCorrupt, let pending = read.snapshot.pending, pending.id == id else { return nil }
        let originalSnapshot = read.snapshot
        var current = read.snapshot.budget
        current.record(inputTokens: actualInputTokens, now: now)
        read.snapshot.budget = current
        read.snapshot.pending = nil
        guard saveSnapshotUnlocked(read.snapshot) else {
            read.snapshot = originalSnapshot
            read.snapshot.pending?.requiresReconciliation = true
            saveSnapshotUnlocked(read.snapshot)
            Self.processLock.activeReservations.remove(id)
            return nil
        }
        Self.processLock.activeReservations.remove(id)
        return current
    }

    /// Latches every thrown result as uncertain. A timeout/cancellation does not prove the
    /// provider failed before billing, so no automatic retry may reuse this reservation.
    func markUncertain(id: UUID) {
        Self.processLock.value.lock(); defer { Self.processLock.value.unlock() }
        var read = readSnapshotUnlocked()
        guard !read.isCorrupt, var pending = read.snapshot.pending, pending.id == id else { return }
        pending.requiresReconciliation = true
        read.snapshot.pending = pending
        saveSnapshotUnlocked(read.snapshot)
        Self.processLock.activeReservations.remove(id)
    }

    /// A new guard cannot know whether a persisted pending request belongs to a live caller.
    /// Mark it uncertain on construction and require explicit usage reconciliation.
    func markExistingReservationUncertain() {
        Self.processLock.value.lock(); defer { Self.processLock.value.unlock() }
        var read = readSnapshotUnlocked()
        guard !read.isCorrupt, var pending = read.snapshot.pending,
              !pending.requiresReconciliation,
              !Self.processLock.activeReservations.contains(pending.id) else { return }
        pending.requiresReconciliation = true
        read.snapshot.pending = pending
        saveSnapshotUnlocked(read.snapshot)
    }

    public var reservationStatus: ReservationStatus {
        Self.processLock.value.lock(); defer { Self.processLock.value.unlock() }
        let read = readSnapshotUnlocked()
        guard !read.isCorrupt else { return .reconciliationRequired }
        guard let pending = read.snapshot.pending else { return .clear }
        return pending.requiresReconciliation ? .reconciliationRequired : .inFlight
    }

    /// Clears an uncertain reservation only after the caller has checked provider billing.
    /// A corrupt ledger remains blocked because its prior month-to-date spend cannot be recovered here.
    func reconcilePending(_ resolution: ReservationResolution, now: Date = Date()) -> JevBudget? {
        Self.processLock.value.lock(); defer { Self.processLock.value.unlock() }
        var read = readSnapshotUnlocked()
        guard !read.isCorrupt, let pending = read.snapshot.pending, pending.requiresReconciliation else { return nil }
        guard !Self.processLock.activeReservations.contains(pending.id) else { return nil }
        if case .billed(let tokens) = resolution, tokens < 0 { return nil }
        let originalSnapshot = read.snapshot
        var current = read.snapshot.budget
        if case .billed(let tokens) = resolution { current.record(inputTokens: tokens, now: now) }
        read.snapshot.budget = current
        read.snapshot.pending = nil
        guard saveSnapshotUnlocked(read.snapshot) else {
            read.snapshot = originalSnapshot
            read.snapshot.pending?.requiresReconciliation = true
            saveSnapshotUnlocked(read.snapshot)
            return nil
        }
        Self.processLock.activeReservations.remove(pending.id)
        return current
    }
}
