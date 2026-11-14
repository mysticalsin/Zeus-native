import SwiftUI
import ZeusCore

// The meeting card, drawn. A pure function of one `ScribeMeetingCard`, the two clock readings, the apps the call
// link opens in, the pointer flag and four closures (the pointer itself is reported by the hosting view).
// It stores no meeting, string or phase: every word comes from `ScribeMeetingCardText`, every state from the
// machine. The only motion is one entrance, one in-place crossfade, the countdown ring and the orb's breathing
// while it counts down.

/// What moves, planned from plain numbers so a test can read it against an injected clock.
enum ScribeMeetingCardMotion {
    /// The ring's one linear drain: the share it starts from and the seconds it takes to reach zero.
    struct Sweep: Equatable {
        var from: Double
        var duration: TimeInterval
    }

    /// A state change inside the card is the short crossfade, with or without Reduce Motion.
    static let crossfade = Animation.easeInOut(duration: AlertMotion.reducedFade)

    /// The sweep a ring starts when it appears. Nil with Reduce Motion, and once the deadline has passed.
    static func sweep(deadline: TimeInterval, uptime: TimeInterval, total: TimeInterval, reduceMotion: Bool) -> Sweep? {
        guard !reduceMotion else { return nil }
        let left = deadline - uptime
        guard left.isFinite, left > 0 else { return nil }
        return Sweep(from: ScribeMeetingCardText.ring(deadline: deadline, now: uptime, total: total), duration: left)
    }

    /// The share a redraw shows before any sweep runs: where the sweep starts, or, with Reduce Motion, the
    /// share left at this redraw (the ring steps down once a second instead of sweeping).
    static func drawn(deadline: TimeInterval, uptime: TimeInterval, total: TimeInterval, reduceMotion: Bool) -> Double {
        sweep(deadline: deadline, uptime: uptime, total: total, reduceMotion: reduceMotion)?.from
            ?? ScribeMeetingCardText.ring(deadline: deadline, now: uptime, total: total)
    }

    /// How the card arrives: the alert spring, a scale from 0.96 and a 6 pt downward drift, or only a short
    /// fade with Reduce Motion.
    static func entrance(reduceMotion: Bool) -> (animation: Animation, drop: CGFloat, scale: CGFloat) {
        reduceMotion ? (crossfade, 0, 1) : (AlertStyle.stretch, 6, 0.96)
    }

    /// The orb glow's breathing: two slow half cycles across the countdown, never a loop. Nil with Reduce Motion
    /// and once the countdown is over.
    struct Breath: Equatable {
        var halfCycle: TimeInterval
        var count: Int
    }

    static func breath(deadline: TimeInterval, uptime: TimeInterval, total: TimeInterval, reduceMotion: Bool) -> Breath? {
        guard !reduceMotion, total > 0, total.isFinite else { return nil }
        let left = deadline - uptime
        guard left.isFinite, left > 0 else { return nil }
        return Breath(halfCycle: min(left, total) / 2, count: 2)
    }

    /// The glow's resting level, and the two ends it breathes between.
    static let glowRest = 0.9
    static let glowLow = 0.55
    static let glowHigh = 1.0
}

struct ScribeMeetingCardView: View {
    let card: ScribeMeetingCard
    /// Wall clock, for "In N min".
    let now: Date
    /// The machine's uptime, for the countdown ring.
    let uptime: TimeInterval
    /// A rendered still has no appearance to wait for.
    var settled = false
    /// The installed apps the call link opens in, the first one the primary action uses. Empty without a link.
    var joinApps: [ScribeJoinApp] = []
    /// The pointer is over the card. The panel reports it; the close button appears with it.
    var hovered = false
    /// Replace the system settings, for a still or a test. Nil follows the system.
    var reduceMotion: Bool?
    var reduceTransparency: Bool?
    var locale: Locale = .current
    var timeZone: TimeZone = .current
    /// Each tap passes `card`, the one drawn here, so no one downstream keeps a copy of what is on screen.
    var onPrimary: (ScribeMeetingCard) -> Void = { _ in }
    var onCancel: (ScribeMeetingCard) -> Void = { _ in }
    var onDismiss: (ScribeMeetingCard) -> Void = { _ in }
    var onJoin: (ScribeMeetingCard, ScribeJoinApp) -> Void = { _, _ in }

    var body: some View {
        if card != .hidden { ScribeMeetingCardBody(spec: self) }
    }
}

private struct ScribeMeetingCardBody: View {
    typealias M = ScribeMeetingCardMetrics

    let spec: ScribeMeetingCardView
    private let still: Bool
    @State private var landed: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    init(spec: ScribeMeetingCardView) {
        self.spec = spec
        still = spec.settled
        _landed = State(initialValue: spec.settled)
    }

    private var card: ScribeMeetingCard { spec.card }
    private var reduceMotion: Bool { spec.reduceMotion ?? systemReduceMotion }
    private var surface: ScribeMeetingCardSurface {
        .resolve(reduceTransparency: spec.reduceTransparency ?? systemReduceTransparency)
    }
    private var canJoin: Bool { ScribeMeetingCardText.canJoin(card, apps: spec.joinApps) }

    var body: some View {
        let entrance = ScribeMeetingCardMotion.entrance(reduceMotion: reduceMotion)
        slab
            .padding(M.shadowRoom)
            .preferredColorScheme(.dark)
            // The entrance moves these three only: an animation on the whole card would replace the ring's own
            // linear sweep in the pass where both start.
            .animation(entrance.animation) {
                $0.opacity(landed ? 1 : 0).scaleEffect(landed ? 1 : entrance.scale).offset(y: landed ? 0 : -entrance.drop)
            }
            .onAppear { landed = true }
            .onChange(of: card.stateID, initial: true) {
                AccessibilityNotification.Announcement(ScribeMeetingCardText.announcement(card, now: spec.now)).post()
            }
    }

    // MARK: The slab

    private var slab: some View {
        HStack(spacing: 0) {
            leftColumn.frame(width: M.leftColumnWidth)
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: M.height - 2 * M.padding - 18)
                .accessibilityHidden(true)
            rightColumn
                .padding(.leading, 18)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, M.padding)
        .frame(width: M.width, height: M.height)
        .scribeCardGlass(surface, snapshot: TopBarStyle.isSnapshot)
        .overlay(alignment: .topTrailing) { close.padding(.top, 10).padding(.trailing, 12) }
    }

    // MARK: Left column

    private var leftColumn: some View {
        VStack(spacing: 10) {
            orb
            tiles
        }
        .frame(maxHeight: .infinity)
    }

    /// The glass orb with its calendar symbol; the countdown ring is a circle around it.
    private var orb: some View {
        ZStack {
            orbGlow
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x9378FF), Color(hex: 0x3D5BFF), Color(hex: 0x1F8CFF)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: M.orb, height: M.orb)
                .shadow(color: Color(hex: 0x4D7BFF).opacity(0.6), radius: 9)
                .overlay {
                    // A bright cap, like light on a glass sphere.
                    Ellipse()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: M.orb * 0.78, height: M.orb * 0.45)
                        .offset(y: -M.orb * 0.24)
                }
                .overlay {
                    Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.12)],
                                                         startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            Image(systemName: ScribeMeetingCardText.orbSymbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: Color(hex: 0x1B2A9A).opacity(0.5), radius: 3, y: 1)
            ring
        }
        .frame(width: M.ringDiameter, height: M.ringDiameter)
        .accessibilityHidden(true)
    }

    /// The glow breathes only while the card counts down; at every other time it rests.
    @ViewBuilder private var orbGlow: some View {
        if case .countdown(_, _, let deadline, let total) = card {
            ScribeMeetingCardGlow(breath: still ? nil : ScribeMeetingCardMotion.breath(
                deadline: deadline, uptime: spec.uptime, total: total, reduceMotion: reduceMotion))
                .id(deadline)
        } else {
            ScribeMeetingCardGlow(breath: nil)
        }
    }

    /// Only the countdown has a ring. Keyed on the deadline so the per-second redraw never restarts it.
    @ViewBuilder private var ring: some View {
        if case .countdown(_, _, let deadline, let total) = card {
            ScribeMeetingCardRing(deadline: deadline, uptime: spec.uptime, total: total, reduceMotion: reduceMotion,
                                  still: still)
                .id(deadline)
        }
    }

    /// One small tile per app the link opens in. The first is the one the primary action uses.
    private var tiles: some View {
        HStack(spacing: M.tileSpacing) {
            ForEach(Array(spec.joinApps.prefix(M.maxApps).enumerated()), id: \.element.bundleID) { index, app in
                ScribeMeetingCardTile(app: app, chosen: index == 0 && canJoin)
            }
        }
        .frame(height: M.tile)
        .accessibilityHidden(true)
    }

    // MARK: Right column

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            words
            Spacer(minLength: 6)
            capsule
        }
        .id(card.stateID)
        .transition(.opacity)
        .animation(ScribeMeetingCardMotion.crossfade, value: card.stateID)
    }

    /// One element for the words, "<title>, <status>"; the buttons stay elements of their own.
    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            pill
            if let meeting = card.meeting {
                Text(ScribeMeetingCardText.title(meeting))
                    .font(TopBarStyle.label(M.titleSize, .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 3)
                timeLine(meeting).padding(.top, 1)
                thirdLine(meeting).padding(.top, 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ScribeMeetingCardText.label(card, now: spec.now))
    }

    private var pill: some View {
        HStack(spacing: 6) {
            if case .starting = card {
                progress
            } else {
                Circle().fill(ScribeMeetingCardPalette.dot(ScribeMeetingCardText.tone(card))).frame(width: 6, height: 6)
            }
            Text(ScribeMeetingCardText.pill(card))
                .font(TopBarStyle.label(11.5, .semibold).monospacedDigit())
                .foregroundStyle(ScribeMeetingCardPalette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 20)
        .background(Capsule().fill(Color.white.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75))
    }

    private func timeLine(_ meeting: ScribeMeeting) -> some View {
        let line = ScribeMeetingCardText.timeLine(meeting, now: spec.now, locale: spec.locale, timeZone: spec.timeZone)
        return HStack(spacing: 7) {
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ScribeMeetingCardPalette.inkSecondary)
            if let range = line.range {
                Text(range)
                    .font(TopBarStyle.label(14, .medium).monospacedDigit())
                    .foregroundStyle(ScribeMeetingCardPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 14)
            }
            Text(line.relative)
                .font(TopBarStyle.label(14, .semibold).monospacedDigit())
                .foregroundStyle(ScribeMeetingCardPalette.violet)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .frame(height: 18)
    }

    /// A reason or a wait where the state has one, else the participants where the calendar gave any.
    @ViewBuilder private func thirdLine(_ meeting: ScribeMeeting) -> some View {
        let detail = ScribeMeetingCardText.detail(card)
        if let text = detail ?? ScribeMeetingCardText.participants(meeting) {
            HStack(spacing: 7) {
                Image(systemName: detail == nil ? "person.2.fill" : detailSymbol)
                    .font(.system(size: 12, weight: .medium))
                Text(text)
                    .font(TopBarStyle.label(13, .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(ScribeMeetingCardPalette.inkSecondary)
            .frame(height: 16)
        } else {
            Color.clear.frame(height: 16)
        }
    }

    private var detailSymbol: String {
        if case .waiting = card { return "hourglass" }
        return "exclamationmark.triangle.fill"
    }

    /// A small spinner, or three dots with Reduce Motion. The still render has no spinner to draw.
    @ViewBuilder private var progress: some View {
        if reduceMotion || TopBarStyle.isSnapshot {
            Image(systemName: "ellipsis").font(.system(size: 9, weight: .bold)).foregroundStyle(ScribeMeetingCardPalette.ink)
                .accessibilityHidden(true)
        } else {
            ProgressView().controlSize(.mini).accessibilityHidden(true)
        }
    }

    // MARK: Controls

    /// The one wide capsule for the state's primary action. Starting without Cancel and recording have none; the
    /// slot stays empty so the card does not change size.
    @ViewBuilder private var capsule: some View {
        if canJoin, let first = spec.joinApps.first {
            HStack(spacing: 0) {
                Button { spec.onJoin(card, first) } label: {
                    CapsuleLabel(symbol: ScribeMeetingCardText.symbol, title: ScribeMeetingCardText.join(first.name))
                }
                .buttonStyle(PressableStyle(reduceMotion: reduceMotion))
                .keyboardShortcut(.defaultAction)
                .ownedJourneyControl("scribe.meetingCard.primary")
                appsMenu
                Spacer(minLength: 0)
            }
            .modifier(CapsuleChrome(hovered: spec.hovered))
        } else if let title = ScribeMeetingCardText.primary(card) {
            Button { spec.onPrimary(card) } label: {
                CapsuleLabel(symbol: ScribeMeetingCardText.primarySymbol(card), title: title)
            }
            .buttonStyle(PressableStyle(reduceMotion: reduceMotion))
            .keyboardShortcut(.defaultAction)
            .ownedJourneyControl("scribe.meetingCard.primary")
            .modifier(CapsuleChrome(hovered: spec.hovered))
        } else if let title = ScribeMeetingCardText.cancel(card) {
            Button { spec.onCancel(card) } label: {
                CapsuleLabel(symbol: ScribeMeetingCardText.cancelSymbol, title: title)
            }
            .buttonStyle(PressableStyle(reduceMotion: reduceMotion))
            .keyboardShortcut(.cancelAction)
            .accessibilityValue(ScribeMeetingCardText.accessibilityValue(card) ?? "")
            .ownedJourneyControl("scribe.meetingCard.cancel")
            .modifier(CapsuleChrome(hovered: spec.hovered))
        } else {
            Color.clear.frame(height: M.capsuleHeight)
        }
    }

    /// The other matching apps, and last the offer's own action, so Join does not take Record away.
    @ViewBuilder private var appsMenu: some View {
        if TopBarStyle.isSnapshot {
            // A still cannot draw a menu control; it shows the chevron the menu hangs from.
            chevron
        } else {
            menu
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ScribeMeetingCardPalette.ink)
            .frame(width: 26, height: M.capsuleHeight)
    }

    private var menu: some View {
        Menu {
            ForEach(Array(spec.joinApps.dropFirst()), id: \.bundleID) { app in
                Button(ScribeMeetingCardText.join(app.name)) { spec.onJoin(card, app) }
            }
            if spec.joinApps.count > 1, ScribeMeetingCardText.primary(card) != nil { Divider() }
            if let title = ScribeMeetingCardText.primary(card) {
                Button(title) { spec.onPrimary(card) }
            }
        } label: {
            chevron.contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .ownedJourneyControl("scribe.meetingCard.apps")
    }

    /// The round close button. It appears with the pointer and is always there for VoiceOver and the keyboard.
    @ViewBuilder private var close: some View {
        if ScribeMeetingCardText.canDismiss(card) {
            Button { spec.onDismiss(card) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ScribeMeetingCardPalette.ink)
                    .frame(width: M.closeSize, height: M.closeSize)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.75))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(reduceMotion: reduceMotion))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(ScribeMeetingCardText.dismiss)
            .ownedJourneyControl("scribe.meetingCard.dismiss")
            .opacity(spec.hovered ? 1 : 0)
            .animation(ScribeMeetingCardMotion.crossfade, value: spec.hovered)
        }
    }
}

// MARK: Parts

/// The soft light behind the orb. At rest it holds one level; while counting down it breathes, slowly, over the
/// countdown, one finite animation and not a loop.
struct ScribeMeetingCardGlow: View {
    let breath: ScribeMeetingCardMotion.Breath?
    @State private var level: Double

    init(breath: ScribeMeetingCardMotion.Breath?) {
        self.breath = breath
        _level = State(initialValue: breath == nil ? ScribeMeetingCardMotion.glowRest : ScribeMeetingCardMotion.glowLow)
    }

    var body: some View {
        Circle()
            .fill(Color(hex: 0x4D7BFF))
            .frame(width: ScribeMeetingCardMetrics.orb + 8, height: ScribeMeetingCardMetrics.orb + 8)
            .blur(radius: 15)
            .opacity(level)
            .allowsHitTesting(false)
            .onAppear {
                guard let breath else { return }
                withAnimation(.easeInOut(duration: breath.halfCycle).repeatCount(breath.count, autoreverses: true)) {
                    level = ScribeMeetingCardMotion.glowHigh
                }
            }
    }
}

/// The thin ring that drains over the countdown. One linear animation, started with the time left.
struct ScribeMeetingCardRing: View {
    let deadline: TimeInterval
    let uptime: TimeInterval
    let total: TimeInterval
    let reduceMotion: Bool
    /// A rendered still shows the share as given and never starts the sweep.
    let still: Bool
    @State private var share: Double

    init(deadline: TimeInterval, uptime: TimeInterval, total: TimeInterval, reduceMotion: Bool, still: Bool) {
        self.still = still
        self.deadline = deadline
        self.uptime = uptime
        self.total = total
        self.reduceMotion = reduceMotion
        _share = State(initialValue: ScribeMeetingCardMotion.drawn(deadline: deadline, uptime: uptime, total: total,
                                                                   reduceMotion: reduceMotion))
    }

    var body: some View {
        let line = ScribeMeetingCardMetrics.ringWidth
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: line)
            Circle()
                .trim(from: 0, to: reduceMotion ? stepped : share)
                .stroke(Color.white, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(line / 2)
        .frame(width: ScribeMeetingCardMetrics.ringDiameter, height: ScribeMeetingCardMetrics.ringDiameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !still, let plan = ScribeMeetingCardMotion.sweep(deadline: deadline, uptime: uptime, total: total,
                                                                   reduceMotion: reduceMotion) else { return }
            withAnimation(.linear(duration: plan.duration)) { share = 0 }
        }
    }

    private var stepped: Double {
        ScribeMeetingCardMotion.drawn(deadline: deadline, uptime: uptime, total: total, reduceMotion: true)
    }
}

/// One app's own icon on a small rounded tile, or a neutral symbol when the icon cannot be read.
private struct ScribeMeetingCardTile: View {
    let app: ScribeJoinApp
    let chosen: Bool

    var body: some View {
        let side = ScribeMeetingCardMetrics.tile
        let shape = RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
        ZStack {
            shape.fill(Color.white.opacity(0.2))
            if let image = AppIconCache.shared.entry(for: app.bundleID).image {
                Image(nsImage: image).resizable().interpolation(.high).padding(1.5)
            } else {
                Image(systemName: AppBrandCatalog.glyph(for: app.bundleID) ?? "app.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ScribeMeetingCardPalette.ink)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(chosen ? 0.75 : 0.28), lineWidth: chosen ? 1.25 : 0.75))
    }
}

/// A symbol and a word on the capsule.
private struct CapsuleLabel: View {
    let symbol: String?
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            }
            Text(title)
                .font(TopBarStyle.label(13, .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(ScribeMeetingCardPalette.ink)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: ScribeMeetingCardMetrics.capsuleHeight)
        .contentShape(Rectangle())
    }
}

/// The wide translucent capsule behind the action. Brighter while the pointer is over the card.
private struct CapsuleChrome: ViewModifier {
    let hovered: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ScribeMeetingCardMetrics.capsuleHeight)
            .background(Capsule().fill(Color.white.opacity(hovered ? 0.2 : 0.13)))
            .overlay {
                Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.42), Color.white.opacity(0.1)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 0.9)
            }
    }
}

extension ScribeMeetingCard {
    /// Changes when the card becomes another state, not when its seconds or minutes tick.
    var stateID: String {
        switch self {
        case .hidden: return "hidden"
        case .offer(let meeting, let blocked): return "offer.\(meeting.key).\(String(describing: blocked))"
        case .countdown(let meeting, _, let deadline, _): return "countdown.\(meeting.key).\(deadline)"
        case .waiting(let meeting): return "waiting.\(meeting.key)"
        case .starting(let meeting, let cancellable): return "starting.\(meeting.key).\(cancellable)"
        case .recording(let meeting): return "recording.\(meeting.key)"
        case .failed(let meeting, let failure): return "failed.\(meeting.key).\(failure)"
        case .next(let meeting): return "next.\(meeting.key)"
        }
    }
}
