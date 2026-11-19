import SwiftUI

/// The minutes-before question. A click expands the local detail. The terminal is not involved.
struct MeetingPromptCard: View {
    var name: String
    var minutes: Int
    var detail: MeetingPrompt.Detail
    var join: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Motion.reduced ? nil : .spring(response: 0.28, dampingFraction: 1)) { expanded.toggle() }
            } label: {
                Text(MeetingPrompt.line(name: name, minutes: minutes))
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MeetingPrompt.line(name: name, minutes: minutes))
            if expanded, !detail.collapsed {
                if !detail.purpose.isEmpty { Text(detail.purpose).font(.system(size: 12)) }
                if !detail.context.isEmpty { Text(detail.context).font(.system(size: 12)).foregroundStyle(.secondary) }
                ForEach(Array(detail.attendees.enumerated()), id: \.offset) { _, person in
                    Text(personLine(person)).font(.system(size: 12))
                }
                if !detail.callApp.isEmpty { Text(detail.callApp).font(.system(size: 12, weight: .semibold)) }
                if detail.joinURL != nil {
                    Button("Join", action: join).font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
    }

    private func personLine(_ person: MeetingPrompt.Attendee) -> String {
        [person.name, person.role, person.company].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
