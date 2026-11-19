import SwiftUI
import ZeusCore

/// Draft for the Jev key field (this toolchain has no SwiftUI `@State` macro).
@MainActor
@Observable
final class EnginePageState {
    static let shared = EnginePageState()
    var jevKeyDraft = ""
    var jevInputTokensDraft = ""
    /// "Confirm no charge" needs a second click before it clears the pending request.
    var confirmingNoCharge = false
    /// The monthly limit being typed. Empty by default: the owner sets the amount.
    var capDraft = ""
}

/// Settings > Engine: the "Instant commands" card. Jev (TypeSafe System One, paid) is the only model
/// stage after the local rules, behind a key in the Keychain and a monthly limit the owner sets.
/// The estimate is local; provider billing remains authoritative.
@MainActor
struct EnginePage: View {
    private let center: IntelligenceCenter
    private let page: EnginePageState
    private let testMode: Bool

    init(center: IntelligenceCenter = .shared, page: EnginePageState = .shared, testMode: Bool = false) {
        self.center = center
        self.page = page
        self.testMode = testMode
    }

    var body: some View {
        if testMode { testModeBanner }
        GSPageHeading(section: .engine, subtitle: "How instant commands are understood, and what it costs.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Instant commands") {
            GSRow(symbol: "bolt", title: "Jev", text: center.jevReadiness.statusText) {
                GSStatus(ok: center.jevReadiness == .ready, text: center.jevReadiness == .ready ? "On" : "Off")
            }
            GSDivider()
            if testMode {
                GSRow(symbol: "key", title: "API key", text: "Disabled in Test Mode. No Keychain item is read or written.") {
                    Text("Unavailable").font(OB.font(13.5, .semibold)).foregroundStyle(GS.secondary)
                }
            } else {
                GSRow(symbol: "key", title: "API key", text: center.hasJevKey ? "Saved in your Keychain. Zeus reads it once." : "Kept in your Keychain. Without a key Jev never runs.") {
                    HStack(spacing: 10) {
                        SecureField(center.hasJevKey ? "Saved" : "Paste a key", text: Binding(get: { page.jevKeyDraft }, set: { page.jevKeyDraft = $0 }))
                            .textFieldStyle(.plain)
                            .snapshotSafeText(page.jevKeyDraft, placeholder: center.hasJevKey ? "Saved" : "Paste a key", secure: true)
                            .font(OB.font(13.5)).foregroundStyle(GS.text)
                            .padding(.horizontal, 10).frame(width: 170, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                            .accessibilityLabel("Jev API key")
                            .onSubmit(saveKey)
                        Button("Save key", action: saveKey).buttonStyle(GSButtonStyle()).disabled(page.jevKeyDraft.isEmpty)
                        if center.hasJevKey {
                            Button("Remove") { center.saveJevKey("") }.buttonStyle(GSButtonStyle())
                        }
                    }
                }
            }
            GSDivider()
            GSRow(symbol: "dollarsign.circle", title: "Monthly limit", text: capRowText) {
                HStack(spacing: 10) {
                    TextField("US$", text: Binding(get: { page.capDraft }, set: { page.capDraft = $0 }))
                        .textFieldStyle(.plain)
                        .snapshotSafeText(page.capDraft, placeholder: "US$")
                        .font(OB.font(13.5)).foregroundStyle(GS.text)
                        .padding(.horizontal, 10).frame(width: 88, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                        .accessibilityLabel("Jev monthly limit in US dollars")
                        .accessibilityIdentifier("settings.engine.jevLimit")
                        .onSubmit(saveCap)
                    Button("Set limit", action: saveCap).buttonStyle(GSButtonStyle()).disabled(parsedCapDraft == nil)
                    if (center.jevBudget.monthlyCap ?? 0) > 0 {
                        Button("Remove") { page.capDraft = ""; center.setJevCap(nil) }.buttonStyle(GSButtonStyle())
                    }
                }
            }
            GSDivider()
            GSRow(symbol: "chart.bar", title: "This month", text: monthSummary) {
                CapMeter(fraction: Self.fraction(center.jevBudget))
                    .frame(width: 120, height: 8)
                    .accessibilityLabel("Jev spend this month").accessibilityValue(monthSummary)
            }
            if center.jevReservationStatus == .reconciliationRequired {
                GSDivider()
                GSRow(symbol: "exclamationmark.triangle", title: "Jev paused", text: "Check the provider usage page before reconciling this request.")
                GSRow(title: "Billed input tokens", text: "Enter the input-token count shown by the provider.") {
                    HStack(spacing: 8) {
                        TextField("Tokens", text: Binding(get: { page.jevInputTokensDraft }, set: { page.jevInputTokensDraft = $0 }))
                            .textFieldStyle(.plain)
                            .snapshotSafeText(page.jevInputTokensDraft, placeholder: "Tokens")
                            .font(OB.font(13.5)).foregroundStyle(GS.text)
                            .padding(.horizontal, 10).frame(width: 88, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GS.window))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(GS.buttonStroke, lineWidth: 1))
                            .accessibilityLabel("Billed cloud model input tokens")
                        Button("Record usage", action: reconcileBilledUsage)
                            .buttonStyle(GSButtonStyle()).disabled(parsedBilledInputTokens == nil)
                    }
                }
                GSRow(title: "No charge", text: "Choose only after provider usage confirms this request was not billed.") {
                    if page.confirmingNoCharge {
                        HStack(spacing: 8) {
                            Button("Yes, not billed") { confirmNoCharge() }
                                .buttonStyle(GSButtonStyle(prominent: true))
                                .accessibilityLabel("Yes, provider usage shows this request was not billed")
                            Button("Cancel") { page.confirmingNoCharge = false }.buttonStyle(GSButtonStyle())
                        }
                    } else {
                        Button("Confirm no charge") { page.confirmingNoCharge = true }.buttonStyle(GSButtonStyle())
                    }
                }
            }
            if let message = center.jevMessage { GSInfo(text: message) }
        }
        GSCard("Recent answers") {
            if center.history.isEmpty {
                GSRow(title: "Nothing yet", text: "Commands you give appear here with the engine that understood them.")
            }
            ForEach(Array(center.history.prefix(6).enumerated()), id: \.element.id) { index, record in
                if index > 0 { GSDivider() }
                GSRow(title: record.utterance, text: record.intent) {
                    HStack(spacing: 8) {
                        EngineBadge(engine: record.engineName)
                        if !testMode, record.decision?.source != .jev, center.jevAvailable {
                            Button("Try with Jev") { Task { await center.tryWithJev(record) } }
                                .buttonStyle(GSButtonStyle()).accessibilityLabel("Run \(record.utterance) again with Jev")
                        }
                    }
                }
            }
        }
        .task { await center.refreshBudget() }
    }

    private var testModeBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "testtube.2").font(.system(size: 19, weight: .semibold)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("TEST MODE: SYNTHETIC DATA ONLY").font(OB.font(13, .bold))
                Text("In-memory state only. No Keychain, model providers, routines, hooks, or helper installers are available.")
                    .font(OB.font(12.5)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Color.orange)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.5)))
        .accessibilityElement(children: .combine)
    }

    /// Return in an empty field must not remove the saved key; Remove is the only way to delete it.
    private func saveKey() {
        guard !page.jevKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if center.saveJevKey(page.jevKeyDraft) { page.jevKeyDraft = "" }
    }

    private var parsedCapDraft: Double? {
        let text = page.capDraft.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "US$", with: "").replacingOccurrences(of: "$", with: "")
        guard let value = Double(text), value > 0 else { return nil }
        return min(value, JevBudgetStore.maxCap)
    }

    private func saveCap() {
        guard let value = parsedCapDraft else { return }
        center.setJevCap(value)
        page.capDraft = ""
    }

    private var capRowText: String {
        guard let cap = center.jevBudget.monthlyCap, cap > 0 else { return "Set a monthly limit to turn Jev on" }
        return String(format: "Limit US$%.0f a month (the most is US$%.0f). Local estimate only; provider billing decides the real limit.", min(cap, JevBudgetStore.maxCap), JevBudgetStore.maxCap)
    }

    private func confirmNoCharge() {
        page.confirmingNoCharge = false
        Task { await center.reconcileJevPending(.confirmedUnbilled) }
    }

    /// The "This month" sentence, from the same live budget the cap pop-up reads, so the two never disagree
    /// (the controller's cached summary starts as "no cap set" until its first refresh finishes).
    private var monthSummary: String {
        guard center.jevReservationStatus == .clear else { return center.budgetSummary }
        let budget = center.jevBudget
        guard let cap = budget.monthlyCap, cap > 0 else { return "Set a monthly limit to turn Jev on" }
        return String(format: "Jev $%.2f of $%.0f", budget.spent, min(cap, JevBudgetStore.maxCap))
    }

    private var parsedBilledInputTokens: Int? {
        guard let tokens = Int(page.jevInputTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)), tokens >= 0 else { return nil }
        return tokens
    }

    private func reconcileBilledUsage() {
        guard let tokens = parsedBilledInputTokens else { return }
        Task {
            // On failure the token count stays in the field and `jevMessage` explains.
            if await center.reconcileJevPending(.billed(inputTokens: tokens)) { page.jevInputTokensDraft = "" }
        }
    }

    static func fraction(_ budget: JevBudget) -> Double {
        guard let cap = budget.monthlyCap, cap > 0 else { return 0 }
        return min(1, budget.spent / min(cap, JevBudgetStore.maxCap))
    }
}

private struct CapMeter: View {
    let fraction: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(GS.toggleOff)
                Capsule().fill(fraction > 0.9 ? Color.orange : OB.allowed).frame(width: max(fraction > 0 ? 4 : 0, proxy.size.width * fraction))
            }
        }
    }
}
