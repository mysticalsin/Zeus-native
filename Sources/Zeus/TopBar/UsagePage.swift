import SwiftUI
import ZeusCore

/// Usage tab: one card per coding agent with its limit rings, reset countdowns and a
/// seven-day strip, read from the agents' own logs on this Mac.
struct UsagePage: View {
    let usage: UsageModel

    var body: some View {
        TickingView(interval: 30) { context in
            HStack(alignment: .top, spacing: 8) {
                ForEach(usage.providers, id: \.provider) { provider in
                    UsageCard(usage: provider, now: context.date, customLimit: usage.claudeBlockLimit > 0)
                }
                if usage.providers.isEmpty {
                    Tile { Text("Reading usage…").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudQuiet) }
                }
            }
        }
    }

    static func tint(_ fraction: Double?) -> Color {
        switch fraction ?? 0 {
        case 0.95...: Theme.danger
        case 0.8...: Theme.ember
        default: Theme.leaf
        }
    }
}

private struct UsageCard: View {
    let usage: ProviderUsage
    let now: Date
    let customLimit: Bool

    var body: some View {
        Tile(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: usage.provider == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.bolt)
                    Text(usage.provider.title.uppercased()).font(TopBarStyle.label(9.5, .bold)).foregroundStyle(Theme.cloudSecondary)
                    if let plan = usage.plan {
                        Text(plan.capitalized).font(TopBarStyle.label(9, .semibold)).foregroundStyle(Theme.storm)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.cloudSecondary, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    if let last = usage.lastActivity {
                        Text(last, format: .relative(presentation: .named, unitsStyle: .narrow))
                            .font(TopBarStyle.label(9.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
                    }
                }
                if usage.hasData {
                    HStack(spacing: 12) {
                        ForEach(usage.meters, id: \.label) { meter in
                            MeterRing(meter: meter, now: now, note: note(for: meter))
                        }
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                    WeekStrip(daily: usage.daily)
                    HStack {
                        Text("Today \(UsageSummary.compact(usage.todayTokens))")
                        Spacer()
                        Text("7d \(UsageSummary.compact(usage.weekTokens))")
                        if usage.weekCost >= 0.01 {
                            Text(usage.weekCost < 1 ? "≈ $\(usage.weekCost, specifier: "%.2f") API" : "≈ $\(usage.weekCost, specifier: "%.0f") API").help("What these tokens would cost at API list prices")
                        }
                    }
                    .font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudQuiet)
                } else {
                    Spacer(minLength: 0)
                    Text("No \(usage.provider.title) sessions this week.").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudQuiet)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func note(for meter: ProviderUsage.Meter) -> String? {
        guard meter.estimated, meter.fraction != nil else { return nil }
        return customLimit ? "of limit" : "vs busiest"
    }
}

private struct MeterRing: View {
    let meter: ProviderUsage.Meter
    let now: Date
    let note: String?

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                if let fraction = meter.fraction {
                    Circle().trim(from: 0, to: max(fraction, 0.01))
                        .stroke(UsagePage.tint(fraction), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fraction)
                    Text("\(Int((fraction * 100).rounded()))").font(TopBarStyle.label(11, .bold).monospacedDigit()).foregroundStyle(Theme.cloudPrimary)
                } else {
                    Image(systemName: "chart.bar.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.cloudSecondary)
                }
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(meter.label).font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary)
                if let reset = meter.resetsAt {
                    Text("resets \(UsageSummary.countdown(to: reset, from: now))").font(TopBarStyle.label(9.5).monospacedDigit()).foregroundStyle(Theme.cloudQuiet)
                } else if let tokens = meter.tokens {
                    Text("\(UsageSummary.compact(tokens)) tokens").font(TopBarStyle.label(9.5).monospacedDigit()).foregroundStyle(Theme.cloudQuiet)
                }
                if let note { Text(note).font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudQuiet) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WeekStrip: View {
    let daily: [Int]

    var body: some View {
        let peak = max(daily.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(daily.enumerated()), id: \.offset) { index, tokens in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index == daily.count - 1 ? Theme.bolt : Color.white.opacity(0.22))
                    .frame(height: max(2, 18 * CGFloat(tokens) / CGFloat(peak)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityLabel("Tokens per day for the last 7 days")
    }
}
