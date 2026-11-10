import SwiftUI
import ZeusCore

/// The Insomnia tab: type how long (or until when) the Mac stays awake, Start, and the lid-closed
/// toggle right beside it, so "close the lid and keep coding" is one glance. Status on the right.
struct InsomniaPage: View {
    let insomnia: InsomniaController

    var body: some View {
        HStack(spacing: 8) {
            Tile {
                if insomnia.isRunning { InsomniaRunning(insomnia: insomnia) } else { InsomniaEntry(insomnia: insomnia) }
            }
            Tile(padding: 12) { InsomniaStatus(insomnia: insomnia) }
                .frame(width: 300)
        }
    }
}

/// Hours and minutes (or an Until time), quick chips, Start and the lid toggle.
private struct InsomniaEntry: View {
    let insomnia: InsomniaController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(TopBarStyle.violet)
                Text("Keep the Mac awake").font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                Spacer()
                ForEach(InsomniaController.EntryMode.allCases) { mode in
                    InsomniaChip(title: mode.rawValue, selected: insomnia.entryMode == mode) { insomnia.entryMode = mode }
                }
            }
            HStack(alignment: .center, spacing: 10) {
                if insomnia.entryMode == .length {
                    if insomnia.duration.indefinite {
                        Text("∞").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(Theme.cloudPrimary)
                            .frame(height: 50)
                        Text("Until you stop it, or a battery or heat rule does.")
                            .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
                    } else {
                        TimeField(insomnia: insomnia, unit: .hours)
                        TimeField(insomnia: insomnia, unit: .minutes)
                    }
                } else {
                    UntilField(insomnia: insomnia)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                ForEach(Array(InsomniaDuration.chips.enumerated()), id: \.offset) { _, chip in
                    InsomniaChip(title: InsomniaDuration.chipLabel(chip),
                                 selected: insomnia.entryMode == .length && insomnia.duration.totalMinutes == chip) {
                        insomnia.applyChip(chip)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                NotchActionButton(title: "Start", tint: TopBarStyle.violet) { insomnia.start() }
                    .accessibilityHint("Keeps the Mac awake for the time you entered.")
                LidToggle(insomnia: insomnia)
                Spacer(minLength: 0)
            }
        }
    }
}

/// While a session runs: the time left, big, then +15 m, +1 h, Stop and the lid toggle.
private struct InsomniaRunning: View {
    let insomnia: InsomniaController

    var body: some View {
        let session = insomnia.session
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: insomnia.lidArmed ? "laptopcomputer" : "cup.and.saucer.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(TopBarStyle.violet)
                Text(insomnia.lidArmed ? "Awake, lid-closed mode on" : "Awake")
                    .font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
            }
            Text(session.isOpenEnded ? "∞" : KeepAwakeLength.countdown(session.remaining))
                .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.cloudPrimary)
                .contentTransition(.numericText())
                .accessibilityLabel(session.isOpenEnded ? "Awake until you stop it" : "\(KeepAwakeLength.countdown(session.remaining)) left")
            Text(session.isOpenEnded ? "Until you stop it" : session.endsAt.map { "Until \($0.formatted(date: .omitted, time: .shortened))" } ?? "")
                .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if !session.isOpenEnded {
                    NotchActionButton(title: "+15 m", tint: Theme.cloudSecondary, filled: false) { insomnia.add(minutes: 15) }
                    NotchActionButton(title: "+1 h", tint: Theme.cloudSecondary, filled: false) { insomnia.add(minutes: 60) }
                }
                NotchActionButton(title: "Stop", tint: Theme.danger) { insomnia.stop() }
                LidToggle(insomnia: insomnia)
                Spacer(minLength: 0)
            }
        }
    }
}

/// "Keep working with the lid closed": sits next to Start and Stop.
private struct LidToggle: View {
    let insomnia: InsomniaController

    var body: some View {
        let on = insomnia.lidClosedMode
        Button { insomnia.lidClosedMode.toggle() } label: {
            HStack(spacing: 6) {
                Capsule().fill(on ? TopBarStyle.violet : Color.white.opacity(0.15)).frame(width: 26, height: 15)
                    .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).frame(width: 11, height: 11).padding(2) }
                Text("Keep working with the lid closed").font(TopBarStyle.label(11, .semibold))
                    .foregroundStyle(on ? Theme.cloudPrimary : Theme.cloudSecondary)
                if on, !insomnia.setup.isReady {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.bolt)
                        .help("Needs a one-time setup")
                        .accessibilityLabel("Needs a one-time setup")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Keep working with the lid closed")
        .accessibilityValue(on ? (insomnia.setup.isReady ? "On" : "On, needs setup") : "Off")
    }
}

/// One number you can type into, step with the arrows or the arrow keys.
private struct TimeField: View {
    enum Unit { case hours, minutes }
    let insomnia: InsomniaController
    let unit: Unit

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", text: Binding(
                get: { String(format: "%02d", unit == .hours ? insomnia.duration.hours : insomnia.duration.minutes) },
                set: { text in unit == .hours ? insomnia.duration.type(hours: text) : insomnia.duration.type(minutes: text) }))
                .textFieldStyle(.plain)
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.cloudPrimary)
                .multilineTextAlignment(.trailing)
                .frame(width: 58, height: 50)
                .onKeyPress(.upArrow) { step(1); return .handled }
                .onKeyPress(.downArrow) { step(-1); return .handled }
                .accessibilityLabel(unit == .hours ? "Hours" : "Minutes")
            VStack(spacing: 2) {
                GlyphButton(symbol: "chevron.up", size: 10, label: unit == .hours ? "One hour more" : "Five minutes more") { step(1) }
                GlyphButton(symbol: "chevron.down", size: 10, label: unit == .hours ? "One hour less" : "Five minutes less") { step(-1) }
            }
            Text(unit == .hours ? "h" : "m").font(TopBarStyle.label(14, .semibold)).foregroundStyle(Theme.cloudSecondary)
        }
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func step(_ direction: Int) {
        if unit == .hours { insomnia.duration.step(hours: direction) } else { insomnia.duration.step(minutes: direction * 5) }
    }
}

/// A clock time ("23:30") with ±15 min steps, and the length it makes.
private struct UntilField: View {
    let insomnia: InsomniaController

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                TextField("23:30", text: Binding(get: { insomnia.untilText }, set: { insomnia.untilText = String($0.prefix(5)) }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.cloudPrimary)
                    .frame(width: 118, height: 50)
                    .onKeyPress(.upArrow) { step(15); return .handled }
                    .onKeyPress(.downArrow) { step(-15); return .handled }
                    .accessibilityLabel("Until, as a clock time")
                VStack(spacing: 2) {
                    GlyphButton(symbol: "chevron.up", size: 10, label: "Fifteen minutes later") { step(15) }
                    GlyphButton(symbol: "chevron.down", size: 10, label: "Fifteen minutes earlier") { step(-15) }
                }
            }
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            if case .some(.some(let minutes)) = insomnia.enteredMinutes {
                Text("= \(InsomniaDuration(hours: 0, minutes: minutes).label)").font(TopBarStyle.label(13, .semibold)).foregroundStyle(Theme.cloudSecondary)
            } else {
                Text("Type a time like 23:30").font(TopBarStyle.label(11)).foregroundStyle(Theme.bolt)
            }
        }
    }

    private func step(_ minutes: Int) {
        let clock = InsomniaDuration.parseClock(insomnia.untilText) ?? (23, 30)
        let total = ((clock.hour * 60 + clock.minute + minutes) % 1440 + 1440) % 1440
        insomnia.untilText = String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Lid, battery, heat, end reason, frozen apps, hotspot, last nudge, and setup when needed.
private struct InsomniaStatus: View {
    let insomnia: InsomniaController

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            line("laptopcomputer", "Lid", insomnia.lidText)
            line("battery.75percent", "Battery", insomnia.batteryText)
            line("thermometer.medium", "Heat", insomnia.heatText)
            line("flag.checkered", "Ended", insomnia.endText)
            line("snowflake", "Frozen apps", "\(insomnia.frozenCount)")
            line("personalhotspot", "Hotspot", insomnia.hotspotSSID.isEmpty ? "Not set" : insomnia.hotspotStatus)
            line("arrow.uturn.right", "Last nudge", insomnia.nudgeAgents ? insomnia.lastNudge : "Off")
            Spacer(minLength: 0)
            if !insomnia.setup.isReady {
                HStack(spacing: 8) {
                    NotchActionButton(title: insomnia.setupBusy ? "Waiting…" : "Set up lid-closed mode", tint: Theme.bolt) {
                        insomnia.installRule()
                    }
                    .disabled(insomnia.setupBusy)
                    .accessibilityHint("macOS asks for your password once. Zeus never sees it.")
                }
            }
            if let text = insomnia.message ?? insomnia.setupMessage {
                Text(text).font(TopBarStyle.label(9.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func line(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.cloudQuiet).frame(width: 14)
            Text(title).font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudSecondary)
            Spacer(minLength: 6)
            Text(value).font(TopBarStyle.label(10.5, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1).truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct InsomniaChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(TopBarStyle.label(11, .semibold))
                .foregroundStyle(selected ? Theme.storm : Theme.cloudSecondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(selected ? TopBarStyle.violet : Color.white.opacity(0.08)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
