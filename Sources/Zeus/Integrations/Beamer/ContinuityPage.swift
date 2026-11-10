import SwiftUI
import ZeusCore

/// The Continuity tab: where your keyboard and mouse are, with Pause, Open Beamer and a button per
/// machine. Off by default; switch it on in Settings › Top bar (the tab list).
struct ContinuityPage: View {
    var beamer: BeamerModel = .shared

    var body: some View {
        let status = beamer.status
        HStack(spacing: 8) {
            Tile {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.connected.to.line.below").font(.system(size: 12, weight: .bold)).foregroundStyle(TopBarStyle.violet)
                        Text("Continuity").font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                        Spacer()
                        Text(status.version.map { "Beamer \($0)" } ?? "Beamer").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                    }
                    Text(status.headline).font(TopBarStyle.label(15, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(2)
                    if let note { Text(note).font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary).lineLimit(3) }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) { actions(status) }
                }
            }
            Tile(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paired machines").font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudSecondary)
                    if status.machines.isEmpty {
                        Text("None yet. Pair a Mac or PC in Beamer.").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
                    }
                    ForEach(status.machines.prefix(5)) { machine in
                        HStack(spacing: 6) {
                            Image(systemName: machine.platform.symbol).font(.system(size: 11)).foregroundStyle(Theme.cloudSecondary).frame(width: 16)
                            Text(machine.name).font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                            Spacer(minLength: 0)
                            if status.link.machine == machine.name { Circle().fill(Color.green).frame(width: 7, height: 7) }
                        }
                    }
                    Spacer(minLength: 0)
                    Text("iPads use Universal Control, not Beamer.").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudSecondary)
                }
            }
            .frame(width: 300)
        }
        .task { beamer.watch(); await beamer.refresh() }
        .onDisappear { beamer.unwatch() }
    }

    private var note: String? { beamer.message }

    @ViewBuilder
    private func actions(_ status: BeamerStatus) -> some View {
        switch status.availability {
        case .notInstalled:
            NotchActionButton(title: "Install Beamer", tint: TopBarStyle.violet) { Task { await beamer.install() } }
        case .notRunning:
            NotchActionButton(title: "Start Beamer", tint: TopBarStyle.violet) { Task { await beamer.perform(.start) } }
        case .needsPermission, .ready:
            NotchActionButton(title: "Open Beamer", tint: TopBarStyle.violet) { Task { await beamer.perform(.showWindow) } }
            if status.availability == .ready {
                NotchActionButton(title: status.paused == true ? "Resume" : "Pause", tint: TopBarStyle.violet) {
                    Task { await beamer.perform(status.paused == true ? .resume : .pause) }
                }
                if status.isCrossed { NotchActionButton(title: "Bring input home", tint: TopBarStyle.violet) { Task { await beamer.perform(.returnHome) } } }
            }
        }
    }
}

/// A small pill on Home while input is on another machine.
struct BeamerHomeChip: View {
    var beamer: BeamerModel = .shared

    var body: some View {
        if beamer.status.isCrossed, let name = beamer.status.link.machine {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.connected.to.line.below").font(.system(size: 9, weight: .bold))
                Text(beamer.status.link == .driving(name) ? "On \(name)" : "\(name) driving").font(TopBarStyle.label(10, .semibold)).lineLimit(1)
            }
            .foregroundStyle(Theme.cloudPrimary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .accessibilityLabel(beamer.status.link.summary)
        }
    }
}
