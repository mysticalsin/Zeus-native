import SwiftUI
import ZeusCore

/// Glass impact on the hub decision row, drawn before Allow once.
/// Monochrome hairline and the bundled face. No gradient. The allow control keeps its name.
struct HubDecisionImpactRow: View {
    var impact: HubApprovalImpact
    var detailsHidden: Bool
    var onAllowOnce: () -> Void
    var onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            impactLines
            HStack(spacing: 8) {
                decisionButton(
                    title: HubApprovalImpact.allowOnceTitle,
                    hint: "Lets this run once.",
                    filled: true,
                    identifier: "hub.decision.allow-once",
                    action: onAllowOnce
                )
                decisionButton(
                    title: HubApprovalImpact.denyTitle,
                    hint: "Stops this once.",
                    filled: false,
                    identifier: "hub.decision.deny",
                    action: onDeny
                )
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(Glass.fill, in: RoundedRectangle(cornerRadius: Glass.rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Glass.rowRadius, style: .continuous)
                .strokeBorder(Glass.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hub.decision.row")
    }

    private var impactLines: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Before allow")
                .font(Glass.eyebrow)
                .foregroundStyle(Glass.tertiary)
            ForEach(impact.lines(detailsHidden: detailsHidden), id: \.title) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(line.title)
                        .font(Glass.caption)
                        .foregroundStyle(Glass.secondary)
                    if !line.detail.isEmpty {
                        Text(line.detail)
                            .font(Glass.font(12, .medium))
                            .foregroundStyle(Glass.text)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(impact.accessibilitySummary(detailsHidden: detailsHidden))
        .accessibilityIdentifier("hub.decision.impact")
    }

    private func decisionButton(title: String, hint: String, filled: Bool, identifier: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Glass.font(12, .medium))
                .foregroundStyle(filled ? Glass.canvas : Glass.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 28)
                .background(Capsule().fill(filled ? Glass.text : Glass.fillRaised))
                .overlay(Capsule().strokeBorder(Glass.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}
