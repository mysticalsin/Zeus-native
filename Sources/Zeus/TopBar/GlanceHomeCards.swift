import SwiftUI
import ZeusCore

/// Glance's card glass, measured on the live pair (parity/N4): nearly clear over the panel (Music
/// and Focus sit within 1 to 3 levels of the body behind them, so the ambient glow shows through),
/// a faint content tint, and a 1 px rim at about white 15 % on top, dimmer below.
/// How much a Home backdrop is darkened under card content so text stays readable (0 = no backdrop).
private struct HomeScrimKey: EnvironmentKey { static let defaultValue: Double = 0 }
extension EnvironmentValues {
    var homeBackdropScrim: Double {
        get { self[HomeScrimKey.self] }
        set { self[HomeScrimKey.self] = newValue }
    }
}

struct GlanceCard<Content: View>: View {
    var tint: Color
    @Environment(\.homeBackdropScrim) private var scrim
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GlanceTopBar.cardRadius, style: .continuous)
        let home = CardFinish.home
        let padded = content
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Settings > Appearance: Home style (Device, Borderless, Borderless colour) and Card style.
        Group {
            switch home.finish {
            case nil:
                padded
                    .background {
                        ZStack {
                            if scrim > 0 { shape.fill(Color.black.opacity(scrim)) }
                            if home.tinted { shape.fill(tint.opacity(0.16)) }
                        }
                    }
                    .clipShape(shape)
            case .glass?, .liquidGlass?:
                // The look measured from Glance's Home cards.
                padded
                    .background {
                        ZStack {
                            if scrim > 0 { shape.fill(Color.black.opacity(scrim)) }
                            shape.fill(tint.opacity(0.08))
                            // About +9 over the body at the top, about -4 at the bottom (parity/N4).
                            shape.fill(LinearGradient(colors: [Color.white.opacity(0.035), .clear, Color.black.opacity(0.07)],
                                                      startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(home.finish == .liquidGlass ? 0.2 : 0.15), Color.white.opacity(0.06)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .clipShape(shape)
            case let finish?:
                padded
                    .background { if scrim > 0 { shape.fill(Color.black.opacity(scrim)) } }
                    .notchCard(finish, radius: GlanceTopBar.cardRadius)
            }
        }
        .cardHoverLift()
    }
}

/// Content tints measured from Glance's Home cards.
enum GlanceTint {
    static let cool = Color(red: 42 / 255, green: 43 / 255, blue: 51 / 255)
    static let neutral = Color(red: 51 / 255, green: 43 / 255, blue: 34 / 255)
    static let slate = Color(red: 44 / 255, green: 45 / 255, blue: 48 / 255)
    static let copper = Color(red: 102 / 255, green: 68 / 255, blue: 57 / 255)
    /// Ambient Home glow: Zeus purple lighting (COLOR DIRECTION; was copper).
    static let glow = Theme.glow

    // Tab row, from the live pair (parity/N4).
    /// Capsule fill (19,19,21) and its 1 pt rim, lit at the top (56) and dim at the bottom (37).
    static let capsule = Color(red: 19 / 255, green: 19 / 255, blue: 21 / 255)
    static let capsuleRim = LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.075)], startPoint: .top, endPoint: .bottom)
    /// Selected pill (53,53,55) with a highlight along its top edge (96).
    static let pill = Color(red: 53 / 255, green: 53 / 255, blue: 55 / 255)
    static let pillRim = LinearGradient(colors: [.white.opacity(0.21), .clear], startPoint: .top, endPoint: .center)
    /// The 30 pt "more" circle (24).
    static let more = Color(red: 24 / 255, green: 24 / 255, blue: 25 / 255)
}

/// Glance type scale for cards.
enum GlanceType {
    static let title = Font.system(size: 11, weight: .regular)
    static let media = Font.system(size: 13.5, weight: .medium)
    static let numeral = Font.system(size: 40, weight: .light)
    static let date = Font.system(size: 34, weight: .light)
}

/// A round 30 pt card control (play, arrow, transport). Glance's main action on a card (play,
/// start, open) is a white disc with a dark glyph; secondary ones (skip) are dark with a rim.
struct GlanceRoundButton: View {
    let symbol: String
    var size: CGFloat = 30
    var filled = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(filled ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? Color.white : Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(filled ? 0 : 0.15), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Home: four equal cards. Each slot shows the widget the person picked (Music, Focus, Weather, Calendar by default),
/// over an optional backdrop. In customise mode the slots wiggle and a click picks one (TOPBAR-SPEC §4).
struct GlanceHomeCards: View {
    let topBar: TopBarModel
    var agentSummary = "No agents running"

    private var store: SettingsStore { .shared }

    var body: some View {
        let slots = HomeSlots((1...HomeSlots.count).map { store.string(HomeSlots.settingID(slot: $0)) })
        let backdrop = HomeBackdrop.resolve(store.string(HomeBackdrop.settingID))
        let editing = topBar.homeCustomizing
        HStack(spacing: GlanceTopBar.cardGap) {
            ForEach(1...HomeSlots.count, id: \.self) { slot in
                SlotFrame(slot: slot, kind: slots[slot], topBar: topBar, agentSummary: agentSummary)
            }
        }
        .environment(\.homeBackdropScrim, backdrop == .off ? 0 : (backdrop.isBusy ? 0.46 : 0.32))
        .frame(height: GlanceTopBar.cardHeight)
        .background {
            HomeBackdropView(backdrop: backdrop, visible: topBar.selectedTab == .home && !topBar.menuOpen)
                .clipShape(RoundedRectangle(cornerRadius: GlanceTopBar.cardRadius, style: .continuous))
                .opacity(0.62)
                .padding(.horizontal, -4)
        }
        .overlay(alignment: .topTrailing) { if !editing { BeamerHomeChip().padding(6) } }
        // The 0.7 s press is pointer-only: a right-click menu and a VoiceOver action reach customise mode too.
        .contextMenu {
            if !editing { Button("Customize Home") { topBar.beginHomeCustomize() } }
        }
        .accessibilityAction(named: "Customize Home") {
            if !topBar.homeCustomizing { topBar.beginHomeCustomize() }
        }
        .live { view in
            view.simultaneousGesture(LongPressGesture(minimumDuration: 0.7).onEnded { _ in
                if !topBar.homeCustomizing { topBar.beginHomeCustomize() }
            })
        }
    }
}

/// One slot: the widget, and in customise mode a wiggle, a rim and the click that selects it.
private struct SlotFrame: View {
    let slot: Int
    let kind: HomeWidgetKind
    let topBar: TopBarModel
    let agentSummary: String

    var body: some View {
        let editing = topBar.homeCustomizing
        let selected = topBar.homePickerSlot == slot
        let shape = RoundedRectangle(cornerRadius: GlanceTopBar.cardRadius, style: .continuous)
        ZStack {
            HomeWidgetCard(kind: kind, topBar: topBar, agentSummary: agentSummary)
                // In customise mode the card shows only its rim and name, so the name chip never covers content.
                .opacity(editing ? 0 : 1)
                .allowsHitTesting(!editing)
                .accessibilityHidden(editing)
            if editing {
                shape.strokeBorder(selected ? OB.controlAccent : Color.white.opacity(0.28),
                                   style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: selected ? [] : [4, 3]))
                // A real Button: focusable, Space/Return and VoiceOver press all select the slot.
                Button { topBar.homePickerSlot = slot } label: {
                    shape.fill(Color.black.opacity(0.001))
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Slot \(slot), \(kind.title)")
                .accessibilityHint("Choose this slot to change its widget.")
                .accessibilityAddTraits(selected ? .isSelected : [])
                // The card content is hidden in edit mode and the slot name sits alone in the middle,
                // so the pill never lands on a title or a number.
                HStack(spacing: 5) {
                    Image(systemName: kind.symbol).font(.system(size: 11, weight: .semibold))
                    Text(kind.title).font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(selected ? OB.controlAccentFill : Color.black.opacity(0.72)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)
            }
        }
        .frame(height: GlanceTopBar.cardHeight)
        .clipShape(shape)
        .modifier(Wiggle(active: editing, seed: Double(slot)))
    }
}

/// The edit-mode shiver. Reduce Motion (and snapshots) keep the cards still; the dashed rim says enough.
private struct Wiggle: ViewModifier {
    let active: Bool
    let seed: Double

    func body(content: Content) -> some View {
        if active && !Motion.reduced && !TopBarStyle.isSnapshot {
            TickingView(interval: 1.0 / 24.0) { context in
                content.rotationEffect(.degrees(sin(context.date.timeIntervalSinceReferenceDate * 13 + seed * 1.7) * 0.9))
            }
        } else {
            content
        }
    }
}

/// Under the cards in customise mode: the widget and style for the selected slot, then the backdrop and Done.
struct HomeCustomizeBar: View {
    let topBar: TopBarModel
    private var store: SettingsStore { .shared }

    var body: some View {
        let slot = topBar.homePickerSlot ?? 1
        let slots = HomeSlots((1...HomeSlots.count).map { store.string(HomeSlots.settingID(slot: $0)) })
        let kind = slots[slot]
        let variant = kind.resolveVariant(store.string(kind.variantSettingID))
        let backdrop = HomeBackdrop.resolve(store.string(HomeBackdrop.settingID))
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Slot \(slot)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7)).frame(width: 44, alignment: .leading)
                ForEach(HomeWidgetKind.allCases) { option in
                    Button { topBar.setHomeWidget(slot: slot, to: option) } label: {
                        Image(systemName: option.symbol).font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(option == kind ? Color.black : Color.white.opacity(0.85))
                            .frame(width: 26, height: 24)
                            .background(Capsule().fill(option == kind ? Color.white : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(PressableStyle())
                    .help(option.title)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(option == kind ? .isSelected : [])
                }
                if !kind.variants.isEmpty {
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 16).padding(.horizontal, 2)
                    ForEach(kind.variants) { option in
                        chip(option.title, selected: option.id == variant) { topBar.setHomeVariant(kind, to: option) }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: HomeCustomize.rowHeight - 4)
            HStack(spacing: 6) {
                Text("Backdrop").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7)).frame(width: 52, alignment: .leading)
                ForEach(HomeBackdrop.allCases) { option in
                    Button { topBar.setHomeBackdrop(option) } label: {
                        BackdropSwatch(backdrop: option, selected: option == backdrop)
                    }
                    .buttonStyle(PressableStyle())
                    .help(option.title)
                    .accessibilityLabel("Backdrop \(option.title)")
                    .accessibilityAddTraits(option == backdrop ? .isSelected : [])
                }
                Spacer(minLength: 0)
                Button { topBar.endHomeCustomize() } label: {
                    Text("Done").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.black)
                        .padding(.horizontal, 14).frame(height: 24)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Done customizing Home")
                .accessibilityIdentifier("home.customize.done")
            }
            .frame(height: HomeCustomize.rowHeight - 4)
        }
        .padding(.horizontal, 4)
        .frame(height: HomeCustomize.barHeight, alignment: .top)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 9).frame(height: 24)
                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.08)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A backdrop in miniature: the real drawing, held on one frame, in a small rounded square.
struct BackdropSwatch: View {
    let backdrop: HomeBackdrop
    var selected = false
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            if backdrop == .off {
                Color.white.opacity(0.06)
                Image(systemName: "nosign").font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(Color.white.opacity(0.5))
            } else {
                HomeBackdropView(backdrop: backdrop, visible: false, reduceMotion: true)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .strokeBorder(selected ? Color.white : Color.white.opacity(0.18), lineWidth: selected ? 2 : 1))
    }
}
