import AppKit
import EventKit
import SwiftUI
import UniformTypeIdentifiers
import ZeusCore

// MARK: Shared pieces

enum TopBarStyle {
    /// ImageRenderer can't draw scroll views, so snapshots lay pages out flat.
    @MainActor static var isSnapshot = false
    /// Glance's open panel: about 870 x 340 pt. Pages get the room under the tab row.
    static let panelWidth: CGFloat = 870
    static let pageHeight: CGFloat = 236
    /// Glance-feel motion: a soft spring with a touch of overshoot for open/close and pages.
    /// Measured from Glance's hover video: opens with no visible overshoot, closes firmly.
    static let openSpring = Animation.spring(response: GlanceTopBar.openSpring.response, dampingFraction: GlanceTopBar.openSpring.damping)
    static let closeMotion = Animation.linear(duration: GlanceTopBar.closeDuration)
    /// The selected tab's label: Glance draws it in a geometric sans; Plus Jakarta Sans (OFL, bundled).
    static var tabLabel: Font {
        GlassFonts.registered ? .custom(GlassFonts.family, size: 12.5).weight(.semibold) : .system(size: 12.5, weight: .semibold)
    }
    static let openHeightSpring = Animation.spring(response: GlanceTopBar.openHeightSpring.response, dampingFraction: GlanceTopBar.openHeightSpring.damping)
    @MainActor static var pageSpring: Animation? { Motion.page(reduceMotion: Motion.reduced) }
    static let tile = Glass.notchTile
    static let tileStroke = Glass.notchTileStroke
    /// Notch accent lighting: Zeus purple (was a hard-coded violet).
    static let violet = Theme.glow
    static let rec = Color(hex: 0xFF4D5E)

    static func label(_ size: CGFloat = 11, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// A rounded glass tile used by every zone and page.
private struct CardFinishOverrideKey: EnvironmentKey {
    static var defaultValue: CardFinish? { nil }
}

extension EnvironmentValues {
    /// A scoped appearance value, used by isolated hosts without reading process-global preferences.
    var cardFinishOverride: CardFinish? {
        get { self[CardFinishOverrideKey.self] }
        set { self[CardFinishOverrideKey.self] = newValue }
    }
}

struct Tile<Content: View>: View {
    @Environment(\.cardFinishOverride) private var finishOverride
    var padding: CGFloat = CardFinish.inset
    /// Home band tiles follow Home style; every other card follows Card style.
    var home = false
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        let finish: CardFinish? = finishOverride ?? (home ? CardFinish.home.finish : CardFinish.current)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .notchCard(finish, tint: finishOverride == nil && home && CardFinish.home.tinted ? tint : nil)
            .cardHoverLift()
    }
}

/// Small round icon button for the notch (big enough to hit, quiet until hovered).
struct GlyphButton: View {
    let symbol: String
    var size: CGFloat = 13
    var tint: Color = Theme.cloudPrimary
    let label: String
    let action: () -> Void


    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size + 15, height: size + 15)
                .background(Circle().fill(Color.white.opacity(0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())

        .help(label)
        .accessibilityLabel(label)
    }
}

/// Album tile: the real cover once it is fetched (crossfading in), over a gradient in the player's
/// own colour that stays as the placeholder while it loads or when no cover can be found.
struct AlbumTile: View {
    let playing: NowPlaying?
    /// Glance Home Music art tile is 48 pt (TOPBAR-SPEC §4); empty state keeps the quiet grey fill.
    var size: CGFloat = 48

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(10, size * 0.22), style: .continuous)
        let store = ArtworkStore.shared
        let art = store.image(for: playing)
        Group {
            if let playing {
                let hue = playing.hue
                shape
                    .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.65, brightness: 0.85),
                                                  Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Image(systemName: playing.player == .spotify ? "dot.radiowaves.left.and.right" : "music.note")
                            .font(.system(size: size * 0.35, weight: .medium))
                            .foregroundStyle(.white.opacity(art == nil ? 0.9 : 0))
                    )
                    .overlay {
                        if let art {
                            Image(nsImage: art)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFill()
                                .frame(width: size, height: size)
                                .clipShape(shape)
                                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                                .transition(.opacity)
                        }
                    }
                    .shadow(color: store.tint(for: playing, saturation: 0.7, brightness: 0.9).opacity(0.45), radius: size * 0.18)
            } else {
                shape.fill(Color.white.opacity(0.08))
                    .overlay(Image(systemName: "music.note").font(.system(size: 17, weight: .medium)).foregroundStyle(Color.white.opacity(0.55)))
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.reduced ? nil : .easeInOut(duration: 0.35), value: art != nil)
        .animation(Motion.reduced ? nil : .easeInOut(duration: 0.35), value: store.currentKey)
    }
}

/// Bars that dance while music plays, or follow the microphone while dictating.
struct LevelBars: View {
    var count = 4
    var color: Color
    var active: Bool
    /// When set, bars follow this level (0…1) instead of the built-in rhythm.
    var level: Double?
    var height: CGFloat = 14

    var body: some View {
        TickingView(interval: 1 / 30, paused: !active || Motion.reduced) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.6, height: barHeight(index: index, time: t))
                }
            }
            .frame(height: height)
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let phase: Double = sin(time * (5.1 + Double(index) * 1.7) + Double(index) * 1.3)
        let base: Double = level.map { max($0, 0.08) * (0.6 + 0.4 * abs(phase)) } ?? (0.35 + 0.65 * abs(phase))
        let fraction = CGFloat(active ? base : 0.2)
        return max(CGFloat(3), height * fraction)
    }
}

/// The finger on a progress line: its place while it is dragged, so the bar and the clock follow it.
@MainActor
@Observable
final class ScrubState {
    static let shared = ScrubState()
    var fraction: Double?
}

/// A thin progress bar. Give it `onSeek` and it becomes a scrubber: press or drag anywhere on it
/// and the bar follows the pointer; the seek is sent when the pointer is released.
/// Sixteen-step level bar for volume, brightness and keyboard backlight HUD cues.
struct HUDSegmentBar: View {
    let fraction: Double
    var muted: Bool = false
    private let segments = SystemHUDMath.segmentCount

    var body: some View {
        let filled = muted ? 0 : SystemHUDMath.filledSegmentCount(for: fraction)
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? Theme.cloudPrimary : Color.white.opacity(0.14))
                    .frame(width: 3, height: index < filled ? 10 : 6)
            }
        }
        .animation(Motion.reduced ? nil : .easeOut(duration: 0.08), value: filled)
    }
}

struct ProgressLine: View {
    let fraction: Double
    var tint: Color = Theme.cloudPrimary
    /// Called with 0...1 on release. nil keeps the line passive.
    var onSeek: ((Double) -> Void)?

    var body: some View {
        let scrub = ScrubState.shared
        let dragging = onSeek != nil ? scrub.fraction : nil
        let shown = min(max(dragging ?? fraction, 0), 1)
        GeometryReader { proxy in
            let barHeight: CGFloat = dragging == nil ? 3 : 5
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: barHeight)
                Capsule().fill(tint).frame(width: proxy.size.width * shown, height: barHeight)
                    .shadow(color: tint.opacity(0.6), radius: 3)
                if dragging != nil {
                    Circle().fill(Color.white).frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .offset(x: min(max(proxy.size.width * shown - 5.5, 0), proxy.size.width - 11))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(onSeek == nil ? nil : DragGesture(minimumDistance: 0)
                .onChanged { value in scrub.fraction = MusicSeek.fraction(x: value.location.x, width: proxy.size.width) }
                .onEnded { value in
                    let end = MusicSeek.fraction(x: value.location.x, width: proxy.size.width)
                    scrub.fraction = nil
                    onSeek?(end)
                })
        }
        .frame(height: onSeek == nil ? 3 : 16)
        .animation(Motion.reduced ? nil : .easeOut(duration: 0.12), value: dragging == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(onSeek == nil ? "Progress" : "Playback position")
        .accessibilityValue("\(Int(shown * 100)) percent")
        .accessibilityAdjustableAction { direction in
            guard let onSeek else { return }
            onSeek(min(max(fraction + (direction == .increment ? 0.05 : -0.05), 0), 1))
        }
    }
}

// MARK: Header

/// Tab icons along the top of the open notch, split around the camera housing like the
/// menu bar itself. The selected tab sits on a sliding pill.
struct TopBarHeader: View {
    let topBar: TopBarModel
    let agentCount: Int
    let needsYou: Bool
    let notchWidth: CGFloat
    let height: CGFloat
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Glance's layout: the menu-bar row stays clear around the notch (Mini ZEUS sits left of it),
    /// and the tabs live in one glass capsule just under it, the selected one showing its name.
    /// Glance's tab row (TOPBAR-SPEC §3): one 34 pt capsule of mono icons on white 10 %, the
    /// selected tab on an 80 x 28 pill with its name, plain grey counts, and only a 30 pt
    /// "more" circle on the right. The notch row above stays empty.
    var body: some View {
        if topBar.tabEditing {
            TabEditorRow(topBar: topBar)
        } else {
        HStack(spacing: 0) {
            HStack(spacing: GlanceTopBar.tabSpacing) {
                ForEach(rowTabs) { tab in item(tab) }
            }
            .padding(.horizontal, GlanceTopBar.capsuleInset.width)
            .padding(.vertical, GlanceTopBar.capsuleInset.height)
            .frame(height: GlanceTopBar.tabRowHeight)
            .background(Capsule().fill(GlanceTint.capsule))
            .overlay(Capsule().strokeBorder(GlanceTint.capsuleRim, lineWidth: 1))
            Spacer(minLength: 0)
            Button { MoreMenu.show(topBar: topBar) } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: GlanceTopBar.moreSize, height: GlanceTopBar.moreSize)
                    .background(Circle().fill(GlanceTint.more))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help("More")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("More")
            .accessibilityHint("Opens a menu with settings and the Zeus pointer toggle.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("notch.more")
        }
        .frame(height: GlanceTopBar.tabRowHeight)
        // N9 (parity/N9-glance-switch): new label appears at once; pill slides about 3 frames later
        // (~50 ms) and settles by about 420 ms. Labels use a blur-out removal, not a shared spring.
        .animation(nil, value: topBar.selectedTab)
        }
    }

    /// At most ten tabs, in your order; the selected one always shows.
    private var rowTabs: [TopBarTab] {
        GlanceTabRow.visible(topBar.layout.tabs, selected: topBar.selectedTab)
    }

    private func item(_ tab: TopBarTab) -> some View {
        let selected = topBar.selectedTab == tab
        return Button {
            topBar.selectedTab = tab
        } label: {
            HStack(spacing: selected ? 7 : 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.white.opacity(selected ? 1 : 0.78))
                    // A fixed 13 pt slot: symbol boxes are wider than their ink, which spread the row.
                    .frame(width: GlanceTopBar.tabIcon)
                if selected {
                    // Glance's geometric label (12.5 pt: its "Home" is 35 pt wide). Appears at once;
                    // the outgoing label blurs out (parity/N9 right column).
                    Text(tab.title)
                        .font(TopBarStyle.tabLabel)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(reduceMotion ? .identity : .asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.05)),
                            removal: .modifier(active: TabLabelBlur(blur: 5, opacity: 0),
                                               identity: TabLabelBlur(blur: 0, opacity: 1))
                                .animation(.easeOut(duration: 0.18))
                        ))
                }
                if let text = TabBadge.text(count(for: tab) ?? 0) {
                    // Plain grey counts beside the icon or label (Clipboard 52, Shelf 7), selected or not; no dots.
                    Text(text)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize()
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, selected ? 12 : GlanceTopBar.tabPadding)
            .frame(minWidth: selected ? GlanceTopBar.selectedPill.width : nil)
            .frame(height: GlanceTopBar.selectedPill.height)
            .background {
                if selected {
                    Capsule().fill(GlanceTint.pill)
                        .overlay(Capsule().strokeBorder(GlanceTint.pillRim, lineWidth: 1))
                        .matchedGeometryEffect(id: "pill", in: pill, properties: reduceMotion ? [] : .frame)
                        // Pill lags the label by about 3 frames at 60 fps, then springs (~420 ms).
                        .animation(Motion.page(reduceMotion: reduceMotion)?.delay(0.05), value: topBar.selectedTab)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(tab.help)
        // One element per tab: its name (and count), whether it is the open one, and what it does.
        // Unselected tabs draw only an icon, so the name must not come from the visible text.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count(for: tab).map { $0 > 0 ? "\(tab.help), \($0)" : tab.help } ?? tab.help)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(selected ? "" : "Shows \(tab.title).")
        .accessibilityIdentifier("notch.tab.\(tab.rawValue)")
    }

    /// Counts shown as numbers (Glance): alerts from the last day, files in the Inbox, clipboard items.
    private func count(for tab: TopBarTab) -> Int? {
        switch tab {
        case .notifications:
            let since = Date().addingTimeInterval(-86_400)
            return NotificationsController.shared.visibleItems.filter { $0.date > since }.count
        case .shelf: return topBar.shelf.count
        case .clipboard: return topBar.clipboard.entries.count
        default: return nil
        }
    }

}

/// Blur + fade used when a tab label leaves the selected pill (N9 Glance right column).
private struct TabLabelBlur: ViewModifier {
    var blur: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: blur).opacity(opacity)
    }
}

/// The ... button's menu: Settings, and where Zeus shows beside the pointer.
@MainActor
enum MoreMenu {
    static func show(topBar: TopBarModel) {
        let menu = NSMenu(title: "More")
        let settings = NSMenuItem(title: "Settings\u{2026}", action: #selector(MoreMenuTarget.openSettings), keyEquivalent: ",")
        settings.target = MoreMenuTarget.shared
        menu.addItem(settings)
        menu.addItem(.separator())
        let editTabs = NSMenuItem(title: "Edit tabs\u{2026}", action: #selector(MoreMenuTarget.editTabs), keyEquivalent: "")
        editTabs.target = MoreMenuTarget.shared
        menu.addItem(editTabs)
        if topBar.selectedTab == .home {
            let customize = NSMenuItem(title: "Customize Home\u{2026}", action: #selector(MoreMenuTarget.customizeHome), keyEquivalent: "")
            customize.target = MoreMenuTarget.shared
            menu.addItem(customize)
        }
        menu.addItem(.separator())
        let parent = NSMenuItem(title: "Show Zeus beside the pointer", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Show Zeus beside the pointer")
        for choice in BuddyShow.allCases {
            let item = NSMenuItem(title: choice.title, action: #selector(MoreMenuTarget.chooseBuddy(_:)), keyEquivalent: "")
            item.target = MoreMenuTarget.shared
            item.representedObject = choice.rawValue
            item.state = BuddyPreference.shared.show == choice ? .on : .off
            sub.addItem(item)
        }
        parent.submenu = sub
        menu.addItem(parent)
        menu.addItem(.separator())
        menu.addItem(ScreenShareQuickToggle.menuItem(target: MoreMenuTarget.shared, action: #selector(MoreMenuTarget.toggleScreenShareVisibility)))
        MoreMenuTarget.shared.topBar = topBar
        topBar.menuOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        topBar.menuOpen = false
    }
}

@MainActor
final class MoreMenuTarget: NSObject {
    static let shared = MoreMenuTarget()
    weak var topBar: TopBarModel?

    @objc func openSettings() { topBar?.openSettings() }
    @objc func editTabs() { topBar?.beginTabEditing() }
    @objc func customizeHome() { topBar?.beginHomeCustomize() }
    @objc func toggleScreenShareVisibility() { ScreenShareQuickToggle.toggle() }

    @objc func chooseBuddy(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let choice = BuddyShow(rawValue: raw) else { return }
        BuddyPreference.shared.show = choice
    }
}

// MARK: Pages

struct TopBarPage: View {
    let topBar: TopBarModel
    let agentSummary: String
    let agents: AnyView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch topBar.selectedTab {
            case .home:
                VStack(spacing: HomeStrip.gap) {
                    GlanceHomeCards(topBar: topBar, agentSummary: agentSummary)
                    if topBar.homeCustomizing {
                        HomeCustomizeBar(topBar: topBar).transition(.opacity)
                    } else if topBar.homeStrip.isVisible {
                        HomeStripView(topBar: topBar).transition(.opacity)
                    }
                }
            case .agents: agents
            case .music: MusicPage(topBar: topBar)
            case .calendar: CalendarPage(topBar: topBar)
            case .todo: TodoPage(topBar: topBar, todo: .shared)
            case .weather: WeatherPage(topBar: topBar)
            case .clipboard: ClipboardPage(topBar: topBar)
            case .shelf: ShelfPage(topBar: topBar)
            case .focus: FocusPage(topBar: topBar)
            case .dictation: DictationPage(topBar: topBar)
            case .teleprompter: TeleprompterPage(topBar: topBar)
            case .insomnia: InsomniaPage(insomnia: .shared)
            case .continuity: ContinuityPage()
            case .waves: WavesPage(topBar: topBar)
            case .polyglot: PolyglotPage(polyglot: .shared, topBar: topBar)
            case .recordly: RecordlyPage(topBar: topBar, recordly: topBar.recordlyForSnapshot ?? .shared)
            case .scribe: ScribePage(topBar: topBar, scribe: .shared)
            case .chat: ChatPage(chat: .shared)
            case .usage: UsagePage(usage: .shared)
            case .today: TodayPage(topBar: topBar, today: .shared)
            case .reminders: RemindersPage(topBar: topBar, reminders: .shared)
            case .notifications: NotificationsPage(topBar: topBar, notifications: .shared)
            }
        }
        .frame(height: GlanceTopBar.pageHeight(home: topBar.selectedTab == .home) + (topBar.selectedTab == .home ? topBar.homeExtraHeight : 0), alignment: .top)
        // Glance's section switch: the new page crossfades in with a small rise and scale.
        .transition(.asymmetric(insertion: reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.985, anchor: .top)),
                                // The old page leaves at once: fading it over the new one drew its title
                                // (e.g. Music's "Nothing playing") on top of the Calendar's add-event field.
                                removal: .identity))
        .id(topBar.selectedTab)
        .animation(Motion.page(reduceMotion: reduceMotion), value: topBar.selectedTab)
    }
}

struct MusicControls: View {
    let topBar: TopBarModel
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            GlyphButton(symbol: "backward.fill", size: size, label: "Previous") { topBar.musicCommand(.previous) }
            GlyphButton(symbol: topBar.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill", size: size + 3, label: "Play or pause") {
                topBar.musicCommand(.playPause)
            }
            GlyphButton(symbol: "forward.fill", size: size, label: "Next") { topBar.musicCommand(.next) }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
final class LyricsToggle: ObservableObject {
    /// Snapshots draw the page with the lyrics already showing.
    static var snapshotShow = false
    @Published var show = TopBarStyle.isSnapshot && LyricsToggle.snapshotShow
}

struct MusicPage: View {
    let topBar: TopBarModel
    /// The SwiftUI @State macro is unavailable to this toolchain, so the toggle lives in an ObservableObject.
    @StateObject private var lyricsToggle = LyricsToggle()
    private var showLyrics: Bool { lyricsToggle.show }

    var body: some View {
        let scrub = ScrubState.shared
        HStack(spacing: 14) {
            AlbumTile(playing: topBar.nowPlaying, size: 132)
            VStack(alignment: .leading, spacing: 8) {
                if showLyrics {
                    Text([topBar.nowPlaying?.title, topBar.nowPlaying?.artist].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " \u{00B7} "))
                        .font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                    LyricsView(playing: topBar.nowPlaying, rows: 3, rowHeight: 24, fontSize: 14)
                } else {
                    Text(topBar.nowPlaying?.title ?? "Nothing playing")
                        .font(TopBarStyle.label(17, .bold)).foregroundStyle(Theme.cloudPrimary).lineLimit(2)
                    Text([topBar.nowPlaying?.artist, topBar.nowPlaying?.album].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " \u{00B7} "))
                        .font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let playing = topBar.nowPlaying {
                    let tint = ArtworkStore.shared.tint(for: playing, saturation: 0.55, brightness: 1)
                    TickingView(interval: 1) { context in
                        let elapsed = scrub.fraction.map { $0 * playing.duration } ?? playing.elapsed(at: context.date)
                        VStack(spacing: 2) {
                            ProgressLine(fraction: MusicSeek.fraction(elapsed: playing.elapsed(at: context.date), duration: playing.duration),
                                         tint: tint,
                                         onSeek: playing.duration > 0 ? { fraction in
                                             if let seconds = MusicSeek.seconds(fraction: fraction, duration: playing.duration) { topBar.seek(seconds) }
                                         } : nil)
                            HStack {
                                Text(FocusTimer.format(elapsed))
                                Spacer()
                                Text(FocusTimer.format(playing.duration))
                            }
                            .font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudQuiet)
                        }
                    }
                }
                HStack {
                    MusicControls(topBar: topBar, size: 16)
                    OutputDeviceMenu(topBar: topBar)
                    GlyphButton(symbol: "quote.bubble", size: 12, tint: showLyrics ? Theme.glow : Theme.cloudSecondary,
                                label: showLyrics ? "Hide lyrics" : "Show lyrics") { withAnimation(TopBarStyle.pageSpring) { lyricsToggle.show.toggle() } }
                    GlyphButton(symbol: "arrow.up.forward.app", size: 12, tint: Theme.cloudSecondary,
                                label: "Open \(topBar.nowPlaying?.player.rawValue ?? "Music")") { topBar.musicCommand(.open) }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// Where the sound goes: a small menu of the Mac's outputs. Choosing one makes it the system output.
struct OutputDeviceMenu: View {
    let topBar: TopBarModel

    var body: some View {
        Button {
            topBar.chooseOutputDevice()
        } label: {
            Image(systemName: "hifispeaker.and.homepod.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.cloudSecondary)
                .frame(width: 27, height: 27)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help("Output device")
        .accessibilityLabel("Choose the output device")
    }
}

struct CalendarPage: View {
    let topBar: TopBarModel

    var body: some View {
        VStack(spacing: 8) {
            QuickAddEventBar(topBar: topBar)
            if topBar.calendarAccess == .denied {
                AccessPrompt(symbol: "calendar", title: "See and add events",
                             detail: "Calendar access is off. Turn it on in System Settings, Privacy & Security, Calendars.",
                             button: "Open Settings") { topBar.openPermissions() }
            } else {
                HStack(spacing: 8) {
                    Tile(padding: 8) { CalendarMonthGrid(topBar: topBar) }
                        .frame(width: 262)
                    Tile(padding: 8) { CalendarDayList(topBar: topBar) }
                    Tile(padding: 8) { CalendarSidePanel(topBar: topBar) }
                        .frame(width: 232)
                }
            }
        }
        .onAppear { if !TopBarStyle.isSnapshot { topBar.refreshCalendarMonth() } }
    }
}

/// "Lunch with Ana tomorrow at 1 pm": one field, Return adds it. The first add asks for Calendar access.
private struct QuickAddEventBar: View {
    let topBar: TopBarModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").font(.system(size: 14)).foregroundStyle(Theme.glow).accessibilityHidden(true)
            if TopBarStyle.isSnapshot {
                Text(topBar.quickAddText.isEmpty ? "Add an event: lunch with Ana tomorrow at 1 pm" : topBar.quickAddText)
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.white.opacity(topBar.quickAddText.isEmpty ? 0.4 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                NotchTextField(text: Binding(get: { topBar.quickAddText }, set: { topBar.quickAddText = $0 }),
                               placeholder: "Add an event: lunch with Ana tomorrow at 1 pm", onSubmit: submit)
                    .accessibilityLabel("Add an event")
            }
            if let note = topBar.quickAddNote {
                Text(note).font(.system(size: 10.5)).foregroundStyle(Theme.cloudSecondary).lineLimit(1).truncationMode(.tail).frame(maxWidth: 300, alignment: .trailing)
            }
            Button(action: submit) {
                Text("Add").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.black)
                    .padding(.horizontal, 12).frame(height: 22).background(Capsule().fill(Color.white))
            }
            .buttonStyle(PressableStyle())
            .disabled(topBar.quickAddText.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Add event")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func submit() {
        let text = topBar.quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { @MainActor in _ = await topBar.addEvent(from: text) }
    }
}

/// A month: arrows, the title, weekday initials, days with a dot under the busy ones; a click picks the day.
private struct CalendarMonthGrid: View {
    let topBar: TopBarModel

    var body: some View {
        let calendar = ZeusDates.calendar()
        let weeks = CalendarGrid.weeks(month: topBar.calendarMonth, calendar: calendar)
        let month = calendar.component(.month, from: topBar.calendarMonth)
        let today = Date()
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(ZeusDates.string(topBar.calendarMonth, template: "MMMMy")).font(TopBarStyle.label(12, .bold)).foregroundStyle(Theme.cloudPrimary)
                Spacer()
                navButton("chevron.left", "Previous month") { topBar.showMonth(offset: -1) }
                Button { topBar.goToToday() } label: {
                    Text("Today").font(TopBarStyle.label(10, .semibold)).foregroundStyle(Theme.cloudSecondary)
                        .padding(.horizontal, 7).frame(height: 20).background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PressableStyle())
                navButton("chevron.right", "Next month") { topBar.showMonth(offset: 1) }
            }
            HStack(spacing: 0) {
                ForEach(Array(CalendarGrid.weekdayInitials(calendar: calendar).enumerated()), id: \.offset) { _, initial in
                    Text(initial).font(TopBarStyle.label(9, .semibold)).foregroundStyle(Theme.cloudQuiet).frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in dayCell(day, month: month, today: today, calendar: calendar) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func navButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.cloudSecondary)
                .frame(width: 22, height: 20).background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private func dayCell(_ day: Date, month: Int, today: Date, calendar: Calendar) -> some View {
        let inMonth = calendar.component(.month, from: day) == month
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let picked = calendar.isDate(day, inSameDayAs: topBar.calendarDay)
        let colors = topBar.events(on: day).prefix(3).map { Color(hex: $0.colorHex) }
        return Button { topBar.pickDay(day) } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 11, weight: isToday || picked ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isToday ? Color.black : (inMonth ? Theme.cloudPrimary : Theme.cloudQuiet.opacity(0.5)))
                    .frame(width: 22, height: 20)
                    .background { if isToday { Circle().fill(Color.white) } else if picked { Circle().strokeBorder(Theme.glow, lineWidth: 1.5) } }
                HStack(spacing: 1.5) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in Circle().fill(color).frame(width: 3, height: 3) }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(ZeusDates.style.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// The picked day's events; a click opens one in the panel on the right.
private struct CalendarDayList: View {
    let topBar: TopBarModel

    var body: some View {
        let events = topBar.events(on: topBar.calendarDay)
        VStack(alignment: .leading, spacing: 6) {
            Text(topBar.calendarDay.formatted(ZeusDates.style.weekday(.wide).day().month(.wide)).uppercased())
                .font(TopBarStyle.label(9.5, .bold)).foregroundStyle(Theme.ember)
            if events.isEmpty {
                Text(topBar.calendarAccess == .granted ? "Nothing on this day" : "Add your first event above. Zeus asks for Calendar access then.")
                    .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudQuiet)
            }
            PageScroll(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events) { event in
                        Button { topBar.calendarDetailID = event.id } label: {
                            EventRow(event: event, openURL: topBar.openURL, selected: topBar.calendarDetailID == event.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the details.")
                    }
                }
            }
        }
    }
}

/// Details of the picked event, or the open reminders when none is picked.
private struct CalendarSidePanel: View {
    let topBar: TopBarModel

    var body: some View {
        if let id = topBar.calendarDetailID, let event = topBar.calendarEvents.first(where: { $0.id == id }) ?? topBar.events.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Capsule().fill(Color(hex: event.colorHex)).frame(width: 3, height: 16)
                    Text(event.title).font(TopBarStyle.label(13, .bold)).foregroundStyle(Theme.cloudPrimary).lineLimit(2)
                }
                Text(event.isAllDay ? "All day, \(event.start.formatted(ZeusDates.style.weekday(.abbreviated).day().month(.abbreviated)))"
                     : "\(event.start.formatted(ZeusDates.style.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) – \(event.end.formatted(ZeusDates.style.hour().minute()))")
                    .font(TopBarStyle.label(10.5).monospacedDigit()).foregroundStyle(Theme.cloudSecondary)
                if let name = event.calendarName { detail("calendar", name) }
                if let location = event.location, !location.isEmpty { detail("mappin.and.ellipse", location) }
                if let notes = event.notes, !notes.isEmpty { detail("note.text", notes) }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let url = event.meetingURL {
                        NotchActionButton(title: "Join", tint: Theme.leaf) { topBar.openURL(url) }
                    }
                    NotchActionButton(title: "Close", tint: Theme.cloudSecondary, filled: false) { topBar.calendarDetailID = nil }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("REMINDERS").font(TopBarStyle.label(9.5, .bold)).foregroundStyle(Theme.ember)
                let remindersAllowed = TopBarStyle.isSnapshot || EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
                if !remindersAllowed {
                    Text("Allow Reminders to see them here.").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudQuiet)
                    NotchActionButton(title: "Allow Reminders", tint: Theme.bolt) { topBar.openPermissions() }
                } else if topBar.openReminders.isEmpty {
                    Text("All done").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudQuiet)
                }
                ForEach(remindersAllowed ? Array(topBar.openReminders.prefix(6)) : []) { reminder in
                    HStack(spacing: 6) {
                        Circle().strokeBorder(Theme.cloudSecondary, lineWidth: 1.2).frame(width: 11, height: 11)
                        Text(reminder.title).font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9.5)).foregroundStyle(Theme.cloudQuiet).frame(width: 12)
            Text(text).font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudSecondary).lineLimit(2)
        }
    }
}

private struct EventRow: View {
    let event: TopBarModel.CalendarItem
    let openURL: (URL) -> Void
    var selected = false

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(Color(hex: event.colorHex)).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(TopBarStyle.label(11.5, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                Text(event.isAllDay ? "All day" : "\(event.start.formatted(ZeusDates.style.hour().minute())) – \(event.end.formatted(ZeusDates.style.hour().minute()))")
                    .font(TopBarStyle.label(10).monospacedDigit()).foregroundStyle(Theme.cloudQuiet)
            }
            Spacer(minLength: 0)
            if let url = event.meetingURL {
                Button("Join") { openURL(url) }
                    .buttonStyle(PressableStyle())
                    .font(TopBarStyle.label(11, .bold))
                    .foregroundStyle(Theme.storm)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.leaf))
                    .accessibilityLabel("Join \(event.title)")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.white.opacity(0.08) : Color.clear))
        .contentShape(Rectangle())
    }
}

struct WeatherPage: View {
    let topBar: TopBarModel

    var body: some View {
        if let weather = topBar.weather {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 40))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(topBar.temperature(weather.temperature))  \(weather.phrase)")
                            .font(TopBarStyle.label(18, .bold)).foregroundStyle(Theme.cloudPrimary)
                        Text("\(topBar.weatherPlace) · feels \(topBar.temperature(weather.apparent)) · humidity \(weather.humidity)% · wind \(Int(weather.wind)) km/h")
                            .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                    }
                    Spacer()
                    GlyphButton(symbol: "arrow.clockwise", size: 11, tint: Theme.cloudSecondary, label: "Refresh weather") { topBar.refreshWeather() }
                }
                if let rain = weather.rainSoon() {
                    Label("Rain likely around \(rain.time.formatted(ZeusDates.style.hour()))", systemImage: "umbrella.fill")
                        .font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.sky)
                }
                HStack(spacing: 6) {
                    ForEach(Array(weather.hours.prefix(8).enumerated()), id: \.offset) { _, hour in
                        VStack(spacing: 4) {
                            Text(hour.time.formatted(ZeusDates.style.hour())).font(TopBarStyle.label(9.5)).foregroundStyle(Theme.cloudQuiet)
                            Image(systemName: WeatherSnapshot.symbol(for: hour.sky, isDay: true))
                                .symbolRenderingMode(.multicolor).font(.system(size: 15))
                            Text(topBar.temperature(hour.temperature)).font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(TopBarStyle.tile, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
        } else {
            // With no city typed and a time zone that names none (UTC, GMT) no fetch ever starts.
            if topBar.weatherCity.trimmingCharacters(in: .whitespaces).isEmpty, !TimeZone.current.identifier.contains("/") {
                AccessPrompt(symbol: "cloud.sun.fill", title: "Weather", detail: "Type your city in Settings to see the weather.",
                             button: "Open Settings") { topBar.openSettings() }
            } else {
                AccessPrompt(symbol: "cloud.sun.fill", title: "Weather", detail: topBar.weatherError ?? "Loading the forecast for your city…",
                             button: "Try again") { topBar.refreshWeather() }
            }
        }
    }
}

/// The Clipboard page's search text (kept here: this toolchain has no @State).
@MainActor
@Observable
final class ClipboardSearchState {
    static let shared = ClipboardSearchState()
    var query = ""
}

struct ClipboardPage: View {
    let topBar: TopBarModel

    private var filtered: [ClipboardEntry] {
        let found = Set(topBar.clipboard.search(ClipboardSearchState.shared.query).map(\.id))
        return topBar.clipboard.entries.filter { topBar.clipboardFilter.includes($0) && found.contains($0.id) }
    }

    var body: some View {
        if topBar.clipboard.entries.isEmpty {
            AccessPrompt(symbol: "doc.on.clipboard", title: "Clipboard empty",
                         detail: "Copy anything. Click an item to copy it again. Passwords that password managers mark as concealed are never kept.",
                         button: nil) {}
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(TopBarModel.ClipboardFilter.allCases) { item in
                        Button {
                            topBar.clipboardFilter = item
                        } label: {
                            Text(item.rawValue)
                                .font(TopBarStyle.label(11, .semibold))
                                .foregroundStyle(topBar.clipboardFilter == item ? .white : Theme.cloudSecondary)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(Capsule().fill(Color.white.opacity(topBar.clipboardFilter == item ? 0.16 : 0.06)))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cloudQuiet)
                        .accessibilityHidden(true)
                    if !TopBarStyle.isSnapshot {
                        NotchTextField(text: Binding(get: { ClipboardSearchState.shared.query }, set: { ClipboardSearchState.shared.query = $0 }),
                                       placeholder: "Search", onSubmit: {})
                            .frame(width: 130, height: 22)
                            .accessibilityLabel("Search the clipboard")
                    }
                    GlyphButton(symbol: "trash", size: 10, tint: Theme.cloudSecondary, label: "Clear clipboard") {
                        topBar.clipboard.clear()
                    }
                }
                PageScroll(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(filtered) { entry in
                            ClipboardRow(entry: entry, topBar: topBar)
                        }
                    }
                }
                HStack {
                    Text("\(filtered.count) of \(topBar.clipboard.entries.count) items. Text stays in memory; images are cached on this Mac until removed. Keeps the latest \(topBar.clipboard.limit), plus pins.")
                        .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
                    Spacer()
                }
            }
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let topBar: TopBarModel

    private var hasThumb: Bool { entry.kind == .image || entry.kind == .file }
    private var symbol: String {
        if entry.pinned { return "pin.fill" }
        switch entry.kind {
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .text: return "text.alignleft"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if hasThumb, let thumb = ClipboardMedia.thumbnail(for: entry) {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: entry.kind == .image ? .fill : .fit)
                    .frame(width: 44, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(entry.pinned ? Theme.bolt : Theme.cloudQuiet).frame(width: 14)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.preview).font(TopBarStyle.label(11.5)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                if entry.kind == .file, entry.filePaths.count == 1, let first = entry.filePaths.first {
                    Text((first as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(TopBarStyle.label(9.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 6)
            if (topBar.hovered == "c\(entry.id)") {
                GlyphButton(symbol: entry.pinned ? "pin.slash" : "pin", size: 10, tint: Theme.cloudSecondary, label: entry.pinned ? "Unpin" : "Pin") {
                    topBar.clipboard.togglePin(entry.id)
                }
                GlyphButton(symbol: "xmark", size: 10, tint: Theme.cloudSecondary, label: "Remove") {
                    topBar.clipboard.remove(entry.id)
                    ClipboardMedia.prune(keeping: topBar.clipboard.imageFilesInUse)
                }
            } else {
                Text(entry.sourceApp ?? "").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: hasThumb ? 40 : 30)
        .background(Color.white.opacity((topBar.hovered == "c\(entry.id)") ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { topBar.hovered = $0 ? "c\(entry.id)" : (topBar.hovered == "c\(entry.id)" ? nil : topBar.hovered) }
        .onTapGesture {
            if entry.kind == .text || entry.kind == .link { topBar.copyText(entry.text) } else { ClipboardMedia.copyBack(entry) }
            topBar.show(.copied(entry.preview))
        }
        .live { $0.onDrag { ClipboardMedia.dragProvider(for: entry) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Copies this again. Drag it out to drop it elsewhere.")
        // Pin and Remove only draw while hovered; VoiceOver and the keyboard get them here.
        .accessibilityAction(named: entry.pinned ? "Unpin" : "Pin") { topBar.clipboard.togglePin(entry.id) }
        .accessibilityAction(named: "Remove") { removeEntry() }
        .contextMenu {
            Button(entry.pinned ? "Unpin" : "Pin") { topBar.clipboard.togglePin(entry.id) }
            Button("Remove", role: .destructive) { removeEntry() }
        }
    }

    private func removeEntry() {
        topBar.clipboard.remove(entry.id)
        ClipboardMedia.prune(keeping: topBar.clipboard.imageFilesInUse)
    }
}

struct ShelfPage: View {
    let topBar: TopBarModel
    

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 6) {
                Image(systemName: topBar.shelfTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(topBar.shelfTargeted ? Theme.bolt : Theme.cloudSecondary)
                    .scaleEffect(topBar.shelfTargeted && !Motion.reduced ? 1.12 : 1)
                Text("Drop files here").font(TopBarStyle.label(11.5, .semibold)).foregroundStyle(Theme.cloudPrimary)
                Text("Drag them out again, AirDrop, or transcribe audio")
                    .font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet).multilineTextAlignment(.center)
            }
            .frame(width: 220)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: CardFinish.radius, style: .continuous)
                .strokeBorder(topBar.shelfTargeted ? Theme.bolt : TopBarStyle.tileStroke, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: topBar.shelfTargeted)

            PageScroll(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(topBar.shelf) { item in ShelfCell(item: item, topBar: topBar).contextMenu { ShelfBrainMenu(url: item.url) } }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .live { $0.onDrop(of: [.fileURL], isTargeted: Binding(get: { topBar.shelfTargeted }, set: { topBar.shelfTargeted = $0 })) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { topBar.addToShelf([url]) } }
                }
            }
            return true
        } }
    }
}

private struct ShelfCell: View {
    let item: TopBarModel.ShelfItem
    let topBar: TopBarModel


    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 52, height: 52)
            Text(item.name).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudPrimary).lineLimit(1).frame(width: 84)
            HStack(spacing: 0) {
                GlyphButton(symbol: "airplayaudio", size: 9, tint: Theme.cloudSecondary, label: "AirDrop") {
                    NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [item.url])
                }
                if item.isMedia {
                    GlyphButton(symbol: "text.bubble", size: 9, tint: Theme.cloudSecondary, label: "Transcribe") { topBar.transcribeFile(item.url) }
                }
                GlyphButton(symbol: "xmark", size: 9, tint: Theme.cloudSecondary, label: "Remove from shelf") { topBar.removeFromShelf(item.id) }
            }
            .opacity((topBar.hovered == "s\(item.id)") ? 1 : 0.0)
        }
        .padding(6)
        .background(Color.white.opacity((topBar.hovered == "s\(item.id)") ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { topBar.hovered = $0 ? "s\(item.id)" : (topBar.hovered == "s\(item.id)" ? nil : topBar.hovered) }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .live { $0.onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() } }
        .accessibilityLabel(item.name)
    }
}

struct FocusPage: View {
    let topBar: TopBarModel

    var body: some View {
        TickingView(interval: 0.5) { context in
            let timer = topBar.focus
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 8)
                    Circle().trim(from: 0, to: timer.progress(at: context.date))
                        .stroke(timer.phase == .rest ? Theme.leaf : TopBarStyle.violet, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: TopBarStyle.violet.opacity(0.6), radius: 6)
                    VStack(spacing: 2) {
                        Text(FocusTimer.format(timer.phase == .idle ? timer.focusLength : timer.remaining(at: context.date)))
                            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Theme.cloudPrimary)
                        Text(timer.phase == .rest ? "Break" : timer.isPaused ? "Paused" : timer.phase == .focus ? "Focus" : "Ready")
                            .font(TopBarStyle.label(10.5, .semibold)).foregroundStyle(Theme.cloudSecondary)
                    }
                }
                .frame(width: 132, height: 132)
                .contentShape(Circle())
                .live { $0.gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let timer = topBar.focus
                    let current = timer.phase == .idle ? Int(timer.focusLength / 60) : Int((timer.remaining() / 60).rounded())
                    let fraction = FocusDial.fraction(dx: drag.location.x - 66, dy: drag.location.y - 66)
                    topBar.focus.setTime(minutes: FocusDial.minutes(fraction: fraction, previous: current))
                }) }
                .accessibilityLabel("Focus time")
                .accessibilityValue("\(Int((timer.phase == .idle ? timer.focusLength : timer.remaining(at: context.date)) / 60)) minutes")
                .accessibilityAdjustableAction { direction in
                    let t = topBar.focus
                    let minutes = t.phase == .idle ? Int(t.focusLength / 60) : Int((t.remaining() / 60).rounded())
                    topBar.focus.setTime(minutes: max(5, minutes + (direction == .increment ? 5 : -5)))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rounds today: \(timer.roundsToday(at: context.date))").font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary)
                    Text("Drag the ring to set the time").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet)
                    HStack(spacing: 6) {
                        ForEach([15, 25, 50], id: \.self) { minutes in
                            chip("\(minutes) min", selected: Int(timer.focusLength / 60) == minutes) {
                                topBar.focus.focusLength = Double(minutes * 60)
                            }
                        }
                        chip("+5 min", selected: false) { topBar.focus.extend() }
                    }
                    HStack(spacing: 8) {
                        if timer.phase == .idle {
                            NotchActionButton(title: "Start focus", tint: TopBarStyle.violet) { topBar.focus.start() }
                        } else {
                            NotchActionButton(title: timer.isPaused ? "Resume" : "Pause", tint: TopBarStyle.violet) {
                                timer.isPaused ? topBar.focus.resume() : topBar.focus.pause()
                            }
                            NotchActionButton(title: "Stop", tint: Theme.cloudSecondary, filled: false) { topBar.focus.stop() }
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(TopBarStyle.label(11, .semibold))
                .foregroundStyle(selected ? Theme.storm : Theme.cloudSecondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(selected ? TopBarStyle.violet : Color.white.opacity(0.08)))
        }
        .buttonStyle(PressableStyle())
    }
}

struct DictationPage: View {
    let topBar: TopBarModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Tile(padding: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(topBar.isDictating ? TopBarStyle.rec : Color.white.opacity(0.1)).frame(width: 30, height: 30)
                            Image(systemName: topBar.isDictating ? "waveform" : "mic.fill")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(status).font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                            Text(hint).font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet).lineLimit(2)
                        }
                    }
                    Text("MODE").font(TopBarStyle.label(9.5, .bold)).foregroundStyle(Theme.cloudQuiet)
                    FlowChips(modes: topBar.dictationModes, selected: topBar.selectedModeKey) { topBar.selectedModeKey = $0 }
                    Spacer(minLength: 0)
                    Button { topBar.chooseFileToTranscribe() } label: {
                        Label("Transcribe a file…", systemImage: "doc.text.magnifyingglass").font(TopBarStyle.label(11, .semibold))
                    }
                    .buttonStyle(PressableStyle()).foregroundStyle(Theme.sky)
                }
            }
            .frame(width: 360)
            Tile(padding: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("HISTORY").font(TopBarStyle.label(9.5, .bold)).foregroundStyle(Theme.cloudQuiet)
                        Spacer()
                        Text("\(wordsToday) words today").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudQuiet)
                    }
                    if topBar.dictationHistory.isEmpty {
                        Text("Your dictations appear here, on this Mac only.").font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudQuiet)
                    }
                    PageScroll(.vertical) {
                        VStack(spacing: 4) {
                            ForEach(topBar.dictationHistory.prefix(20)) { record in
                                HStack(spacing: 6) {
                                    Text(record.result).font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(record.modeName).font(TopBarStyle.label(9.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
                                    GlyphButton(symbol: "doc.on.doc", size: 9, tint: Theme.cloudSecondary, label: "Copy") {
                                        topBar.copyText(record.result)
                                        topBar.show(.copied(record.result))
                                    }
                                }
                                .padding(.horizontal, 6)
                                .frame(height: 24)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
    }

    private var status: String {
        switch topBar.dictationPhase {
        case .idle, .done: "Ready to dictate"
        case .listening: "Listening · \(topBar.dictationModeName)"
        case .transcribing: "Transcribing on your Mac…"
        case .rewriting: "Polishing with \(topBar.dictationModeName)…"
        case .failed(let message): message
        }
    }

    private var hint: String {
        if case .listening = topBar.dictationPhase, !topBar.dictationPartial.isEmpty { return topBar.dictationPartial }
        let key = DictationSettings.shared.key?.symbols ?? "a dictation key (Settings)"
        return "Hold \(key) and speak; release to type. Double-tap for hands-free, Esc cancels."
    }

    private var wordsToday: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return topBar.dictationHistory.filter { $0.datetime >= start }.reduce(0) { $0 + $1.wordCount }
    }
}

private struct FlowChips: View {
    let modes: [DictationMode]
    let selected: String
    let choose: (String) -> Void

    var body: some View {
        let rows = stride(from: 0, to: modes.count, by: 3).map { Array(modes[$0..<min($0 + 3, modes.count)]) }
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row) { mode in
                        Button { choose(mode.key) } label: {
                            Label(mode.name, systemImage: mode.symbol)
                                .font(TopBarStyle.label(10.5, .semibold))
                                .foregroundStyle(mode.key == selected ? Theme.storm : Theme.cloudSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(mode.key == selected ? Theme.cloudPrimary : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(PressableStyle())
                        .help(mode.usesAI ? "Rewrites with your Claude plan" : "Plain voice to text, fully on your Mac")
                    }
                }
            }
        }
    }
}

struct AccessPrompt: View {
    let symbol: String
    let title: String
    let detail: String
    let button: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).symbolRenderingMode(.multicolor).font(.system(size: 34)).foregroundStyle(Theme.cloudSecondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(TopBarStyle.label(14, .bold)).foregroundStyle(Theme.cloudPrimary)
                Text(detail).font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudSecondary).fixedSize(horizontal: false, vertical: true)
                if let button { NotchActionButton(title: button, tint: Theme.bolt, action: action) }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }
}

struct NotchActionButton: View {
    let title: String
    let tint: Color
    var filled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TopBarStyle.label(12, .semibold))
                .foregroundStyle(filled ? Theme.storm : tint)
                .padding(.horizontal, 14)
                .frame(minHeight: 28)
                .background(Capsule().fill(filled ? tint : Color.white.opacity(0.12)))
                .shadow(color: filled ? tint.opacity(0.5) : .clear, radius: 6)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: Closed-notch wings

/// What sits either side of the camera housing while the notch is closed: a cue, a live
/// dictation, a focus countdown or the track that's playing (in that order of importance).
struct ClosedWings: View {
    let topBar: TopBarModel

    enum Kind: Equatable { case recordly, scribe, recordingFeedback, cue(NotchCue), dictation, avatar(AvatarState), focus, music, none }

    static func kind(of topBar: TopBarModel) -> Kind {
        if RecordlyController.shared.isRecording { return .recordly }
        if ScribeController.shared.isRecording { return .scribe }
        if topBar.isDictating { return .dictation }
        if RecordlyController.shared.topBarFeedback() != nil || ScribeController.shared.topBarFeedback() != nil {
            return .recordingFeedback
        }
        if let cue = topBar.cue { return .cue(cue) }
        let avatar = AvatarStatus.shared
        if avatar.posePreview != nil || avatar.current != .idle { return .avatar(avatar.current) }
        if topBar.focus.phase != .idle, SettingsStore.shared.bool("lights.timer") { return .focus }
        if topBar.liveMusicWings, topBar.nowPlaying?.isPlaying == true { return .music }
        if avatar.alwaysInNotch { return .avatar(.idle) }
        return .none
    }

    var body: some View {
        switch Self.kind(of: topBar) {
        case .recordly:
            wings {
                RecordingActivityWings.Leading(input: .recordly(elapsed: RecordlyController.shared.elapsed))
            } right: {
                HStack(spacing: 8) {
                    // Scribe captures audio too: its indicator must not vanish while Recordly records.
                    if ScribeController.shared.isRecording {
                        ScribeWings.Leading(elapsed: ScribeController.shared.elapsed, compact: true, announces: true)
                    } else if let snapshot = ScribeController.shared.topBarFeedback() {
                        RecordingFeedbackView(snapshot: snapshot) { topBar.onOpenTab(.scribe) }
                    }
                    RecordingActivityWings.Trailing(
                        input: .recordly(elapsed: RecordlyController.shared.elapsed),
                        elapsedText: RecordlyElapsed.format(RecordlyController.shared.elapsed)
                    ) {
                        Task { await RecordlyController.shared.stop() }
                    }
                }
            }
        case .scribe:
            let scribe = ScribeController.shared
            wings {
                ScribeWings.Leading(elapsed: scribe.elapsed)
            } right: {
                HStack(spacing: 5) {
                    ScribeWings.Trailing(scribe: scribe, topBar: topBar)
                    if let snapshot = RecordlyController.shared.topBarFeedback() {
                        RecordingFeedbackView(snapshot: snapshot) { topBar.onOpenTab(.recordly) }
                    }
                }
            }
        case .recordingFeedback:
            wings {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 16)).foregroundStyle(Theme.glow)
                    .accessibilityHidden(true)
            } right: {
                HStack(spacing: 5) {
                    if let snapshot = RecordlyController.shared.topBarFeedback() {
                        RecordingFeedbackView(snapshot: snapshot) { topBar.onOpenTab(.recordly) }
                    }
                    if let snapshot = ScribeController.shared.topBarFeedback() {
                        RecordingFeedbackView(snapshot: snapshot) { topBar.onOpenTab(.scribe) }
                    }
                }
            }
        case .dictation:
            wings {
                HStack(spacing: 5) {
                    Circle().fill(TopBarStyle.rec).frame(width: 7, height: 7).shadow(color: TopBarStyle.rec, radius: 4)
                    Image(systemName: topBar.dictationModeSymbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.cloudPrimary)
                }
            } right: {
                if topBar.dictationPhase == .listening {
                    DictationWave(levels: topBar.dictationLevels, color: TopBarStyle.rec)
                } else {
                    ProgressView().controlSize(.mini).tint(Theme.cloudPrimary)
                }
            }
        case .cue(let cue):
            wings { cueIcon(cue) } right: { cueDetail(cue) }
        case .avatar(let state):
            // ZEUS itself: the v2 mascot posed for what it is doing, and a word for it.
            wings { MiniMascotView(state: state, size: 22) } right: {
                if state != .idle {
                    Text(state.short).font(TopBarStyle.label(10.5, .semibold)).foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1).contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: state)
                }
            }
        case .focus:
            wings {
                Image(systemName: "timer").font(.system(size: 11, weight: .bold)).foregroundStyle(TopBarStyle.violet)
            } right: {
                TickingView(interval: 1) { context in
                    Text(FocusTimer.format(topBar.focus.remaining(at: context.date)))
                        .font(TopBarStyle.label(11, .semibold).monospacedDigit()).foregroundStyle(TopBarStyle.violet)
                }
            }
        case .music:
            wings { AlbumTile(playing: topBar.nowPlaying, size: 18) } right: {
                LevelBars(color: ArtworkStore.shared.tint(for: topBar.nowPlaying, saturation: 0.55, brightness: 1), active: true, height: 12)
            }
        case .none:
            EmptyView()
        }
    }

    private func wings<L: View, R: View>(@ViewBuilder left: () -> L, @ViewBuilder right: () -> R) -> some View {
        // Width springs via `NotchView.wingsSpring`; scale insertion caused a one-frame full-size jump (R24 C1).
        HStack(spacing: 0) {
            left().frame(width: Self.wingWidth - 14, alignment: .leading)
            Spacer(minLength: 0)
            right().frame(width: Self.wingWidth - 14 + Self.extraWidth(for: topBar), alignment: .trailing)
        }
    }

    static let wingWidth: CGFloat = 62
    /// Cues with text get a wider right wing.
    static func extraWidth(for topBar: TopBarModel) -> CGFloat {
        switch kind(of: topBar) {
        case .cue(let cue):
            switch cue {
            case .copied, .trackChanged, .focusFinished, .dictation, .usageAlert, .decided, .hint, .keepAwake: return 150
            case .permission: return 230
            case .shortcut, .rain: return 70
            case .volume, .brightness, .keyboardBacklight: return 58
            default: return 30
            }
        // An idle mascot has no word beside it, so the closed bar hugs the notch and the mascot (finding 24).
        case .avatar(let state): return state == .idle ? -36 : 14
        case .dictation: return 60
        case .recordly:
            if ScribeController.shared.isRecording { return 230 }
            return ScribeController.shared.topBarFeedback() != nil ? 300 : 110
        case .scribe: return RecordlyController.shared.topBarFeedback() != nil ? 300 : 230
        case .recordingFeedback:
            return RecordlyController.shared.topBarFeedback() != nil && ScribeController.shared.topBarFeedback() != nil ? 300 : 180
        case .none: return 0
        default: return 0
        }
    }

    @ViewBuilder
    private func cueIcon(_ cue: NotchCue) -> some View {
        let (symbol, color): (String, Color) = switch cue {
        case .copied: ("doc.on.doc.fill", Theme.sky)
        case .capsLock(let on): (on ? "capslock.fill" : "capslock", on ? Theme.bolt : Theme.cloudSecondary)
        case .volume(let level, let muted): (muted || level == 0 ? "speaker.slash.fill" : level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill", Theme.cloudPrimary)
        case .charging: ("battery.100percent.bolt", Theme.leaf)
        case .lowBattery: ("battery.25percent", Theme.danger)
        case .trackChanged: ("music.note", Theme.leaf)
        case .shelfAdded: ("tray.and.arrow.down.fill", Theme.bolt)
        case .focusFinished: ("timer", TopBarStyle.violet)
        case .dictation: ("waveform", TopBarStyle.rec)
        case .usageAlert: ("gauge.with.dots.needle.67percent", Theme.ember)
        case .hint, .permission: ("lock.fill", Theme.ember)
        case .keepAwake: ("cup.and.saucer.fill", Theme.ember)
        case .brightness(let level): (level < 0.5 ? "sun.min.fill" : "sun.max.fill", Theme.cloudPrimary)
        case .keyboardBacklight: ("keyboard.fill", Theme.cloudPrimary)
        case .shortcut(let peek): (peek.symbol, Theme.cloudPrimary)
        case .rain: ("cloud.rain.fill", Theme.sky)
        case .decided: ("checkmark.circle.fill", Theme.bolt)
        case .screenshot: ("camera.fill", Theme.bolt)
        }
        Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
            .shadow(color: color.opacity(0.7), radius: 4)
    }

    @ViewBuilder
    private func cueDetail(_ cue: NotchCue) -> some View {
        switch cue {
        case .volume(let level, let muted):
            HUDSegmentBar(fraction: muted ? 0 : level, muted: muted).frame(width: 72)
        case .brightness(let level):
            HUDSegmentBar(fraction: level, muted: false).frame(width: 72)
        case .keyboardBacklight(let level):
            HUDSegmentBar(fraction: level, muted: false).frame(width: 72)
        case .shortcut(let peek):
            HStack(spacing: 6) {
                Text(peek.title).font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.cloudPrimary)
                Text(peek.key).font(TopBarStyle.label(11, .medium)).foregroundStyle(Theme.cloudSecondary)
            }.lineLimit(1)
        case .decided(let engine, let summary):
            HStack(spacing: 6) {
                Text(summary).font(TopBarStyle.label(11, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                EngineBadge(engine: engine)
            }.frame(width: 190, alignment: .trailing)
        case .rain(let minutes):
            Text("Rain in \(minutes) min").font(TopBarStyle.label(11, .semibold)).foregroundStyle(Theme.sky).lineLimit(1)
        case .capsLock(let on):
            Text(on ? "ON" : "OFF").font(TopBarStyle.label(10.5, .bold)).foregroundStyle(on ? Theme.bolt : Theme.cloudSecondary)
        case .charging(let level), .lowBattery(let level):
            Text("\(level)%").font(TopBarStyle.label(11, .semibold).monospacedDigit()).foregroundStyle(Theme.cloudPrimary)
        case .shelfAdded(let count):
            Text("+\(count)").font(TopBarStyle.label(11, .bold)).foregroundStyle(Theme.bolt)
        case .screenshot(let title):
            Text(title).font(TopBarStyle.label(11, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(1).frame(width: 190, alignment: .trailing)
        case .copied(let text), .dictation(let text), .focusFinished(let text), .usageAlert(let text), .hint(let text), .keepAwake(let text):
            Text(text).font(TopBarStyle.label(11, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(1).frame(width: 190, alignment: .trailing)
        case .permission(let text, let pane):
            HStack(spacing: 6) {
                Text(text).font(TopBarStyle.label(10.5, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                Button("Open") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.plain).font(TopBarStyle.label(10.5, .bold)).foregroundStyle(Theme.bolt)
                .accessibilityLabel("Open System Settings")
            }.frame(width: 250, alignment: .trailing)
        case .trackChanged(let title, let artist):
            Text(artist.isEmpty ? title : "\(title) · \(artist)").font(TopBarStyle.label(11, .medium)).foregroundStyle(Theme.cloudPrimary)
                .lineLimit(1).frame(width: 190, alignment: .trailing)
        }
    }
}

/// Scribe's own closed-notch wings, in the manner of a compact recording pill: a live scrolling waveform on the
/// left, and on the right the newest words as they are spoken (the clock until there are any). The whole right
/// wing opens Scribe, where the meeting is ended. No red: it is a calm "listening" cue, not a warning.
enum ScribeWings {
    struct Leading: View {
        let elapsed: TimeInterval
        /// The small capsule meter of the combined Recordly wings. Alone, the left wing is the scrolling waveform.
        var compact = false
        /// True where this meter is the only Scribe indicator (the combined Recordly wings): it then
        /// is its own accessibility element. Alone, the trailing ticker speaks for Scribe.
        var announces = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            if compact {
                // Reduce Motion: a steady set of bars.
                let meter = ScribeMeterView(
                    history: ScribeController.shared.levelHistory,
                    height: 12, barWidth: 2.5, spacing: 2.5, reduceMotion: reduceMotion
                )
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                if announces {
                    meter.accessibilityElement(children: .ignore)
                        .accessibilityLabel("Scribe is recording")
                        .accessibilityValue(RecordingMotion.spokenElapsed(elapsed) ?? "Elapsed time unavailable")
                } else {
                    meter.accessibilityHidden(true)
                }
            } else {
                Wave(history: ScribeController.shared.levelHistory, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// The last levels scroll right to left, newest next to the notch; silence is a row of small dots.
    /// Reduce Motion draws one steady set of bars.
    struct Wave: View {
        let history: [Double]
        var reduceMotion = false

        static let barCount = 12
        private static let steady: [Double] = [0.2, 0.35, 0.5, 0.7, 0.9, 0.7, 0.5, 0.8, 0.6, 0.4, 0.3, 0.2]

        var body: some View {
            let levels = reduceMotion ? Self.steady : ScribeLevelMeter.bars(history: history, count: Self.barCount)
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    let age = Double(index) / Double(max(levels.count - 1, 1))
                    if !reduceMotion && level < ScribeLevelMeter.silentBelow {
                        Circle().fill(Theme.leaf.opacity(0.3 + 0.4 * age)).frame(width: 2.5, height: 2.5)
                    } else {
                        Capsule().fill(Theme.leaf.opacity(0.4 + 0.6 * age))
                            .frame(width: 2.5, height: max(2.5, 3 + 13 * CGFloat(min(1, level))))
                    }
                }
            }
            .frame(height: 18)
            .animation(reduceMotion ? nil : .linear(duration: 0.06), value: levels)
            .accessibilityHidden(true)
        }
    }

    struct Trailing: View {
        let scribe: ScribeController
        let topBar: TopBarModel
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            // Ending is confirmed on the page, so this only brings the person there (capture continues).
            Button { topBar.onOpenTab(.scribe) } label: {
                ticker
            }
            .buttonStyle(PressableStyle())
            // The words are not read out as they stream in: VoiceOver gets the status, the page has the text.
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Scribe recording")
            .accessibilityValue(RecordingMotion.spokenElapsed(scribe.elapsed) ?? "Elapsed time unavailable")
            .accessibilityHint("Opens Scribe, where you can end the meeting.")
        }

        /// The clock for the words' pacing runs only while this wing is on screen (that is, while recording).
        @ViewBuilder
        private var ticker: some View {
            if reduceMotion {
                Ticker(scribe: scribe, date: Date(), reduceMotion: true)
            } else {
                TimelineView(.periodic(from: Date(), by: 1.0 / 20)) { context in
                    Ticker(scribe: scribe, date: context.date, reduceMotion: false)
                }
            }
        }
    }

    /// One line: a dot in the speaker's colour, the newest words with the older ones fading out on the left,
    /// and a small clock. Before any words, or when details are hidden, only status and the clock.
    struct Ticker: View {
        let scribe: ScribeController
        let date: Date
        let reduceMotion: Bool

        /// How many of the newest words are laid out (the rest could never be seen).
        private static let tailWords = 14

        var body: some View {
            let time = RecordlyElapsed.format(scribe.elapsed)
            if MeetingState.hideDetails {
                pill {
                    Circle().fill(Theme.leaf).frame(width: 6, height: 6)
                    Text("Recording").font(TopBarStyle.label(11, .medium)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                    clock(time)
                }
            } else if let segment = scribe.latestWordsSegment() {
                let shown = ScribeWordText.prefix(
                    segment.text,
                    words: scribe.visibleWordCount(for: segment, at: date, reduceMotion: reduceMotion)
                )
                let rgb = ScribeSpeakerPalette.color(for: segment.speaker)
                pill {
                    Circle().fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue)).frame(width: 6, height: 6)
                    Text(ScribeTickerText.tail(shown, words: Self.tailWords))
                        .font(TopBarStyle.label(11, .medium)).foregroundStyle(Theme.cloudPrimary)
                        .lineLimit(1).fixedSize()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .clipped()
                        .mask(LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.3),
                                .init(color: .black, location: 1),
                            ],
                            startPoint: .leading, endPoint: .trailing
                        ))
                    clock(time)
                }
            } else {
                pill {
                    Text(time)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .fixedSize()
                }
            }
        }

        private func clock(_ time: String) -> some View {
            Text(time)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.cloudSecondary)
                .fixedSize()
        }

        private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
            HStack(spacing: 6) { content() }
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
        }
    }
}

/// Superwhisper-style live waveform: the last levels scroll right to left, newest at the notch.
struct DictationWave: View {
    let levels: [Double]
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                let age = Double(index) / Double(max(levels.count - 1, 1))
                Capsule()
                    .fill(color.opacity(0.35 + 0.65 * age))
                    .frame(width: 2, height: max(2, min(16, 2 + level * 30)))
            }
        }
        .frame(height: 18)
        .animation(Motion.reduced ? nil : .linear(duration: 0.08), value: levels)
    }
}

/// A scroll view in the app, a plain clipped stack in `--snapshots` renders.
struct PageScroll<Content: View>: View {
    let axis: Axis.Set
    let content: Content

    init(_ axis: Axis.Set, @ViewBuilder content: () -> Content) {
        self.axis = axis
        self.content = content()
    }

    var body: some View {
        if TopBarStyle.isSnapshot {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
        } else {
            ScrollView(axis, showsIndicators: false) { content }
        }
    }
}

extension View {
    /// Applies interaction-only modifiers (drag and drop) everywhere except snapshot renders,
    /// where ImageRenderer would draw them as placeholders.
    @ViewBuilder
    func live<V: View>(_ transform: (Self) -> V) -> some View {
        if TopBarStyle.isSnapshot { self } else { transform(self) }
    }
}

/// The small engine tag on a decided command: which engine understood it.
struct EngineBadge: View {
    let engine: String
    var body: some View {
        Text(engine)
            .font(TopBarStyle.label(11, .bold))
            .foregroundStyle(engine == "Jev" ? Theme.accent : Theme.bolt)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().strokeBorder((engine == "Jev" ? Theme.accent : Theme.bolt).opacity(0.6), lineWidth: 1))
            .accessibilityLabel("Answered by \(engine)")
    }
}

/// Superwhisper in one click: start talking, click again (or press the talk key) to type it
/// into the app you were in. The notch never takes focus, so the text lands where your cursor was.
struct DictateButton: View {
    let topBar: TopBarModel

    var body: some View {
        let listening = topBar.dictationPhase == .listening
        let busy = topBar.isDictating && !listening
        // Click to latch (click again to stop and type), or hold to talk: a press of at least
        // DictateHold.threshold that started dictation stops it on release.
        HStack(spacing: 5) {
            Image(systemName: listening ? "stop.fill" : (busy ? "ellipsis" : "mic.fill"))
                .font(.system(size: 11.5, weight: .bold))
            Text(listening ? (DictateHold.shared.holding ? "Release" : "Stop") : (busy ? "Typing" : "Dictate"))
                .font(Glass.font(12, .semibold))
                .fixedSize()
        }
        .foregroundStyle(listening ? Color.white : Color.black)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(listening ? TopBarStyle.rec : Color.white))
        .shadow(color: (listening ? TopBarStyle.rec : Color.white).opacity(0.3), radius: 6)
        .scaleEffect(DictateHold.shared.pressedAt == nil ? 1 : 0.96)
        .contentShape(Capsule())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in DictateHold.shared.press(topBar) }
            .onEnded { _ in DictateHold.shared.release(topBar) })
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { topBar.toggleDictation() }
        .help(listening ? "Stop and type it" : "Dictate into the app you're in")
        .accessibilityLabel(listening ? "Stop dictation" : "Start dictation")
    }
}

/// Press state for DictateButton (an @Observable singleton: the SwiftUI @State macro is not
/// available to this toolchain). Pure timing logic so a hold and a click behave predictably.
@MainActor @Observable
final class DictateHold {
    static let shared = DictateHold()
    static let threshold: TimeInterval = 0.35
    private(set) var pressedAt: Date?
    private var startedHere = false
    private var holdTask: Task<Void, Never>?
    var holding = false

    func press(_ topBar: TopBarModel) {
        guard pressedAt == nil else { return }
        pressedAt = Date()
        startedHere = !topBar.isDictating
        if startedHere { topBar.toggleDictation() }
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.threshold))
            guard let self, !Task.isCancelled, self.pressedAt != nil, self.startedHere else { return }
            self.holding = true
        }
    }

    func release(_ topBar: TopBarModel) {
        guard let at = pressedAt else { return }
        holdTask?.cancel()
        pressedAt = nil
        holding = false
        let held = Date().timeIntervalSince(at) >= Self.threshold
        // Started by this press: a hold ends it now, a quick click leaves it latched.
        // Already dictating before the press: the click stops it.
        if startedHere ? held : true { topBar.toggleDictation() }
        startedHere = false
    }
}

// MARK: Tab editor

/// The notch row in edit mode: every tab in the row as a chip you drag to reorder, an x to take one out,
/// a + for the ones that are out, and Done. Lists `TopBarTab.allCases` generically, so a new tab needs nothing here.
struct TabEditorRow: View {
    let topBar: TopBarModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(topBar.layout.tabs) { tab in chip(tab) }
                addMenu
            }
            .padding(.horizontal, GlanceTopBar.capsuleInset.width + 2)
            .frame(height: GlanceTopBar.tabRowHeight)
            .background(Capsule().fill(GlanceTint.capsule))
            .overlay(Capsule().strokeBorder(GlanceTint.capsuleRim, lineWidth: 1))
            Text(topBar.tabEditorNote ?? "Drag to reorder. Tap \u{2715} to remove.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(topBar.tabEditorNote == nil ? Color.white.opacity(0.5) : Theme.ember)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Button { topBar.endTabEditing() } label: {
                Text("Done").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.black)
                    .padding(.horizontal, 16).frame(height: GlanceTopBar.moreSize)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Done editing tabs")
            .accessibilityIdentifier("notch.tabs.done")
        }
        .frame(height: GlanceTopBar.tabRowHeight)
    }

    private func chip(_ tab: TopBarTab) -> some View {
        let isHome = tab == .home
        return ZStack(alignment: .topTrailing) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(width: 30, height: 26)
                .background(Capsule().fill(topBar.draggedTab == tab ? Theme.glow.opacity(0.5) : GlanceTint.pill))
                .contentShape(Capsule())
            if !isHome {
                Button { withAnimation(TopBarStyle.pageSpring) { topBar.removeTab(tab) } } label: {
                    Image(systemName: "xmark").font(.system(size: 6.5, weight: .heavy)).foregroundStyle(Color.black)
                        .frame(width: 12, height: 12).background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -3)
                .accessibilityLabel("Remove \(tab.title)")
            }
        }
        .help(isHome ? "Home stays first" : "\(tab.title): drag to reorder")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.title)
        .accessibilityAction(named: "Move left") { if let index = topBar.layout.tabs.firstIndex(of: tab), index > 1 { topBar.moveTab(tab, onto: topBar.layout.tabs[index - 1]) } }
        .accessibilityAction(named: "Move right") { if let index = topBar.layout.tabs.firstIndex(of: tab), index + 1 < topBar.layout.tabs.count { topBar.moveTab(tab, onto: topBar.layout.tabs[index + 1]) } }
        .live { view in
            view.onDrag {
                topBar.draggedTab = tab
                return NSItemProvider(object: tab.rawValue as NSString)
            }
            .onDrop(of: [.text], delegate: TabDropDelegate(target: tab, topBar: topBar))
        }
    }

    private var addMenu: some View {
        Button {
            TabAddMenu.show(topBar: topBar)
        } label: {
            Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 30, height: 26)
                .background(Capsule().strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help("Add a tab")
        .accessibilityLabel("Add a tab")
        .opacity(topBar.layout.removedTabs.isEmpty ? 0.35 : 1)
    }
}

private struct TabDropDelegate: DropDelegate {
    let target: TopBarTab
    let topBar: TopBarModel

    func dropEntered(info: DropInfo) {
        guard let dragged = topBar.draggedTab, dragged != target else { return }
        withAnimation(TopBarStyle.pageSpring) { topBar.moveTab(dragged, onto: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        topBar.draggedTab = nil
        return true
    }
}

/// The + menu: every tab that is not in the row.
@MainActor
enum TabAddMenu {
    static func show(topBar: TopBarModel) {
        let menu = NSMenu(title: "Add a tab")
        for tab in topBar.layout.removedTabs {
            let item = NSMenuItem(title: tab.title, action: #selector(TabAddTarget.add(_:)), keyEquivalent: "")
            item.target = TabAddTarget.shared
            item.representedObject = tab.rawValue
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            let none = NSMenuItem(title: "Every tab is in the row", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        TabAddTarget.shared.topBar = topBar
        topBar.menuOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        topBar.menuOpen = false
    }
}

@MainActor
final class TabAddTarget: NSObject {
    static let shared = TabAddTarget()
    weak var topBar: TopBarModel?

    @objc func add(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let tab = TopBarTab(rawValue: raw) else { return }
        topBar?.addTab(tab)
    }
}
