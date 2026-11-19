import SwiftUI
import ZeusCore

/// The notch silhouette: concave "ears" that flare out of the bezel at the top (`shoulder`
/// wide, fading by `earHeight`), then continuous (squircle-like) bottom corners. ZEUS's own
/// drawing of the shape measured from Glance (TOPBAR-SPEC §2); every part animates.
struct NotchShape: Shape {
    var shoulder: CGFloat = 8
    var earHeight: CGFloat? = nil
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(shoulder, AnimatablePair(earHeight ?? shoulder, bottomRadius)) }
        set {
            shoulder = newValue.first
            earHeight = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(shoulder, rect.width / 4)
        let h = min(earHeight ?? s, rect.height / 2)
        let r = max(0, min(bottomRadius, (rect.height - h) / 2, (rect.width - 2 * s) / 2))
        // Plain circular corners, closed (6 pt) and open (22 pt): Glance's edges measured row by
        // row (parity/N1, N4) follow a circle, not a continuous curve.
        let start = r
        let handle = r * 0.5523
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s, y: rect.minY + h), control: CGPoint(x: rect.minX + s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - start))
        path.addCurve(to: CGPoint(x: rect.minX + s + start, y: rect.maxY),
                      control1: CGPoint(x: rect.minX + s, y: rect.maxY - start + handle),
                      control2: CGPoint(x: rect.minX + s + start - handle, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s - start, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX - s, y: rect.maxY - start),
                      control1: CGPoint(x: rect.maxX - s - start + handle, y: rect.maxY),
                      control2: CGPoint(x: rect.maxX - s, y: rect.maxY - start + handle))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + h))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - s, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

extension NotchModel.Status {
    var color: Color {
        switch self {
        case .idle: Theme.cloudQuiet
        case .working: Theme.accent
        case .needsYou: Theme.ember
        case .done: Theme.leaf
        case .failed: Theme.danger
        case .stalled: Theme.amber
        }
    }
}

extension Theme {
    /// Stalled agents: working, but silent for too long.
    static let amber = Color(hex: 0xFFB833)
}

extension ClosedWingsFacts {
    /// What the closed wings show right now. The extra width is read only while the body grows wings.
    @MainActor init(of topBar: TopBarModel) {
        self.init(kindIsNone: ClosedWings.kind(of: topBar) == .none, hasLights: !topBar.lights.isEmpty,
                  hasLiveActivity: topBar.hasLiveActivity, extraWidth: 0)
        if showsWings { extraWidth = ClosedWings.extraWidth(for: topBar) }
    }
}

struct NotchView: View {
    let model: NotchModel
    /// The top bar (tabs, pages, closed wings). Nil keeps the classic agents-only notch.
    var topBar: TopBarModel? = nil
    /// What this display reports about its top edge. The closed shape is resolved from it: the hardware notch,
    /// or where there is none the slim pill or the shape the owner drew.
    var facts: NotchDisplayFacts? = nil
    /// Snapshots and previews pin the closed shape and the guide, so they never read a store; nil asks the model.
    var footprintOverride: NotchFootprint? = nil
    var guideOverride: Bool? = nil
    /// Tests pass their own model; nil is the app's.
    var drawnNotch: DrawnNotchModel? = nil
    /// Snapshots and previews pin the drop; nil reads Settings > Appearance > Top bar position.
    var topOffsetOverride: Double? = nil
    /// Snapshots and previews pin the island background; nil reads Settings > Appearance > Island background.
    var backgroundOverride: NotchBackground? = nil
    /// What the notch's accessibility action does: open the panel. The closed notch is click-through and opens on
    /// the pointer, which a VoiceOver or Switch Control user does not have. Nil (previews, snapshots) does nothing.
    var openPanel: (() -> Void)? = nil

    /// The layers the body draws now: Transparent drops fill, outline and glow of the closed island only.
    private var layers: NotchBodyLayers {
        let background = backgroundOverride ?? NotchBackground.resolve(SettingsStore.shared.string(NotchBackground.settingID))
        return background.layers(closed: model.presentation == .closed)
    }

    /// The closed shape on this display.
    var footprint: NotchFootprint {
        if let footprintOverride { return footprintOverride }
        guard let facts else { return .pill }
        return (drawnNotch ?? .shared).footprint(for: facts)
    }

    /// A guide outline on the drawn notch while it is closed and being calibrated: a black shape on a dark menu
    /// bar cannot be seen otherwise.
    var showsGuide: Bool {
        guard model.presentation == .closed, case .drawn = footprint else { return false }
        return guideOverride ?? DrawnNotchCalibration.showsGuide((drawnNotch ?? .shared).state)
    }

    /// How far the closed bar and the peek card sit below the top of the screen. The open panel stays
    /// flush with the top; the notch light, ticker and wings are part of the closed bar and move with it.
    private var topOffset: CGFloat {
        let resolved = topOffsetOverride.map(TopBarPosition.clamped) ?? TopBarPositionModel.shared.offset
        return CGFloat(TopBarPosition.applied(resolved: resolved, panelOpen: model.presentation == .panel))
    }

    /// The hardware size (width 0 for the pill).
    private var notch: CGSize { footprint.layoutSize }
    private var slimPill: Bool { footprint.isPill }
    private var barHeight: CGFloat { max(notch.height, 30) }
    /// The closed body is taller than the bar on a hardware notch (it hangs below the notch). The peek, the open
    /// panel and the tab row keep `barHeight`.
    private var closedBodyHeight: CGFloat { NotchFootprintRules.closedHeight(footprint, wings: closedWings) }
    private var hasNotch: Bool { notch.width > 0 }

    /// Idle and closed, the top bar is exactly the hardware notch (square top, no ears); open it
    /// flares 27.5 pt ears like Glance. The classic notch keeps its small shoulders.
    private var idleClosed: Bool {
        guard let topBar, hasNotch, model.presentation == .closed else { return false }
        return ClosedWings.kind(of: topBar) == .none
    }
    /// A stalled session the peek is talking about (no card of its own to compete with).
    private var stalledPeek: NotchModel.Session? { Self.stalledPeek(model) }

    private static func stalledPeek(_ model: NotchModel) -> NotchModel.Session? {
        guard model.approval == nil, model.completion == nil, model.failure == nil,
              let session = model.peekSession, session.status == .stalled else { return nil }
        return session
    }

    /// Whether the peek draws a card under its bar. A bar-only peek takes the mouse like the closed notch.
    static func peekHasCard(model: NotchModel) -> Bool {
        model.approval != nil || model.completion != nil || model.failure != nil || stalledPeek(model) != nil
            || model.selectionEdit != nil || model.workBehind?.streaming == true || model.recap != nil
    }

    /// One diff row of the edit card and how many 15 pt text lines it takes.
    struct SelectionEditRow: Identifiable {
        var line: TextDiffLine
        var textLines: Int
        var id: Int { line.id }
        var height: CGFloat { 15 * CGFloat(textLines) }
    }

    /// The edit card body: the visible rows, how many were left out, and the whole height.
    struct SelectionEditLayout {
        var rows: [SelectionEditRow]
        var hidden: Int
        var height: CGFloat
        /// The plain line shown under a capped list, nil when every row is visible.
        var moreText: String? { hidden > 0 ? "+\(hidden) more lines" : nil }
    }

    /// Room for the edit card body (rows, the more-lines line and the Accept row): the notch window below the lowest
    /// bar position, the bar and the 10 pt gap. The card never grows past it, so Accept stays drawn and clickable.
    static func selectionEditBudget(barHeight: CGFloat) -> CGFloat {
        GlanceTopBar.windowHeight - CGFloat(TopBarPosition.maximum) - barHeight - 10
    }

    /// The edit card: each diff line takes up to two 15 pt lines (about 54 characters each), 4 pt apart, then the 28 pt
    /// Accept row. Rows that would not fit the budget are left out and counted in `hidden`, with a 15 pt line saying so.
    /// The view pins every row to `SelectionEditRow.height`, so what is drawn is what is measured here.
    static func selectionEditLayout(_ edit: SelectionEdit, barHeight: CGFloat) -> SelectionEditLayout {
        let budget = selectionEditBudget(barHeight: barHeight)
        let moreLine: CGFloat = 15 + 4
        var rows: [SelectionEditRow] = []
        var height: CGFloat = 28
        for (index, line) in edit.diff.enumerated() {
            let row = SelectionEditRow(line: line, textLines: min(2, max(1, (line.text.count + 2 + 53) / 54)))
            let reserve = index < edit.diff.count - 1 ? moreLine : 0
            if height + row.height + 4 + reserve > budget { break }
            rows.append(row)
            height += row.height + 4
        }
        let hidden = edit.diff.count - rows.count
        return SelectionEditLayout(rows: rows, hidden: hidden, height: height + (hidden > 0 ? moreLine : 0))
    }

    /// The peek card as drawn (the peek always has the 8 pt shoulders). The window's click-through rule reads it too.
    static func peekSize(model: NotchModel, footprint: NotchFootprint) -> CGSize {
        let notch = footprint.layoutSize
        let barHeight = max(notch.height, 30)
        let shoulder: CGFloat = 8
        if let approval = model.approval {
            let wide = (approval.detail?.height ?? 0) > 0
            // 6 pt more than before for the avatar header row of the shared card grammar.
            return CGSize(width: max(notch.width + 2 * shoulder + 240, wide ? 520 : 440), height: barHeight + 98 + approval.extraHeight)
        }
        if model.completion != nil {
            return CGSize(width: max(notch.width + 2 * shoulder + 240, 460), height: barHeight + 10 + CompletionCardView.height)
        }
        if model.failure != nil || stalledPeek(model) != nil {
            return CGSize(width: max(notch.width + 2 * shoulder + 240, 480), height: barHeight + 10 + AgentTroubleCard.height)
        }
        if let edit = model.selectionEdit {
            return CGSize(width: max(notch.width + 2 * shoulder + 240, 520), height: barHeight + 10 + selectionEditLayout(edit, barHeight: barHeight).height)
        }
        if let preview = model.workBehind, preview.streaming {
            return CGSize(width: max(notch.width + 2 * shoulder + 240, 440), height: barHeight + 10 + 24)
        }
        if let recap = model.recap {
            return CGSize(width: max(notch.width + 2 * shoulder + 240, 520), height: barHeight + 14 + WelcomeRecapCardView.height(for: recap))
        }
        return CGSize(width: (notch.width > 0 ? notch.width : 120) + 2 * shoulder + 230, height: barHeight)
    }

    private var shoulder: CGFloat {
        if !hasNotch, slimPill, model.presentation == .closed { return 0 }
        if topBar != nil, model.presentation == .panel { return GlanceTopBar.ear }
        return idleClosed ? 0 : 8
    }
    private var earHeight: CGFloat {
        topBar != nil && model.presentation == .panel ? GlanceTopBar.earHeight : shoulder
    }

    /// Width follows the presentation, height its own (faster on open) transaction.
    private var size: CGSize {
        CGSize(width: size(for: model.presentation).width, height: size(for: model.shownHeight).height)
    }

    /// How the closed notch grows into (and out of) its wings.
    @MainActor static var wingsSpring: Animation? { Motion.reducible(Motion.cueGrow) }

    private var closedWings: ClosedWingsFacts { topBar.map(ClosedWingsFacts.init(of:)) ?? .noWings }

    /// While closed (nil otherwise), what the closed width depends on besides the footprint: the trigger for
    /// `wingsSpring`. It never reads the footprint, so a footprint change moves the body without the spring.
    var closedWidthKey: ClosedWingsFacts.MotionKey? {
        model.presentation == .closed ? closedWings.motionKey : nil
    }

    /// The open panel's height, or nil while it is not open. A tab change (Home is 122 pt shorter than the other
    /// pages) or an approval changes it, so the height eases with the page spring instead of jumping.
    static func panelHeightKey(presentation: NotchModel.Presentation, panelHeight: CGFloat) -> CGFloat? {
        presentation == .panel ? panelHeight : nil
    }

    private var panelHeightKey: CGFloat? {
        Self.panelHeightKey(presentation: model.presentation, panelHeight: size(for: .panel).height)
    }

    private func size(for presentation: NotchModel.Presentation) -> CGSize {
        switch presentation {
        case .closed:
            let wings = closedWings
            if wings.showsWings {
                return CGSize(
                    width: NotchClosedBodyLayout.bodyWidth(
                        notchWidth: footprint.wingBase, shoulder: shoulder, showWings: true,
                        extraWidth: wings.extraWidth, hasNotch: hasNotch, slimPill: slimPill),
                    height: closedBodyHeight)
            }
            if hasNotch { return CGSize(width: notch.width + 2 * shoulder, height: closedBodyHeight) }
            return footprint.idleSize
        case .peek:
            return Self.peekSize(model: model, footprint: footprint)
        case .panel:
            if let topBar {
                return Self.topBarPanelSize(barHeight: barHeight, hasApproval: model.approval != nil, extra: model.approval?.extraHeight ?? 0,
                                            home: topBar.selectedTab == .home, homeStrip: topBar.homeExtraHeight)
            }
            let rows = CGFloat(max(model.sessions.count, 1))
            return CGSize(width: 540, height: barHeight + 20 + rows * 62 + (model.approval != nil ? 110 : 0) + 14)
        }
    }

    /// Glance's open panel: 870 x 210 on Home (taller pages get more room), plus the ears.
    static func topBarPanelSize(barHeight: CGFloat, hasApproval: Bool, extra: CGFloat = 0, home: Bool = false, homeStrip: CGFloat = 0) -> CGSize {
        GlanceTopBar.panelSize(home: home, extra: (hasApproval ? 126 + extra + 8 : 0) + (home ? homeStrip : 0))
    }

    /// The closed outline the lights follow: the black shape with wings, or the bare notch.
    private var closedLightBody: CGSize {
        let closed = size
        return closed.width > 0 ? closed : CGSize(width: notch.width + 2 * shoulder, height: closedBodyHeight)
    }

    private var bottomRadius: CGFloat {
        switch model.presentation {
        case .closed: !hasNotch && slimPill ? 4.5 : (idleClosed ? GlanceTopBar.closedBottomRadius : 10)
        case .peek: model.approval != nil ? 22 : 14
        case .panel: topBar != nil ? GlanceTopBar.bottomRadius : 32
        }
    }

    var body: some View {
        // Width and height interpolate in their own Animatable modifiers (Glance's height leads on
        // open, parity/N7), and the body reads the in-between size from the environment. The inner
        // modifier's animation wins for everything under it, so the height spring sits innermost.
        let open = model.presentation == .panel
        NotchSizeReader { animated in canvas(size: animated) }
            .modifier(AnimatedNotchHeight(height: size(for: model.shownHeight).height))
            .animation(open ? TopBarStyle.openHeightSpring : TopBarStyle.closeMotion, value: model.shownHeight)
            // Outside the open-height animation, which wins on open: this one only runs when the page or an approval
            // changes the open panel's height.
            .animation(TopBarStyle.pageSpring, value: panelHeightKey)
            .modifier(AnimatedNotchWidth(width: size(for: model.presentation).width))
            .animation(Self.wingsSpring, value: closedWidthKey)
            .animation(open ? TopBarStyle.openSpring : TopBarStyle.closeMotion, value: model.presentation)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, topOffset)
            // The drop changes with the presentation (the open panel is flush with the top), so it moves with
            // the same curve as the body. A separate easing made the bar slide on its own after every open
            // and close.
            .animation(Motion.reduced ? nil : (open ? TopBarStyle.openSpring : TopBarStyle.closeMotion), value: topOffset)
            .overlay(alignment: .top) {
                if !model.alerts.isEmpty, model.presentation == .closed {
                    AlertStackView(stack: model.alerts, settled: TopBarStyle.isSnapshot, actions: NotchControllerBridge.alertActions(),
                                   onHover: { NotchControllerBridge.alertHover($0) })
                        .padding(.top, closedBodyHeight + 6 + topOffset)
                        .transition(AlertStyle.transition(reduceMotion: Motion.reduced))
                }
            }
            .animation(Motion.reduced ? AlertStyle.crossfade(true) : AlertStyle.stretch, value: model.alerts.isEmpty)
            // The place of a drawn shape, applied last so the alerts move with the body. It moves the drawing and not
            // the layout, which is why it cannot sit under the alert overlay. It has no animation of its own.
            .offset(x: NotchAnchor.offset(footprint))
    }

    /// Whether the outline itself glows (and so breathes). With the top bar, the closed notch glows
    /// along its arms (NotchLights) instead, so a running agent must not tick this one.
    private func glowsOutline(status: NotchModel.Status) -> Bool {
        let halo = topBar?.haloStyle ?? .classic
        let pillGlow = slimPill && !hasNotch
        return halo != .off && status != .idle && !(model.presentation == .closed && !pillGlow && (!hasNotch || topBar != nil))
    }

    private func canvas(size: CGSize) -> some View {
        let status = model.status
        let halo = topBar?.haloStyle ?? .classic
        let drawn = layers
        let glowing = glowsOutline(status: status) && drawn.glow
        // Only tick while the halo is drawn and breathing, and only the outline layers (never the
        // content): an idle notch, or a closed one whose arms carry the glow, costs nothing.
        let breathing = !Motion.reduced && glowing
        let shape = NotchShape(shoulder: shoulder, earHeight: earHeight, bottomRadius: bottomRadius)
        let glanceOpen = topBar != nil && model.presentation == .panel
        return ZStack(alignment: .top) {
            DisplaySynchronizedView(paused: !breathing, preferredFramesPerSecond: Motion.ambientFPS) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let period = status == .needsYou ? 1.8 : 2.6
                // Reduce Motion: a steady glow instead of breathing.
                let breath = Motion.reduced ? 0.7 : 0.5 + 0.4 * (0.5 + 0.5 * sin(t * 2 * .pi / period))
                // Aurora drifts through hues; Storm adds a second, wider bolt-yellow bloom.
                let glow = halo == .aurora && !Motion.reduced
                    ? Color(hue: (t / 9).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 1)
                    : status.color
                ZStack(alignment: .top) {
                    shape
                        // Pitch black, closed and open, so the body reads as part of the hardware notch and
                        // only Zeus's own marks show on it. One fill type, so opening grows the body instead of
                        // cross-fading a new layer in.
                        .fill(Color.black)
                        // Transparent: the closed island has no body, only its marks (the hardware notch is black).
                        .opacity(drawn.fill ? 1 : 0)
                        // Glance's soft drop shadow under the open body (parity/N4: alpha 0.19 at 2 pt
                        // below, 0.10 at 15 pt, gone by 50 pt; weaker at the sides).
                        .shadow(color: .black.opacity(glanceOpen ? Glass.notchShadow.opacity : 0),
                                radius: Glass.notchShadow.radius, y: Glass.notchShadow.y)
                        .shadow(color: glow.opacity(glowing ? 0.28 * breath : 0), radius: 9)
                        .shadow(color: glow.opacity(glowing ? 0.2 * breath : 0), radius: 3)
                        .shadow(color: Theme.bolt.opacity(glowing && halo == .storm ? 0.3 * breath : 0), radius: 26)
                    shape.stroke(glow.opacity(glowing && drawn.outline ? 0.35 + 0.5 * breath : 0), lineWidth: 1.2)
                }
            }

            content
                .padding(.horizontal, glanceOpen ? shoulder : shoulder + (model.presentation == .panel ? 18 : 14))
                // Laid out at the final size and revealed by the growing outline, like Glance
                // (laying it out at the in-between size squeezed the cards and cut their text).
                .frame(width: self.size.width, height: self.size.height, alignment: .top)
                .frame(width: size.width, height: size.height, alignment: .top)
                // Nothing paints past the animated outline: the glow used to leak at the open
                // corners, and the page (inserted at its final layout) showed outside the body
                // while it grew.
                .clipShape(shape)

            if showsGuide {
                shape.stroke(Color.white.opacity(0.6), lineWidth: 1)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        // One labelled element for the whole notch (its children stay reachable), so a closed notch that draws only
        // marks still has a name and something to press.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zeus")
        .accessibilityAction { openPanel?() }
        // Offered only while there is a panel to open, so VoiceOver does not list a dead action on the open panel.
        .accessibilityActions {
            if model.presentation != .panel {
                Button("Open Zeus panel") { openPanel?() }
            }
        }
        .ownedJourneyControl("notch.body")
        // Glance (parity/N7, frames 139 to 143): the glass rim sits on the final open outline from
        // the first frame while the body grows inside it, then fades. Behind the body, not animated.
        .background(alignment: .top) {
            let open = topBar != nil && model.presentation == .panel
            GlassBloom(shoulder: GlanceTopBar.ear, earHeight: GlanceTopBar.earHeight, bottomRadius: GlanceTopBar.bottomRadius,
                       start: open ? model.openedAt : nil)
                .frame(width: self.size.width, height: self.size.height)
                .transaction { $0.animation = nil }
        }
        .overlay(alignment: .top) {
            if let topBar, model.presentation == .closed, layers.glow, hasNotch || slimPill || !topBar.lights.isEmpty {
                NotchLights(topBar: topBar, status: status, body_: closedLightBody, shoulder: shoulder)
            }
        }
        .onChange(of: model.status) { old, new in
            guard let topBar, old == .idle, new != .idle, topBar.haloStyle != .off else { return }
            let tint: NotchLightTint = switch new { case .needsYou, .failed: .ember; case .done: .leaf; case .stalled: .amber; default: .sky }
            let style = HaloEntrance.resolve(SettingsStore.shared.string("halo.entrance"))
            topBar.flash(.entrance(style, tint))
            topBar.flash(.edgeWave(tint))
        }
        .animation(Motion.live(MotionTokens.peekContent), value: model.approval?.id)
        .animation(Motion.live(MotionTokens.panelResize), value: model.sessions.count)
        .animation(Self.wingsSpring, value: topBar.map { ClosedWings.kind(of: $0) })
    }

    @ViewBuilder
    private var content: some View {
        switch model.presentation {
        case .closed:
            if let topBar {
                // Nothing drawn in the closed wings is pressed: a click on the notch only opens it.
                ClosedWings(topBar: topBar, notchGap: footprint.wingBase).frame(height: barHeight)
                    .allowsHitTesting(false)
                    // Transparent: no body behind the white wing text, so a soft shadow keeps it readable.
                    .shadow(color: .black.opacity(layers.fill ? 0 : 0.7), radius: 2, y: 0.5)
            }
        case .peek:
            VStack(spacing: 10) {
                peekBar
                if let approval = model.approval {
                    ApprovalBody(approval: approval, compact: true)
                        .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.12)))
                } else if let completion = model.completion {
                    CompletionCardView(completion: completion) { model.completion = nil }
                        .transition(.opacity.combined(with: .offset(y: -4)).animation(Motion.reducible(Motion.peekContent)))
                } else if let failure = model.failure {
                    AgentTroubleCard(kind: .failed, sessionID: failure.sessionID, agent: failure.agent, project: failure.project, reason: failure.reason) {
                        NotchControllerBridge.dismissFailure()
                    }
                    .transition(.opacity.combined(with: .offset(y: -4)).animation(Motion.reducible(Motion.peekContent)))
                } else if let session = stalledPeek {
                    AgentTroubleCard(kind: .stalled, sessionID: session.id, agent: session.agent, project: session.project,
                                     reason: session.reason ?? "No activity for a while") {
                        model.peekSessionID = nil
                        NotchControllerBridge.closePeek()
                    }
                    .transition(.opacity.combined(with: .offset(y: -4)).animation(Motion.reducible(Motion.peekContent)))
                } else if let edit = model.selectionEdit {
                    SelectionEditBody(layout: Self.selectionEditLayout(edit, barHeight: barHeight))
                        .padding(.horizontal, 16)
                } else if let preview = model.workBehind, preview.streaming {
                    WorkBehindBody(preview: preview)
                        .padding(.horizontal, 16)
                } else if let recap = model.recap {
                    WelcomeRecapCardView(recap: recap) { model.recap = nil; NotchControllerBridge.closePeek() }
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .offset(y: -4)).animation(Motion.reducible(Motion.peekContent)))
                }
            }
            .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.1)))
        case .panel:
            Group {
                if let topBar {
                    TopBarPanelBody(model: model, topBar: topBar, barHeight: barHeight, notchWidth: notch.width)
                } else {
                    PanelBody(model: model, barHeight: barHeight, notchWidth: notch.width)
                }
            }
            // Glance: tabs and cards fade in with the body, no slide or scale; on close they shrink
            // into the notch with the body (parity/N8-glance.mp4).
            .transition(.asymmetric(
                insertion: .opacity.animation(TopBarStyle.openSpring),
                removal: .opacity.combined(with: .scale(scale: 0.2, anchor: .top)).animation(TopBarStyle.closeMotion)))
        }
    }

    private var peekBar: some View {
        let status = model.status
        return HStack(spacing: 7) {
            HStack(spacing: 7) {
                BoltShape()
                    .fill(status.color)
                    .frame(width: 11, height: 13)
                    .shadow(color: status.color.opacity(0.9), radius: 4)
                Text(model.approval?.agent ?? model.peekSession?.agent ?? "Zeus")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cloudPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: hasNotch ? notch.width + 8 : 12, height: 1)
            HStack(spacing: 7) {
                if !peekStatusText.isEmpty {
                    Text(peekStatusText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                }
                if let session = model.peekSession, model.approval == nil, session.status == .working {
                    ElapsedText(since: session.startedAt)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: barHeight)
    }

    private var peekStatusText: String {
        switch model.status {
        case .needsYou: "Needs you"
        case .working: "Running"
        case .done: "Done"
        case .failed: "Failed"
        case .stalled: AgentCardKind.quiet.label
        case .idle: ""
        }
    }
}

private struct SelectionEditBody: View {
    let layout: NotchView.SelectionEditLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(layout.rows) { row in
                Text(prefix(row.line.kind) + row.line.text)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(color(row.line.kind))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: row.height, maxHeight: row.height, alignment: .topLeading)
            }
            if let more = layout.moreText {
                Text(more)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.cloudSecondary)
                    .frame(maxWidth: .infinity, minHeight: 15, maxHeight: 15, alignment: .topLeading)
            }
            HStack {
                Spacer()
                NotchButton(title: "Accept", tint: Theme.leaf, filled: true) { HandsHUD.shared.accept() }
            }
            .frame(height: 28)
        }
    }

    private func prefix(_ kind: TextDiffLine.Kind) -> String {
        switch kind {
        case .removed: "- "
        case .added: "+ "
        case .same: "  "
        }
    }

    private func color(_ kind: TextDiffLine.Kind) -> Color {
        switch kind {
        case .removed: Theme.danger
        case .added: Theme.leaf
        case .same: Theme.cloudPrimary
        }
    }
}

private struct WorkBehindBody: View {
    let preview: WorkBehindPreview

    var body: some View {
        Button(action: { HandsHUD.shared.openCoveredWindow() }) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.cloudSecondary, lineWidth: 1)
                    .frame(width: 36, height: 24)
                Text(preview.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.cloudPrimary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ElapsedText: View {
    let since: Date

    var body: some View {
        TickingView(interval: 1) { context in
            let seconds = max(Int(context.date.timeIntervalSince(since)), 0)
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.cloudQuiet)
        }
    }
}

private struct ApprovalBody: View {
    let approval: NotchModel.Approval
    let compact: Bool

    private var cardKind: AgentCardKind {
        if case .questions? = approval.detail?.kind { return .question }
        return .needsYou
    }

    /// Shared card grammar: avatar (in the peek), agent and project, the tool, danger flag, status chip.
    private var header: some View {
        let hidden = MeetingState.hideDetails
        return HStack(spacing: 6) {
            if compact {
                // The peek bar above already names the agent and says "Needs you"; the card shows each once.
                BotAvatarView.forAgent(approval.agent, state: cardKind.avatarState, size: 22)
                    .accessibilityLabel(approval.agent)
            }
            if !hidden {
                Text(approval.project)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(compact ? Theme.cloudQuiet : Theme.cloudSecondary)
                    .lineLimit(1)
                Text("·").foregroundStyle(Theme.cloudQuiet)
            }
            Text(approval.tool.uppercased())
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.cloudSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if approval.risk == .high {
                Label("DANGER", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundStyle(Theme.danger)
                    .background(Theme.danger.opacity(0.15), in: Capsule())
            }
            if !compact { AgentStatusChip(kind: cardKind) }
        }
        .frame(minHeight: compact ? 22 : 18)
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !approval.position.isEmpty {
                Text(approval.position)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.cloudSecondary)
                    .accessibilityLabel("Request \(approval.position)")
            }
            if MeetingState.hideDetails, approval.detail?.hasOwnActions == true {
                // The rich detail (questions, plans) is the content itself, so it stays out of view; Deny remains.
                HStack(spacing: 8) {
                    Text("Details hidden (Settings > Privacy). Answer in the terminal.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.cloudSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    NotchButton(title: "Deny", tint: Theme.cloudSecondary, filled: false) { approval.deny() }
                        .accessibilityHint("Stops \(approval.agent) from running this.")
                }
            } else if let detail = approval.detail, !MeetingState.hideDetails {
                // Never built while details are hidden: a diff's file name and source text are the content too.
                ApprovalDetailView(detail: detail, agent: approval.agent, resolve: approval.resolve)
            }
            if approval.detail?.hasOwnActions != true {
                let preview = NotchModel.Approval.isChangePreview(approval.command) && !MeetingState.hideDetails
                if preview {
                    Text(CommandDisplay.plain(approval.command))
                        .accessibilityLabel(approval.command)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.cloudPrimary)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                HStack(spacing: 8) {
                    if !preview {
                        Text(MeetingState.hideDetails ? "Details hidden (Settings > Privacy)" : CommandDisplay.plain(approval.command))
                            .accessibilityLabel(MeetingState.hideDetails ? "Details hidden" : approval.command)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.cloudPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    // Neither button is the default: approving shouldn't be one reflexive keypress.
                    NotchButton(title: "Deny", tint: Theme.cloudSecondary, filled: false) { approval.deny() }
                        .accessibilityHint("Stops \(approval.agent) from running this.")
                    ApprovalAllowButton(
                        title: approval.allowGate.confirmVisible ? "Confirm" : "Approve",
                        tint: Theme.ember,
                        fraction: approval.allowGate.holdFraction(now: ProcessInfo.processInfo.systemUptime)
                    ) {
                        approval.beginHold()
                    } release: { inside in
                        if case .hold = approval.allowGate.gesture { approval.endHold(inside) }
                        else { approval.activateAllow() }
                    } accessibility: {
                        approval.activateAllow()
                    }
                    NotchButton(title: "Deny all", tint: Theme.cloudSecondary, filled: false) { approval.denyAll() }
                        .accessibilityHint("Denies this request and every request waiting behind it. Nothing is allowed.")
                }
            }
            HStack(spacing: 6) {
                if let deadline = approval.deadline {
                    TickingView(interval: 1) { context in
                        let left = max(Int(deadline.timeIntervalSince(context.date).rounded(.up)), 0)
                        Text("\(left) s left, \(approval.timeoutNote)")
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 8)
                if let trust = approval.trustChat, approval.detail?.hasOwnActions != true {
                    Button(action: trust) {
                        Text("Allow this whole chat")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.cloudSecondary)
                            .underline()
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityHint("Approves this and later requests from \(approval.agent) in this chat, except risky commands, until Zeus quits.")
                }
            }
            .font(.system(size: 10.5, design: .rounded))
            .foregroundStyle(Theme.cloudQuiet)
        }
    }
}

/// Pointer presses begin and end a hold. A click, a key, or VoiceOver uses the plain activation,
/// which cannot finish a high-risk hold.
private struct ApprovalAllowButton: View {
    let title: String
    let tint: Color
    let fraction: Double
    let press: () -> Void
    let release: (Bool) -> Void
    let accessibility: () -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.storm)
            .padding(.horizontal, 14)
            .frame(minHeight: 28)
            .background {
                GeometryReader { proxy in
                    Capsule().fill(tint.opacity(0.35 + 0.65 * fraction))
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in press() }
                            .onEnded { value in
                                release(CGRect(origin: .zero, size: proxy.size).contains(value.location))
                            })
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title == "Confirm" ? "Confirm. Press again after a short wait." : title)
            .accessibilityAction { accessibility() }
    }
}

private struct NotchButton: View {
    let title: String
    let tint: Color
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(filled ? Theme.storm : tint)
                .padding(.horizontal, 14)
                .frame(minHeight: 28)
                .background(
                    Capsule().fill(filled ? tint : Color.white.opacity(0.12))
                )
                .shadow(color: filled ? tint.opacity(0.6) : .clear, radius: 6)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct PanelBody: View {
    let model: NotchModel
    let barHeight: CGFloat
    let notchWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                HStack(spacing: 7) {
                    BoltShape().fill(Theme.bolt).frame(width: 11, height: 13)
                        .shadow(color: Theme.bolt.opacity(0.8), radius: 4)
                    Text("Zeus")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.cloudPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: notchWidth + 8, height: 1)
                Text("\(model.sessions.count) agent\(model.sessions.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cloudSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: barHeight)

            if let approval = model.approval {
                ApprovalBody(approval: approval, compact: false)
                    .padding(12)
                    .background(Theme.ember.opacity(0.08), in: RoundedRectangle(cornerRadius: CardFinish.radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CardFinish.radius, style: .continuous).strokeBorder(Theme.ember.opacity(0.35)))
            }

            ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
                AgentCard(session: session, onStop: model.stopHandlers[session.id], picked: model.picker?.index == index)
            }
        }
        .padding(.bottom, 12)
    }
}

/// The open top bar: tab header split around the notch, any approval, then the selected page.
private struct TopBarPanelBody: View {
    let model: NotchModel
    let topBar: TopBarModel
    let barHeight: CGFloat
    let notchWidth: CGFloat

    /// Glance's layout (TOPBAR-SPEC §2-4): the notch row stays empty, the tab capsule sits at
    /// y 41 (24 in from the body), the page starts at y 82 (18 in), 14 above the bottom. Ambient
    /// glow is content-driven (music hue when playing, otherwise copper behind Calendar).
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Absolute black behind the content: no ambient glow (the owner's choice over the reference look).
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: GlanceTopBar.tabRowTop)
                TopBarHeader(topBar: topBar, agentCount: model.sessions.count, needsYou: model.status == .needsYou,
                             notchWidth: notchWidth, height: barHeight)
                    .padding(.leading, GlanceTopBar.tabRowInset)
                    .padding(.trailing, GlanceTopBar.rowTrailing)
                Color.clear.frame(height: GlanceTopBar.cardTop - GlanceTopBar.tabRowTop - GlanceTopBar.tabRowHeight)
                VStack(alignment: .leading, spacing: 8) {
                    if let approval = model.approval {
                        ApprovalBody(approval: approval, compact: false)
                            .padding(12)
                            .background(Theme.ember.opacity(0.08), in: RoundedRectangle(cornerRadius: CardFinish.radius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: CardFinish.radius, style: .continuous).strokeBorder(Theme.ember.opacity(0.35)))
                    }
                    TopBarPage(topBar: topBar, agentSummary: summary, agents: AnyView(agents))
                }
                .padding(.horizontal, GlanceTopBar.cardInset)
            }
        }
    }

    private var summary: String {
        let working = model.sessions.filter { $0.status == .working }.count
        if model.sessions.isEmpty { return "No agents running" }
        let count = "\(model.sessions.count) agent\(model.sessions.count == 1 ? "" : "s")"
        return working > 0 ? "\(count), \(working) working" : count
    }

    private var agents: some View {
        PageScroll(.vertical) {
            VStack(spacing: 8) {
                if model.sessions.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "bolt.horizontal.circle").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.cloudQuiet)
                        Text("No agents running. Start Claude Code and it shows up here.")
                            .font(.system(size: 11.5, design: .rounded)).foregroundStyle(Theme.cloudSecondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 34)
                }
                ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
                    AgentCard(session: session, onStop: model.stopHandlers[session.id], picked: model.picker?.index == index)
                }
                if model.picker != nil {
                    Text("Up and Down pick  ·  Return opens the terminal  ·  Esc closes")
                        .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.cloudQuiet)
                }
            }
        }
    }
}

private struct AgentCard: View {
    let session: NotchModel.Session
    var onStop: (@MainActor () -> Void)? = nil
    /// The keyboard picker's highlighted row.
    var picked = false

    /// Working sessions work, stalled ones nod off, everything else idles. The session model has no
    /// idle clock, so a stalled status stands in for "idle past the sleep threshold".
    private var avatarState: BotAvatarState {
        .forActivity(running: session.status == .working, idleFor: session.status == .stalled ? 600 : 0)
    }

    var body: some View {
        HStack(spacing: 10) {
            BotAvatarView(type: BotAvatarSpec.type(forAgent: session.agent), state: avatarState, size: 28,
                          seed: BotAvatarSpec.seed(forAgent: session.agent), interactive: true, agentName: session.agent)
            Circle()
                .fill(session.status.color)
                .frame(width: 8, height: 8)
                .shadow(color: session.status.color, radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.agent)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.cloudPrimary)
                    if !MeetingState.hideDetails {
                        Text(session.project)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.cloudQuiet)
                            .lineLimit(1)
                    }
                }
                if !MeetingState.hideDetails {
                    Text(session.task)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.cloudSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            // Running card: Wave (Glance's default) shows a live wave beside the timer.
            if session.status == .working, SettingsStore.shared.string("appearance.runningCard") != "Essentials" {
                LevelBars(count: 5, color: session.status.color, active: true, height: 16)
            }
            if session.status == .working {
                ElapsedText(since: session.startedAt)
            } else if let kind = AgentCardKind.kind(for: session.status) {
                AgentStatusChip(kind: kind)
            }
            if let onStop, session.status == .working || session.status == .needsYou {
                GlyphButton(symbol: "stop.fill", size: 11, tint: Theme.cloudSecondary, label: "Stop \(session.agent)") { onStop() }
            }
            JumpToTerminalButton(session: session.id, agent: session.agent)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .notchCard(CardFinish.current)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accent.opacity(picked ? 0.9 : 0), lineWidth: 2))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

// MARK: Animated size

private struct NotchWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private struct NotchHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }

private extension EnvironmentValues {
    var notchWidth: CGFloat {
        get { self[NotchWidthKey.self] }
        set { self[NotchWidthKey.self] = newValue }
    }
    var notchHeight: CGFloat {
        get { self[NotchHeightKey.self] }
        set { self[NotchHeightKey.self] = newValue }
    }
}

/// Interpolates the notch width on its own animation.
private struct AnimatedNotchWidth: ViewModifier, Animatable {
    var width: CGFloat
    nonisolated var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }
    func body(content: Content) -> some View { content.environment(\.notchWidth, width) }
}

/// Interpolates the notch height on its own animation.
private struct AnimatedNotchHeight: ViewModifier, Animatable {
    var height: CGFloat
    nonisolated var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }
    func body(content: Content) -> some View { content.environment(\.notchHeight, height) }
}

/// Hands the in-between notch size to the drawing.
private struct NotchSizeReader<Content: View>: View {
    @Environment(\.notchWidth) private var width
    @Environment(\.notchHeight) private var height
    let content: (CGSize) -> Content

    var body: some View { content(CGSize(width: width, height: height)) }
}

/// Dims on press so custom-drawn buttons still show feedback.
struct PressableStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let reduceMotionOverride: Bool?

    init(reduceMotion: Bool? = nil) { reduceMotionOverride = reduceMotion }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .modifier(MotionEffect(active: configuration.isPressed, enabled: isEnabled, presses: true, forced: reduceMotionOverride))
    }
}

/// Commands are shown character for character. A zero-width non-joiner between the two characters of a
/// pair like `--`, `->` or `!=` stops the font joining them into one glyph, so `--force` never reads as a dash followed by `force`.
/// Display only: the command that runs, and the VoiceOver label, are the original text.
enum CommandDisplay {
    static func plain(_ command: String) -> String {
        var text = command
        for pair in ["--", "->", "=>", "!=", "==", "<=", ">=", "&&", "||", "::"] {
            let characters = Array(pair)
            text = text.replacingOccurrences(of: pair, with: "\(characters[0])\u{200C}\(characters[1])")
        }
        return text
    }
}
