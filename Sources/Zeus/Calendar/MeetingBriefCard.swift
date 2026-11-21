import SwiftUI

/// Name and time, and the local summary when the card is allowed to open.
struct MeetingBriefCard: View {
    var card: MeetingBrief.Card
    var onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(card.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(card.time).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if card.collapsed {
                Button("Show brief", action: onExpand).buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
            } else {
                if let role = card.role, let company = card.company {
                    Text("\(role), \(company)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let summary = card.summary {
                    Text(summary).font(.system(size: 12)).lineLimit(3)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: 420, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
