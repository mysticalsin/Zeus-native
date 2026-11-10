import SwiftUI
import ZeusCore

/// Settings > Intelligence: which engine understands commands, what Jev has cost this month,
/// and the recent answers with the engine that made each one.
struct IntelligenceSettings: View {
    @Bindable var center: IntelligenceCenter

    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Engine") {
                GlassRow(title: "Understands your commands", note: note) {
                    GlassMenu(options: IntelligenceEngine.allCases.map { ($0.rawValue, $0.title) },
                              selection: Binding(get: { center.engine.rawValue },
                                                 set: { center.engine = IntelligenceEngine(rawValue: $0) ?? .laya }))
                }
                GlassDivider()
                GlassRow(title: "Laya", note: center.layaInstalled ? "Loads on first use and unloads after 5 idle minutes." : "Not installed on this Mac yet. Commands use rules, then Jev if allowed.") {
                    GlassStatus(ok: center.layaInstalled, text: center.layaRunning ? "Loaded" : center.layaInstalled ? "Ready" : "Not installed")
                }
                GlassDivider()
                GlassRow(title: "Jev", note: center.hasJevKey ? "Key saved in Keychain." : "No key saved.") {
                    GlassStatus(ok: center.hasJevKey, text: center.hasJevKey ? "Ready" : "No key")
                }
            }
            GlassCard(title: "Usage") {
                GlassRow(title: "Local (free)", note: "Rules and Laya answers since launch.") {
                    Text("\(center.localCount)").font(Glass.font(12, .semibold).monospacedDigit()).foregroundStyle(Glass.secondary)
                }
                GlassDivider()
                GlassRow(title: "This month", note: "Local usage estimate only; provider billing controls set the actual limit. Jev pauses when the estimate reaches this amount.") {
                    Text(center.budgetSummary).font(Glass.font(12, .semibold).monospacedDigit()).foregroundStyle(Glass.secondary)
                }
            }
            GlassCard(title: "Recent answers") {
                if center.history.isEmpty {
                    GlassRow(title: "Nothing yet", note: "Commands you give appear here with the engine that understood them.") { EmptyView() }
                }
                ForEach(Array(center.history.prefix(8).enumerated()), id: \.element.id) { index, record in
                    if index > 0 { GlassDivider() }
                    GlassRow(title: record.utterance, note: record.intent) {
                        HStack(spacing: 8) {
                            EngineBadge(engine: record.engineName)
                            if record.decision?.source != .jev {
                                Button("Try with Jev") { Task { await center.tryWithJev(record) } }
                                    .buttonStyle(GlassButtonStyle(kind: .secondary, compact: true))
                                    .disabled(!center.hasJevKey)
                                    .accessibilityLabel("Run \(record.utterance) again with Jev")
                            }
                        }
                    }
                }
            }
        }
    }

    private var note: String {
        switch center.engine {
        case .laya: "Free and private: runs on this Mac."
        case .jev: "TypeSafe's cloud model. Counts against the local usage estimate."
        case .auto: "Laya first; Jev only when Laya is unsure."
        }
    }
}

/// Live CPU and memory of this process. Samples every 2 s only while the Energy card is on
/// screen; nothing runs when it is closed.
@MainActor
@Observable
final class EnergyMonitor {
    static let shared = EnergyMonitor()
    private(set) var cpu = 0.0
    private(set) var memory = 0.0
    private var last = (ProcessEnergy.sample(), Date())
    private var timer: Timer?
    private var viewers = 0

    func start() {
        viewers += 1
        guard timer == nil else { return }
        last = (ProcessEnergy.sample(), Date())
        memory = last.0.residentMB
        let t = Timer(timeInterval: 2, repeats: true) { _ in Task { @MainActor in EnergyMonitor.shared.sample() } }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate(); timer = nil
    }

    private func sample() {
        let now = Date(), s = ProcessEnergy.sample()
        cpu = ProcessEnergy.cpuPercent(from: last.0, to: s, over: now.timeIntervalSince(last.1))
        memory = s.residentMB
        last = (s, now)
    }
}

/// Diagnostics > Energy: this app's live CPU and memory against the budget.
struct EnergyCard: View {
    var monitor = EnergyMonitor.shared

    var body: some View {
        GlassCard(title: "Energy") {
            GlassRow(title: "CPU", note: String(format: "Budget: under %.0f%% when idle.", PerformanceBudget.idleCPUPercent)) {
                Text(String(format: "%.1f%%", monitor.cpu)).font(Glass.font(12, .semibold).monospacedDigit()).foregroundStyle(Glass.secondary)
            }
            GlassDivider()
            GlassRow(title: "Memory", note: String(format: "Budget: under %.0f MB when idle.", PerformanceBudget.idleMemoryMB)) {
                Text(String(format: "%.0f MB", monitor.memory)).font(Glass.font(12, .semibold).monospacedDigit()).foregroundStyle(Glass.secondary)
            }
            GlassDivider()
            GlassRow(title: "Power", note: "Low Power Mode or a hot Mac switch to lighter engines.") {
                let state = PowerState.current
                Text(state.lowPower ? "Low Power" : state.constrained ? "Hot, saving" : "Normal").font(Glass.font(12, .semibold)).foregroundStyle(Glass.secondary)
            }
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}
