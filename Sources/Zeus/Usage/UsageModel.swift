import Foundation
import Observation
import ZeusCore

/// Usage and limits for the coding agents, rebuilt from their local logs every minute.
@MainActor
@Observable
final class UsageModel {
    static let shared = UsageModel()

    private(set) var providers: [ProviderUsage] = []
    private(set) var updatedAt: Date?
    private(set) var isScanning = false
    /// Tokens allowed in one Claude 5-hour window. 0 means "compare with my busiest window".
    var claudeBlockLimit: Int {
        didSet { UserDefaults.standard.set(claudeBlockLimit, forKey: "usage.claudeBlockLimit"); rebuild() }
    }
    var alertsEnabled: Bool {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: "usage.alerts") }
    }
    /// Shown on the closed notch when a limit gets close.
    var onAlert: (String) -> Void = { _ in }

    private var snapshot = UsageScanner.Snapshot()
    /// Kept for its read cache: each refresh only reads what the logs gained.
    private let scanner = UsageScanner()
    private var timer: Timer?
    private var watcher: LogWatcher?
    private var lastFullWalk = Date.distantPast
    /// A full walk of the log folders at most this often; between walks FSEvents says what changed.
    static let fullWalkInterval: TimeInterval = 30 * 60
    /// Alerts already sent, per provider and threshold, so each fires once per window.
    private var alerted: Set<String> = []

    private init() {
        claudeBlockLimit = UserDefaults.standard.integer(forKey: "usage.claudeBlockLimit")
        alertsEnabled = UserDefaults.standard.object(forKey: "usage.alerts") as? Bool ?? true
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { UsageModel.shared.refresh() }
        }
    }

    func refresh() {
        guard !isScanning else { return }
        if watcher == nil { watcher = LogWatcher(roots: scanner.watchRoots) }
        let now = Date()
        var changed: Set<URL>?
        if let watcher, now.timeIntervalSince(lastFullWalk) < Self.fullWalkInterval {
            let drained = watcher.drain()
            if !drained.walk {
                // Nothing written to any log: no walk, no stat, no rebuild.
                guard !drained.changed.isEmpty else { updatedAt = now; return }
                changed = drained.changed
            }
        }
        if changed == nil { lastFullWalk = now }
        isScanning = true
        let scanner = scanner
        let limit = claudeBlockLimit
        Task.detached(priority: .utility) { [changed] in
            let snapshot = scanner.scan(changed: changed)
            // Summaries are built here too, so the main thread only swaps the result in.
            let providers = snapshot.unchanged ? nil : Self.summaries(snapshot, blockLimit: limit, now: Date())
            await MainActor.run {
                self.isScanning = false
                self.updatedAt = Date()
                guard let providers else { return }
                self.snapshot = snapshot
                self.providers = providers
                self.checkAlerts()
            }
        }
    }

    /// Scans on the calling thread; for snapshots.
    func loadNow() {
        snapshot = scanner.scan()
        updatedAt = Date()
        rebuild()
    }

    /// The fullest meter across providers, for the tab badge.
    var tightest: (provider: UsageProvider, meter: ProviderUsage.Meter)? {
        providers.compactMap { usage in usage.tightest.map { (usage.provider, $0) } }
            .max { ($0.meter.fraction ?? 0) < ($1.meter.fraction ?? 0) }
    }

    private func rebuild() {
        providers = Self.summaries(snapshot, blockLimit: claudeBlockLimit, now: Date())
        checkAlerts()
    }

    nonisolated static func summaries(_ snapshot: UsageScanner.Snapshot, blockLimit: Int, now: Date) -> [ProviderUsage] {
        UsageProvider.allCases.map { provider in
            UsageSummary.make(provider: provider, entries: snapshot.entries, codexLimits: snapshot.codexLimits,
                              blockLimit: provider == .claude && blockLimit > 0 ? blockLimit : nil, now: now)
        }
    }

    private func checkAlerts() {
        guard alertsEnabled else { return }
        for usage in providers {
            for meter in usage.meters {
                guard let fraction = meter.fraction else { continue }
                // Estimated Claude meters only alert against a limit you set yourself.
                if meter.estimated && claudeBlockLimit == 0 { continue }
                let window = meter.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
                // Only the highest threshold crossed speaks, once per window.
                guard let threshold = [0.8, 0.95].last(where: { fraction >= $0 }),
                      alerted.insert("\(usage.provider.rawValue).\(meter.label).\(threshold).\(window)").inserted else { continue }
                let reset = meter.resetsAt.map { " · resets in \(UsageSummary.countdown(to: $0, from: Date()))" } ?? ""
                onAlert("\(usage.provider.title) \(meter.label) at \(Int(fraction * 100))%\(reset)")
            }
        }
    }
}
