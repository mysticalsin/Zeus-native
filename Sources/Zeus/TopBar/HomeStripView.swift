import SwiftUI
import ZeusCore

extension TopBarModel {
    /// The slim strip under Home's cards: battery and keep-awake, only when they matter.
    var homeStrip: HomeStrip {
        let session = KeepAwakeSession.shared
        let ended = session.lastEnd.flatMap { $0 == .timeUp ? nil : $0.text }
        return HomeStrip.make(batteryLevel: battery?.level, charging: battery?.charging ?? false, pluggedIn: battery?.pluggedIn ?? false,
                              keepAwakeActive: session.isActive || keepAwake, keepAwakeLabel: session.isActive ? session.label : "On",
                              keepAwakeOpenEnded: session.isOpenEnded || !session.isActive, keepAwakeEndedText: ended)
    }
}

/// Home's status chips in Glance's card style: a dark capsule with a 1 pt rim and 11 pt text.
struct HomeStripView: View {
    let topBar: TopBarModel
    private var session: KeepAwakeSession { .shared }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(topBar.homeStrip.chips.enumerated()), id: \.offset) { _, chip in
                view(for: chip)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .frame(height: HomeStrip.height)
    }

    @ViewBuilder
    private func view(for chip: HomeStrip.Chip) -> some View {
        switch chip {
        case .battery(let level, let charging, let low):
            ChipFrame(tint: low ? Theme.danger : nil) {
                Image(systemName: charging ? "battery.100percent.bolt" : Self.batterySymbol(level))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(low ? Theme.danger : Color.white.opacity(0.75))
                Text(low ? "Battery low \(level)%" : (charging ? "Charging \(level)%" : "On battery \(level)%"))
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(low ? Theme.danger : Color.white.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
        case .keepAwake(let label, let openEnded):
            ChipFrame(tint: Theme.glow) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.glow)
                Text(openEnded ? "Keeping awake" : "Awake \(label)")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Color.white.opacity(0.78))
                if session.isActive, !session.isOpenEnded {
                    chipButton("plus", "Add 15 minutes") { session.add(minutes: 15) }
                }
                chipButton("xmark", "End keep-awake") {
                    session.end()
                    topBar.keepAwake = false
                }
            }
        case .keepAwakeEnded(let text):
            ChipFrame(tint: Theme.danger) {
                Image(systemName: "cup.and.saucer").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.danger)
                Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.danger).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func chipButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    static func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

private struct ChipFrame<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill((tint ?? Color.white).opacity(tint == nil ? 0.05 : 0.10)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}
