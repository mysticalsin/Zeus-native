import SwiftUI
import ZeusCore

/// Settings > Intelligence: which engine understands commands, what Jev has cost this month,
/// and the recent answers with the engine that made each one.
struct IntelligenceSettings: View {
    @Bindable var center: IntelligenceCenter

    var body: some View {
        VStack(spacing: Glass.gap) {
            GlassCard(title: "Instant commands") {
                GlassRow(title: "Jev", note: center.jevReadiness.statusText) {
                    GlassStatus(ok: center.jevReadiness == .ready, text: center.jevReadiness == .ready ? "On" : "Off")
                }
            }
            GlassCard(title: "Usage") {
                GlassRow(title: "Local (free)", note: "Rules answers since launch.") {
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
}

/// Live CPU and memory of this process. Samples every 2 s only while the Energy card is on
/// screen; nothing runs when it is closed.
@MainActor
@Observable
final class EnergyMonitor {
    static let shared = EnergyMonitor()
    private(set) var cpu = 0.0
    private(set) var memory = 0.0
    /// False from a fresh start until the first 2 s sample, so a reader can say Unknown rather than 0.
    private(set) var hasCPUSample = false
    private var last = (ProcessEnergy.sample(), Date())
    private var timer: Timer?
    private var viewers = 0

    func start() {
        viewers += 1
        guard timer == nil else { return }
        last = (ProcessEnergy.sample(), Date())
        memory = last.0.residentMB
        hasCPUSample = false
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
        hasCPUSample = true
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
