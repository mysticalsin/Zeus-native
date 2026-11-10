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
}

/// Settings > Engine: which brain understands commands. Laya answers on this Mac for free, Jev is
/// the paid cloud model behind a local estimate guard of US$10, and Auto uses Laya first and Jev
/// only when Laya is unsure. Provider billing remains authoritative.
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

    static let capOptions = ["Off", "US$2", "US$5", "US$10"]

    var body: some View {
        if testMode { testModeBanner }
        GSPageHeading(section: .engine, subtitle: "Which brain understands you, and what it costs.")
            .padding(.bottom, -GS.cardGap)
        GSCard("Engine") {
            engineChoice(.laya, "Laya", "Free and private. Runs on this Mac.")
            GSDivider()
            engineChoice(.jev, "Jev", "A stronger cloud model. Counts against the local usage estimate.")
            GSDivider()
            engineChoice(.auto, "Auto", "Laya first. Jev only when Laya is unsure.")
        }
        GSCard("Laya") {
            GSRow(symbol: "cpu", title: "On this Mac", text: center.layaInstalled ? "Loads on first use and unloads after 5 idle minutes." : "Not installed on this Mac. Commands use the rules, then Jev if you allow it.") {
                GSStatus(ok: center.layaInstalled, text: center.layaRunning ? "Loaded" : center.layaInstalled ? "Ready" : "Not installed")
            }
        }
        GSCard("Jev") {
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
            GSRow(symbol: "dollarsign.circle", title: "Monthly estimate cap", text: "Local usage estimate only; provider-side spending controls determine the actual billing limit. At this amount Jev pauses until next month.") {
                GSPopup(selection: Binding(get: { Self.capTitle(center.jevBudget.monthlyCap) }, set: { center.setJevCap(Self.cap(for: $0)) }),
                        options: Self.capOptions)
            }
            GSDivider()
            GSRow(symbol: "chart.bar", title: "This month", text: center.budgetSummary) {
                CapMeter(fraction: Self.fraction(center.jevBudget))
                    .frame(width: 120, height: 8)
                    .accessibilityLabel("Jev spend this month").accessibilityValue(center.budgetSummary)
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
                            .accessibilityLabel("Billed Jev input tokens")
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
                Text("TEST MODE — SYNTHETIC DATA ONLY").font(OB.font(13, .bold))
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

    private func confirmNoCharge() {
        page.confirmingNoCharge = false
        Task { await center.reconcileJevPending(.confirmedUnbilled) }
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

    private func engineChoice(_ engine: IntelligenceEngine, _ title: String, _ text: String) -> some View {
        let selected = center.engine == engine
        return GSRow(symbol: selected ? "checkmark.circle.fill" : "circle", title: title, text: text) {
            if selected { GSStatus(ok: true, text: "In use") }
            else { Button("Use") { center.engine = engine }.buttonStyle(GSButtonStyle()).accessibilityLabel("Use \(title)") }
        }
    }

    static func capTitle(_ cap: Double?) -> String {
        guard let cap, cap > 0 else { return "Off" }
        return capOptions.first { $0 == "US$\(Int(min(cap, JevBudgetStore.maxCap)))" } ?? "US$10"
    }

    static func cap(for title: String) -> Double? { title == "Off" ? nil : Double(title.dropFirst(3)) }

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
