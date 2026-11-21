import SwiftUI
import ZeusCore

/// The two columns inside the existing To-do page. Monochrome. A state change replaces the text immediately.
struct LocalTodoAgendaPanels: View {
    let surface: LocalTodoAgendaSurface
    @AccessibilityFocusState private var statusFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LocalTodoAgendaColumnView(column: surface.left, moves: surface.loadingBarMoves, statusFocused: $statusFocused)
            LocalTodoAgendaColumnView(column: surface.right, moves: surface.loadingBarMoves, statusFocused: nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(surface.voiceOverLabel)
        .onAppear {
            if !surface.showsOwnList { statusFocused = true }
        }
        .onChange(of: surface.voiceOverLabel) { _, _ in
            if !surface.showsOwnList { statusFocused = true }
        }
    }
}

struct LocalTodoAgendaColumnView: View {
    let column: LocalTodoAgendaColumnModel
    let moves: Bool
    var statusFocused: AccessibilityFocusState<Bool>.Binding?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(column.kicker)
                .font(TopBarStyle.label(10.5, .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.38))
            Text(column.head)
                .font(TopBarStyle.label(13, column.warns ? .bold : .regular))
                .foregroundStyle(Color.white.opacity(0.94))
                .modifier(StatusFocus(binding: statusFocused))
            if !column.groups.isEmpty {
                PageScroll(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(column.groups) { group in
                            groupList(group)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let body = column.body {
                Text(body)
                    .font(TopBarStyle.label(11.5))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = column.note {
                Text(note)
                    .font(TopBarStyle.label(11.5))
                    .foregroundStyle(Color.white.opacity(0.60))
            }
            if column.loading {
                LocalTodoAgendaLoadingBar(moves: moves)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .animation(nil, value: column.head)
    }

    private func groupList(_ group: LocalTodoAgendaGroupModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !group.name.isEmpty {
                Text(group.name)
                    .font(TopBarStyle.label(10.5, .semibold))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 4) {
                ForEach(group.rows) { row in
                    HStack(spacing: 8) {
                        Text(row.title)
                            .font(TopBarStyle.label(11.5, .medium))
                            .foregroundStyle(Color.white.opacity(0.94))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(row.meta)
                            .font(TopBarStyle.label(11.5, row.emphasized ? .bold : .regular).monospacedDigit())
                            .underline(row.emphasized)
                            .foregroundStyle(Color.white.opacity(row.emphasized ? 0.94 : 0.60))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.title), \(row.meta)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(group.name.isEmpty ? (column.kicker == "Agenda" ? "Events" : "Tasks") : group.name)
        }
    }
}

/// A thin bar. It travels only when Reduce Motion is off. The word Loading is the status.
private struct LocalTodoAgendaLoadingBar: View {
    let moves: Bool
    @State private var travel = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.12))
                Rectangle()
                    .fill(Color.white.opacity(moves ? 0.70 : 0.35))
                    .frame(width: moves ? geo.size.width * 0.35 : geo.size.width)
                    .offset(x: moves && travel ? geo.size.width : 0)
            }
        }
        .frame(height: 2)
        .clipped()
        .accessibilityHidden(true)
        .onAppear { if moves { travel = true } }
        .animation(moves ? .linear(duration: 1.4).repeatForever(autoreverses: false) : nil, value: travel)
    }
}

private struct StatusFocus: ViewModifier {
    let binding: AccessibilityFocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let binding {
            content.accessibilityFocused(binding)
        } else {
            content
        }
    }
}
