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
            if MeetingState.hideDetails, approval.detail?.hasOwnActions == true {
                // The rich detail (questions, plans) is the content itself, so it stays out of view; Deny remains.
                HStack(spacing: 8) {
                    Text("Details hidden (Settings > Privacy). Answer in the terminal.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.cloudSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    NotchButton(title: "Deny", tint: Theme.cloudSecondary, filled: false) { approval.resolve(.deny) }
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
                    NotchButton(title: "Deny", tint: Theme.cloudSecondary, filled: false) { approval.resolve(.deny) }
                        .accessibilityHint("Stops \(approval.agent) from running this.")
                    NotchButton(title: "Approve", tint: Theme.ember, filled: true) { approval.resolve(.allow) }
                        .accessibilityHint("Lets \(approval.agent) run this once.")
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
    @State private var agentsPage = AgentsPage.fresh()
    @State private var agentsReply = ""
    @State private var agentsNote = ""
    @State private var cardGate = AgentsPageCardGate()
    @FocusState private var agentsApprovalFocused: Bool

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
                    if let approval = model.approval, topBar.selectedTab != .agents {
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
        Group {
            if agentsPage.schedulesOneSecondTimer {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    agentsStack(now: context.date)
                        .onChange(of: context.date) { _, _ in adopt(AgentsPageHook.advance(agentsPage, ticks: 1)) }
                }
            } else {
                agentsStack(now: .now)
            }
        }
        .onAppear {
            syncAgents(now: .now)
            if let openedAt = model.openedAt {
                agentsPage.firstFrameMilliseconds = Int(Date().timeIntervalSince(openedAt) * 1000)
            }
        }
        .onChange(of: model.sessions) { _, _ in syncAgents(now: .now) }
        .onChange(of: model.approval?.id) { _, _ in syncAgents(now: .now) }
        .onChange(of: model.presentation) { _, _ in syncAgents(now: .now) }
    }

    private func agentsStack(now: Date) -> some View {
        let copy = HubScreenMachine.copy(agentsPage.screen)
        let selected = agentsPage.selectedID
        return PageScroll(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                if agentsPage.screen.screen != .ready || agentsPage.roster.isEmpty {
                    agentsNotice(copy)
                }
                if agentsPage.screen.screen == .ready || (agentsPage.screen.screen == .connectionError && !agentsPage.roster.isEmpty) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            SessionListView(
                                groups: agentListGroups(now: now),
                                selectedID: selected,
                                hidesDetails: MeetingState.hideDetails,
                                reduceMotionOverride: agentsPage.reduceMotion,
                                onToggleGroup: { agentsPage = agentsPage.applying(.toggleGroup($0)) },
                                onSelectRow: { agentsPage = agentsPage.applying(.select($0)) },
                                onOpenRow: { openAgent($0) }
                            )
                            if agentsPage.approvalGrown {
                                approvalRow
                                revisionActions
                            }
                            if agentsPage.undoTicksLeft > 0 {
                                NotchButton(title: "Undo", tint: Theme.cloudSecondary, filled: false) {
                                    adopt(AgentsPageHook.undo(agentsPage))
                                }
                                .accessibilityLabel("Undo")
                            }
                        }
                        .frame(width: selected == nil ? nil : 270, alignment: .leading)
                        if let selected {
                            agentDetail(selected)
                        }
                    }
                }
                if model.picker != nil {
                    Text("Up and Down pick  ·  Return opens the terminal  ·  Esc closes")
                        .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.cloudQuiet)
                }
            }
        }
    }

    private func agentsNotice(_ copy: HubScreenCopy) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.cloudQuiet)
            if let sentence = copy.sentence {
                Text(sentence)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cloudPrimary)
                    .multilineTextAlignment(.center)
            }
            if let detail = copy.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(Theme.cloudSecondary)
                    .multilineTextAlignment(.center)
            }
            if copy.actionTitle == "New chat" {
                NotchButton(title: "New chat", tint: Theme.cloudSecondary, filled: false) { openNewChat() }
                    .accessibilityLabel("New chat")
            }
            if agentsPage.showsTryAgain {
                NotchButton(title: "Try again", tint: Theme.cloudSecondary, filled: false) {
                    agentsPage = agentsPage.applying(.tryAgain)
                }
                .accessibilityLabel("Try again")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 34)
        .accessibilityElement(children: .contain)
    }

    private var revisionActions: some View {
        let tier = agentsPage.revision.showing?.tier
        let destructive = tier == .destructive
        return VStack(alignment: .leading, spacing: 6) {
            if let tier {
                Text(tier.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cloudSecondary)
                    .accessibilityLabel(tier.title)
            }
            if agentsPage.revision.decisionShowing {
                HStack(spacing: 8) {
                    if destructive {
                        revisionHold(HubDecisionAction.allowOnce)
                        revisionHold(HubDecisionAction.allowForThisSession)
                    } else {
                        NotchButton(title: HubDecisionAction.allowForThisSession.title, tint: Theme.cloudSecondary, filled: false) {
                            adopt(AgentsPageHook.press(agentsPage, .two))
                        }
                        .accessibilityLabel(HubDecisionAction.allowForThisSession.title)
                    }
                    NotchButton(title: HubDecisionAction.denyWithNote.title, tint: Theme.cloudSecondary, filled: false) {
                        adopt(AgentsPageHook.press(agentsPage, .four))
                    }
                    .accessibilityLabel(HubDecisionAction.denyWithNote.title)
                }
                TextField("Note", text: $agentsNote)
                    .font(.system(size: 12, design: .rounded))
                    .onChange(of: agentsNote) { _, text in
                        let limit = HubRevision3Timing.noteCharacterLimit
                        if text.count > limit {
                            agentsNote = String(text.prefix(limit))
                            return
                        }
                        agentsPage = agentsPage.applying(.note(text))
                    }
                    .accessibilityLabel("Deny with note")
            }
            if let pending = agentsPage.revision.pending {
                Text(HubRevision3Speech.pending(pending.action, deniesAllQueued: pending.deniesAllQueued))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.cloudSecondary)
            }
            if agentsPage.revision.waitingCount > 0 {
                Text(HubRevision3Speech.queue(agentsPage.revision.waitingCount))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.cloudQuiet)
                    .accessibilityLabel(HubRevision3Speech.queue(agentsPage.revision.waitingCount))
            }
        }
    }

    private func revisionHold(_ action: HubDecisionAction) -> some View {
        NotchButton(title: action.title, tint: Theme.cloudSecondary, filled: false) {}
            .onLongPressGesture(minimumDuration: Double(HubRevision3Timing.destructiveHoldMilliseconds) / 1_000) {
                adopt(AgentsPageHook.hold(
                    agentsPage, action: action, milliseconds: HubRevision3Timing.destructiveHoldMilliseconds))
            }
            .accessibilityLabel(action.title)
            .accessibilityHint("Press and hold")
    }

    private var approvalRow: some View {
        HubDecisionRow(
            request: decisionRequest,
            queue: HubDecisionQueue(thisRowIsQueued: false, count: agentsPage.queuedRequests.count),
            scope: .approval,
            reply: $agentsReply,
            answerKeysOn: SettingsStore.shared.bool("shortcut.answerKeys"),
            detailsHidden: MeetingState.hideDetails,
            reduceMotion: agentsPage.reduceMotion,
            onVerdict: resolveApproval
        )
        .focused($agentsApprovalFocused)
        .onHover { agentsPage = agentsPage.applying(.hover($0)) }
        .onChange(of: agentsApprovalFocused) { _, focused in agentsPage = agentsPage.applying(.focus(focused)) }
    }

    private var decisionRequest: HubDecisionRequest? {
        guard let request = agentsPage.showingRequest else { return nil }
        return HubDecisionRequest(
            tool: request.tool,
            highRisk: request.highRisk,
            command: request.command,
            secondsLeft: agentsPage.secondsLeft,
            allowsAsk: true
        )
    }

    private func agentDetail(_ id: String) -> some View {
        let session = agentsPage.roster.first { $0.id == id }
        let status = agentsPage.sessions[id]?.status
        let transcript = agentTranscript(id)
        return VStack(alignment: .leading, spacing: 8) {
            Text(session?.agent ?? "")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.cloudPrimary)
            if !MeetingState.hideDetails, let project = session?.project, !project.isEmpty {
                Text(project).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.cloudQuiet)
            }
            if let word = status?.visibleWord {
                Text(word).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.cloudSecondary)
            }
            if let command = agentsPage.showingRequest?.command, agentsPage.showingRequest?.sessionID == id {
                Text(command)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.cloudPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HubTranscriptView(lines: transcript.lines, status: transcript.status, prefersReducedMotion: agentsPage.reduceMotion)
            HStack(spacing: 8) {
                if let title = agentsPage.dismissTitle {
                    NotchButton(title: title, tint: Theme.cloudSecondary, filled: false) { dismissError() }
                        .accessibilityLabel(title)
                }
                if AgentTerminals.shared.canJump(to: id) {
                    NotchButton(title: "Open", tint: Theme.cloudSecondary, filled: false) { openAgent(id) }
                        .accessibilityLabel("Open")
                }
            }
            if agentsPage.selectedID != nil {
                HubDecisionRow(
                    request: nil,
                    queue: .none,
                    scope: .reply,
                    reply: $agentsReply,
                    answerKeysOn: false,
                    detailsHidden: MeetingState.hideDetails,
                    reduceMotion: agentsPage.reduceMotion,
                    onVerdict: { _ in },
                    onSend: {}
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func agentListGroups(now: Date) -> [SessionListGroup] {
        agentsPage.groups.groups.map { group in
            let rows = group.projects.flatMap(\.sessions).map { session in
                SessionListRow(
                    id: session.id,
                    name: session.agent,
                    project: session.project,
                    task: agentsPage.tasks[session.id] ?? agentsPage.reasons[session.id] ?? "",
                    status: session.status,
                    elapsedText: elapsedClock(liveElapsed(session, now: now)),
                    queuedApproval: agentsPage.queuedRequests.contains { $0.sessionID == session.id },
                    canOpen: AgentTerminals.shared.canJump(to: session.id)
                )
            }
            return SessionListGroup(id: group.agent, name: group.agent, expanded: group.status == .expanded, rows: rows)
        }
    }

    private func agentTranscript(_ id: String) -> (lines: [HubTranscriptLine], status: HubTranscriptStatus) {
        if let reason = agentsPage.reasons[id] {
            return ([HubTranscriptLine(id: "\(id).reason", role: .failed, text: reason)], .failed)
        }
        if agentsPage.sessions[id]?.clockPhase == .ticking {
            return ([], .streaming)
        }
        return ([], .idle)
    }

    private func elapsedClock(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        let clamped = max(0, seconds)
        return "\(clamped / 60):" + String(format: "%02d", clamped % 60)
    }

    private func openAgent(_ id: String) {
        agentsPage = agentsPage.applying(.open(id))
        guard agentsPage.jumpSessionID == id else { return }
        AgentTerminals.shared.jump(to: id)
    }

    private func openNewChat() {
        agentsPage = agentsPage.applying(.newChat(onChatTab: true))
        topBar.selectedTab = .chat
        AgentHub.shared.beginNewChat()
    }

    private func dismissError() {
        let id = agentsPage.selectedID
        agentsPage = agentsPage.applying(.dismiss)
        guard let id, let index = model.sessions.firstIndex(where: { $0.id == id }) else { return }
        model.sessions[index].status = .done
    }

    private func resolveApproval(_ verdict: HubApprovalVerdict) {
        switch verdict {
        case .allow:
            adopt(AgentsPageHook.tapAllow(agentsPage))
        case .deny:
            adopt(AgentsPageHook.tapDeny(agentsPage))
        case .ask:
            model.approval?.resolve(HookDecision.Verdict.ask)
        }
    }

    /// Hands a verdict to the hook only when the undo window has closed without an undo,
    /// and only while the card that opened that window is still the one on screen.
    private func adopt(_ step: AgentsPageHook.Step) {
        let (gate, sends) = cardGate.step(before: agentsPage, after: step.page, currentCard: model.approval?.id)
        cardGate = gate
        agentsPage = step.page
        for verdict in sends {
            deliver(verdict)
        }
    }

    private func deliver(_ verdict: AgentsPageHookVerdict) {
        switch verdict {
        case .allow: model.approval?.resolve(HookDecision.Verdict.allow)
        case .deny: model.approval?.resolve(HookDecision.Verdict.deny)
        case .ask: model.approval?.resolve(HookDecision.Verdict.ask)
        }
    }

    private func syncAgents(now: Date) {
        var page = agentsPage
        page.reduceMotion = Motion.reduced
        page.panelClosed = model.presentation != .panel
        page.oneSecondTimerScheduled = page.panelClosed ? false : page.schedulesOneSecondTimer
        page.waveDisplayLinkRunning = false
        let roster = model.sessions.map { session in
            HubGroupSession(
                id: session.id,
                agent: session.agent,
                project: session.project,
                status: hubStatus(session),
                elapsedSeconds: elapsedSeconds(session, now: now)
            )
        }
        for session in model.sessions {
            page.tasks[session.id] = session.task
            if session.status == .failed || session.status == .stalled {
                page.reasons[session.id] = session.reason ?? session.task
            }
        }
        page = page.applying(.sessionsReplaced(roster))
        if let approval = model.approval {
            let req = AgentsPageLive.request(
                approvalID: approval.id,
                sessionID: approval.sessionID,
                tool: approval.tool,
                highRisk: approval.risk == .high,
                command: approval.command.isEmpty ? nil : approval.command
            )
            let known = page.revision.showing?.id == req.boundID
                || page.revision.pending?.requestIDs.contains(req.boundID) == true
                || page.revision.waiting.contains { $0.id == req.boundID }
            if !known {
                page = page.applying(.approvalRequested(req))
            }
            if let deadline = approval.deadline, page.revision.pending == nil, page.revision.showing?.id == req.boundID {
                page.secondsLeft = max(0, Int(deadline.timeIntervalSinceNow.rounded(.down)))
            }
        }
        page.entry = .tab
        agentsPage = page
    }

    private func hubStatus(_ session: NotchModel.Session) -> HubSessionStatus {
        switch session.status {
        case .idle: return .loading
        case .working: return .running
        case .needsYou: return .waitingForInput
        case .done: return .done
        case .failed: return .error(.failed)
        case .stalled: return .error(.quiet)
        }
    }

    private func liveElapsed(_ session: HubGroupSession, now: Date) -> Int? {
        if let live = model.sessions.first(where: { $0.id == session.id }) {
            return elapsedSeconds(live, now: now)
        }
        return session.elapsedSeconds
    }

    private func elapsedSeconds(_ session: NotchModel.Session, now: Date) -> Int {
        let frozen = session.status == .done || session.status == .failed || session.status == .stalled
        let end = frozen ? session.lastEventAt : now
        return max(0, Int(end.timeIntervalSince(session.startedAt)))
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

// AGENTS-PAGE-MODEL-BEGIN

/// Where the Agents page was opened. The tab and Home show the same page.
enum AgentsPageEntry: String, Equatable, Sendable {
    case tab
    case home
}

/// What the Agents page is showing. Connection error stays distinct from empty.
enum AgentsPagePhase: String, Equatable, Sendable {
    case empty
    case connecting
    case connectionError
    case groups
    case selected
    case approval
    case error
}

/// One approval the page can show or queue. Tiers beyond the existing high-risk flag are not invented here.
struct AgentsPageRequest: Equatable, Sendable {
    /// Empty means the session id. A real request supplies its own id.
    var id: String = ""
    var sessionID: String
    var tool: String
    var highRisk: Bool
    var command: String?
    /// The revision 3 tier. High-risk maps to `.high`. Destructive is named only by that type.
    var tier: HubRiskTier = .low

    var boundID: String { id.isEmpty ? sessionID : id }
}

/// What the Agents page is told. A pair that is not handled leaves the page as it was.
enum AgentsPageSignal: Equatable, Sendable {
    case show(AgentsPageEntry)
    case socketOpening
    case socketOpened(sessionCount: Int, failureSentence: String?)
    case socketFailed(String?)
    case sessionArrived(HubGroupSession)
    case sessionsReplaced([HubGroupSession])
    case lastSessionEnded
    case tryAgain
    case select(String?)
    case toggleGroup(String)
    case approvalRequested(AgentsPageRequest)
    case approve
    case deny
    case dismiss
    case activity(String)
    case session(String, HubSessionEvent)
    case open(String)
    case hover(Bool)
    case focus(Bool)
    case tick
    case undo
    case panel(closed: Bool)
    case newChat(onChatTab: Bool)
    case key(HubDecisionKey, command: Bool)
    case note(String)
    case holdBegan(HubDecisionAction)
    case holdReleased(after: Int)
}

/// The Agents page: which screen is up, which row is selected, and whether an approval has grown.
/// The screen and session machines decide the transitions. This value does not open a window.
struct AgentsPage: Equatable, Sendable {
    var screen: HubScreenState
    var roster: [HubGroupSession]
    var sessions: [String: HubSessionState]
    var groups: HubGroupState
    var loadedGroups: Bool
    var selectedID: String?
    var entry: AgentsPageEntry
    var showingRequest: AgentsPageRequest?
    var queuedRequests: [AgentsPageRequest]
    var approvalGrown: Bool
    var cardAbovePage: Bool
    var openedWindow: Bool
    var jumpSessionID: String?
    var secondsLeft: Int
    var approvalHovered: Bool
    var approvalFocused: Bool
    var undoTicksLeft: Int
    var lastVerdict: HubApprovalVerdict?
    var panelClosed: Bool
    var oneSecondTimerScheduled: Bool
    var socketReadInProgress: Bool
    var waveDisplayLinkRunning: Bool
    var reduceMotion: Bool
    var reasons: [String: String]
    var tasks: [String: String]
    var firstFrameMilliseconds: Int?
    /// The revision 3 decision. Tiers, keys, the countdown, and undo live here.
    var revision: HubRevision3State
    var requestDetails: [String: AgentsPageRequest]
    /// Request id to session id. Written only after the duplicate check.
    var requestSessionIDs: [String: String]
    /// Spoken by the revision machine. Nil until a step keeps it.
    var announcement: String?

    static let countdownStart = 12
    static let undoSeconds = 2
    static let openBudgetMilliseconds = 100
    static let idleBudgetPercentOfOneCore = 1.0
    static let opensNewWindow = false
    static let usesCommandShortcut = false
    /// A deny note, in extended grapheme clusters. The limit is the revision 3 type.
    static let denyNoteLimit: Int? = HubRevision3Timing.noteCharacterLimit

    static func fresh() -> AgentsPage {
        AgentsPage(
            screen: HubScreenState(),
            roster: [],
            sessions: [:],
            groups: HubGroupState(),
            loadedGroups: false,
            selectedID: nil,
            entry: .tab,
            showingRequest: nil,
            queuedRequests: [],
            approvalGrown: false,
            cardAbovePage: false,
            openedWindow: false,
            jumpSessionID: nil,
            secondsLeft: 0,
            approvalHovered: false,
            approvalFocused: false,
            undoTicksLeft: 0,
            lastVerdict: nil,
            panelClosed: true,
            oneSecondTimerScheduled: false,
            socketReadInProgress: false,
            waveDisplayLinkRunning: false,
            reduceMotion: false,
            reasons: [:],
            tasks: [:],
            firstFrameMilliseconds: nil,
            revision: HubRevision3State(),
            requestDetails: [:],
            requestSessionIDs: [:],
            announcement: nil
        )
    }

    /// Press-and-hold belongs to the destructive tier. High is not that tier.
    static func holdSeconds(highRisk: Bool) -> Double? { nil }

    static func holdMilliseconds(tier: HubRiskTier) -> Int {
        tier == .destructive ? HubRevision3Timing.destructiveHoldMilliseconds : 0
    }

    /// The keys the existing focus events already name. Return and Escape are not approval keys.
    static func verdict(forKey event: HubFocusEvent) -> HubApprovalVerdict? {
        switch event {
        case .approveKey: return .allow
        case .denyKey: return .deny
        case .askKey: return .ask
        case .pageOpened, .activate, .up, .down, .return, .escape: return nil
        }
    }

    static func approvalOffset(reduceMotion: Bool) -> Double { reduceMotion ? 0 : 8 }

    static func approvalScale(reduceMotion: Bool) -> Double { reduceMotion ? 1 : 0.985 }

    func applying(_ signal: AgentsPageSignal) -> AgentsPage {
        switch signal {
        case .show(let entry):
            guard self.entry != entry else { return self }
            var next = self
            next.entry = entry
            return next
        case .socketOpening:
            return stepScreen(.socketOpening, count: roster.count, sentence: nil, onChatTab: false)
        case .socketOpened(let count, let sentence):
            let event: HubScreenEvent
            if screen.screen == .connectionError {
                event = .socketOpened
            } else if count == 0 {
                event = .socketOpenedNoSessions
            } else if screen.screen == .loading {
                event = .atLeastOneSession
            } else if screen.screen == .empty {
                event = .sessionArrived
            } else {
                return self
            }
            return stepScreen(event, count: count, sentence: sentence, onChatTab: false)
        case .socketFailed(let sentence):
            return stepScreen(.socketFailed, count: roster.count, sentence: sentence, onChatTab: false)
        case .sessionArrived(let session):
            var rows = roster
            if let index = rows.firstIndex(where: { $0.id == session.id }) {
                rows[index] = session
            } else {
                rows.append(session)
            }
            return replaceRoster(rows)
        case .sessionsReplaced(let rows):
            return replaceRoster(rows)
        case .lastSessionEnded:
            return endLastSession()
        case .tryAgain:
            return stepScreen(.tryAgain, count: roster.count, sentence: nil, onChatTab: false)
        case .select(let id):
            return select(id)
        case .toggleGroup(let name):
            let nextGroups = HubGroupMachine.next(groups, .activateHeader, header: name)
            guard nextGroups != groups else { return self }
            var next = self
            next.groups = nextGroups
            return next
        case .approvalRequested(let request):
            return requestApproval(request)
        case .approve:
            return applyRevision(.key(.return, command: false))
        case .deny:
            return applyRevision(.key(.escape, command: false))
        case .dismiss:
            return dismissSelected()
        case .activity(let id):
            return stepSession(id, .activity, clearReasonOnRunning: true)
        case .session(let id, let event):
            return stepSession(id, event, clearReasonOnRunning: event == .activity || event == .promptStarted)
        case .open(let id):
            guard roster.contains(where: { $0.id == id }) else { return self }
            var next = self
            next.jumpSessionID = id
            next.openedWindow = false
            return next
        case .hover(let hovering):
            return applyRevision(.pause(.hover, active: hovering))
        case .focus(let focused):
            return applyRevision(.pause(.focus, active: focused))
        case .tick:
            guard revision.showing != nil || revision.pending != nil || revision.holdBeganAt != nil else { return self }
            return applyRevision(.advance(to: revision.clock + 1_000))
        case .undo:
            return applyRevision(.key(.undo, command: false))
        case .key(let key, let command):
            return applyRevision(.key(key, command: command))
        case .note(let text):
            return applyRevision(.replaceNote(text))
        case .holdBegan(let action):
            return applyRevision(.holdBegan(action, at: revision.clock))
        case .holdReleased(let after):
            let began = revision.holdBeganAt ?? revision.clock
            return applyRevision(.holdReleased(at: began + after))
        case .panel(let closed):
            return setPanel(closed: closed)
        case .newChat(let onChatTab):
            return stepScreen(.newChat, count: roster.count, sentence: screen.reason, onChatTab: onChatTab)
        }
    }

    func meetsOpenBudget(_ milliseconds: Int) -> Bool {
        milliseconds >= 0 && milliseconds <= Self.openBudgetMilliseconds
    }

    func isIdle(percentOfOneCore: Double) -> Bool {
        guard panelClosed, showingRequest == nil, !socketReadInProgress, !oneSecondTimerScheduled, !waveDisplayLinkRunning else {
            return false
        }
        guard percentOfOneCore.isFinite, percentOfOneCore >= 0, percentOfOneCore <= Self.idleBudgetPercentOfOneCore else {
            return false
        }
        return true
    }

    private func stepScreen(_ event: HubScreenEvent, count: Int, sentence: String?, onChatTab: Bool) -> AgentsPage {
        let context = HubScreenContext(sessionCount: count, onChatTab: onChatTab, failureSentence: sentence)
        let nextScreen = HubScreenMachine.next(screen, event, context: context)
        guard nextScreen != screen else { return self }
        var next = self
        next.screen = nextScreen
        next.openedWindow = false
        return next
    }

    private func endLastSession() -> AgentsPage {
        let nextScreen = HubScreenMachine.next(screen, .lastSessionEnded, context: HubScreenContext(sessionCount: roster.count))
        guard nextScreen != screen else { return self }
        var next = self
        next.screen = nextScreen
        next.openedWindow = false
        guard nextScreen.screen == .empty else { return next }
        next.roster = []
        next.sessions = [:]
        next.groups = HubGroupState()
        next.loadedGroups = false
        next.selectedID = nil
        next.showingRequest = nil
        next.queuedRequests = []
        next.approvalGrown = false
        next.secondsLeft = 0
        next.approvalHovered = false
        next.approvalFocused = false
        next.revision = HubRevision3State()
        next.requestDetails = [:]
        next.requestSessionIDs = [:]
        return next
    }

    private func select(_ id: String?) -> AgentsPage {
        guard screen.screen == .ready || screen.screen == .connectionError else { return self }
        if let id, !roster.contains(where: { $0.id == id }) { return self }
        guard selectedID != id else { return self }
        var next = self
        next.selectedID = id
        return next
    }

    private func requestApproval(_ request: AgentsPageRequest) -> AgentsPage {
        guard let state = sessions[request.sessionID] else { return self }
        let requestID = request.boundID
        if revision.showing?.id == requestID || revision.waiting.contains(where: { $0.id == requestID }) {
            return self
        }
        if revision.showing == nil, revision.pending == nil, revision.waiting.isEmpty {
            guard HubSessionMachine.next(state, .approvalRequested).status == .needsApproval else { return self }
        }
        let tier = request.tier == .low && request.highRisk ? HubRiskTier.high : request.tier
        var stored = request
        stored.id = requestID
        stored.tier = tier
        stored.highRisk = tier == .high || tier == .destructive
        var next = self
        next.requestDetails[requestID] = stored
        next.requestSessionIDs[requestID] = request.sessionID
        let wasShowing = revision.showing?.id
        next = next.applyRevision(.request(HubRevision3Request(id: requestID, sessionID: request.sessionID, tier: tier)))
        guard next.revision.showing?.id == requestID, wasShowing != requestID else { return next }
        guard let state = next.sessions[request.sessionID] else { return next }
        let stepped = HubSessionMachine.next(state, .approvalRequested)
        guard stepped.status == .needsApproval else { return next }
        next.sessions[request.sessionID] = stepped
        if next.selectedID == nil { next.selectedID = request.sessionID }
        next.syncRoster()
        next.restoreDetails()
        return next
    }

    private func applyRevision(_ event: HubRevision3Event) -> AgentsPage {
        let before = revision.executed.count
        let outcome = HubRevision3Decision.step(revision, event)
        guard outcome.state != revision else { return self }
        var next = self
        next.revision = outcome.state
        next.applyExecutions(since: before)
        next.mirrorRevision()
        next.restoreDetails()
        next.openedWindow = false
        next.cardAbovePage = false
        return next
    }

    private mutating func applyExecutions(since previousCount: Int) {
        guard revision.executed.count > previousCount else { return }
        for execution in revision.executed.dropFirst(previousCount) {
            let event: HubSessionEvent = execution.action.isApproval ? .approved : (execution.fromCountdown ? .timedOut : .denied)
            for id in execution.requestIDs {
                let sessionID = requestSessionIDs[id] ?? id
                if let state = sessions[sessionID] {
                    sessions[sessionID] = HubSessionMachine.next(state, event)
                }
            }
            lastVerdict = execution.action.isApproval ? .allow : .deny
        }
        if let showing = revision.showing?.sessionID, sessions[showing]?.status != .needsApproval, let state = sessions[showing] {
            let stepped = HubSessionMachine.next(state, .approvalRequested)
            if stepped.status == .needsApproval { sessions[showing] = stepped }
        }
        syncRoster()
    }

    private mutating func mirrorRevision() {
        approvalGrown = revision.showing != nil || revision.pending != nil
        secondsLeft = revision.remainingMilliseconds / 1_000
        approvalHovered = revision.pauses.contains(.hover)
        approvalFocused = revision.pauses.contains(.focus) || revision.pauses.contains(.voiceOverFocus)
        if let pending = revision.pending {
            undoTicksLeft = max(0, (pending.undoUntil - revision.clock) / 1_000)
        } else {
            undoTicksLeft = 0
        }
    }

    private mutating func restoreDetails() {
        if let showing = revision.showing {
            var detail = requestDetails[showing.id] ?? AgentsPageRequest(
                sessionID: showing.sessionID, tool: "", highRisk: showing.tier != .low, command: nil, tier: showing.tier)
            detail.id = showing.id
            detail.sessionID = showing.sessionID
            detail.tier = showing.tier
            detail.highRisk = showing.tier == .high || showing.tier == .destructive
            showingRequest = detail
        } else if revision.pending == nil {
            showingRequest = nil
        }
        queuedRequests = revision.waiting.map { waiting in
            var detail = requestDetails[waiting.id] ?? AgentsPageRequest(
                sessionID: waiting.sessionID, tool: "", highRisk: waiting.tier != .low, command: nil, tier: waiting.tier)
            detail.id = waiting.id
            detail.sessionID = waiting.sessionID
            detail.tier = waiting.tier
            detail.highRisk = waiting.tier == .high || waiting.tier == .destructive
            return detail
        }
    }

    private func dismissSelected() -> AgentsPage {
        guard let id = selectedID, sessions[id]?.status == .error(.failed), let state = sessions[id] else { return self }
        var next = self
        next.sessions[id] = HubSessionMachine.next(state, .dismissed)
        next.openedWindow = false
        next.syncRoster()
        return next
    }

    private func stepSession(_ id: String, _ event: HubSessionEvent, clearReasonOnRunning: Bool) -> AgentsPage {
        guard let state = sessions[id] else { return self }
        let stepped = HubSessionMachine.next(state, event)
        guard stepped != state else { return self }
        var next = self
        next.sessions[id] = stepped
        if clearReasonOnRunning, stepped.status == .running { next.reasons[id] = nil }
        if stepped.status == .absent {
            next.roster.removeAll { $0.id == id }
            if next.selectedID == id { next.selectedID = nil }
        }
        next.syncRoster()
        return next
    }

    private func setPanel(closed: Bool) -> AgentsPage {
        var next = self
        next.panelClosed = closed
        if closed {
            next.oneSecondTimerScheduled = false
            next.waveDisplayLinkRunning = false
        } else {
            next.oneSecondTimerScheduled = next.schedulesOneSecondTimer
        }
        return next == self ? self : next
    }

    private func replaceRoster(_ rows: [HubGroupSession]) -> AgentsPage {
        var next = self
        let visible = rows.filter { $0.status != .absent }
        let ids = Set(visible.map(\.id))
        var kept: [String: HubSessionState] = [:]
        for row in visible {
            if var existing = sessions[row.id] {
                let keepApproval = showingRequest?.sessionID == row.id && existing.status == .needsApproval
                if !keepApproval, existing.status != row.status {
                    existing.status = row.status
                }
                kept[row.id] = existing
            } else {
                let generation = row.status.clockPhase == .notStarted || row.status.clockPhase == nil ? 0 : 1
                kept[row.id] = HubSessionState(status: row.status, clockGeneration: generation)
            }
        }
        for id in sessions.keys where !ids.contains(id) {
            next.reasons[id] = nil
            next.tasks[id] = nil
        }
        next.sessions = kept
        next.roster = visible.map { row in
            var copy = row
            if let status = kept[row.id]?.status { copy.status = status }
            return copy
        }
        if let selectedID, !ids.contains(selectedID) { next.selectedID = nil }
        if let showing = next.showingRequest, !ids.contains(showing.sessionID) {
            next.showingRequest = nil
            next.approvalGrown = false
            next.secondsLeft = 0
        }
        next.queuedRequests.removeAll { !ids.contains($0.sessionID) }
        next.reconcileScreen()
        next.syncRoster()
        next.openedWindow = false
        return next == self ? self : next
    }

    private mutating func reconcileScreen() {
        guard screen.screen != .connectionError else { return }
        let count = roster.count
        if roster.isEmpty, screen.screen == .ready {
            screen = HubScreenMachine.next(screen, .lastSessionEnded, context: HubScreenContext(sessionCount: 0))
        } else if !roster.isEmpty, screen.screen == .empty {
            screen = HubScreenMachine.next(screen, .sessionArrived, context: HubScreenContext(sessionCount: count))
        } else if !roster.isEmpty, screen.screen == .loading {
            screen = HubScreenMachine.next(screen, .atLeastOneSession, context: HubScreenContext(sessionCount: count))
        }
    }

    private mutating func syncRoster() {
        roster = roster.compactMap { row in
            guard let status = sessions[row.id]?.status, status != .absent else { return nil }
            var copy = row
            copy.status = status
            return copy
        }
        if roster.isEmpty {
            groups = HubGroupState()
            loadedGroups = false
            return
        }
        if !loadedGroups {
            groups = HubGroupMachine.next(HubGroupState(), .firstLoad, sessions: roster)
            loadedGroups = true
        } else {
            groups = HubGroupMachine.next(groups, .sessionsChanged, sessions: roster)
        }
    }

    var copy: HubScreenCopy { HubScreenMachine.copy(screen) }

    var countdownPaused: Bool { approvalHovered || approvalFocused }

    var phase: AgentsPagePhase {
        switch screen.screen {
        case .empty: return .empty
        case .loading: return .connecting
        case .connectionError: return .connectionError
        case .ready:
            if approvalGrown, showingRequest != nil { return .approval }
            if let id = selectedID, let status = sessions[id]?.status, status.isError { return .error }
            if selectedID != nil { return .selected }
            return .groups
        }
    }

    var dismissTitle: String? {
        guard screen.screen == .ready, let id = selectedID, sessions[id]?.status == .error(.failed) else { return nil }
        return "Dismiss"
    }

    var showsTryAgain: Bool { screen.screen == .connectionError && copy.actionTitle == "Try again" }

    var focusOrder: [HubFocusTarget] {
        if approvalGrown, selectedID != nil { return HubFocusTarget.selectedApprovalOrder }
        if selectedID != nil { return HubFocusTarget.screenOrder }
        return [.groupHeader, .row]
    }

    var schedulesOneSecondTimer: Bool {
        guard !panelClosed else { return false }
        if showingRequest != nil, secondsLeft > 0 { return true }
        if undoTicksLeft > 0 { return true }
        return roster.contains { sessions[$0.id]?.clockPhase == .ticking }
    }
}

private extension HubSessionStatus {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

/// What the page tells the hook. The stub still sends Allow on the tap. The window is not consulted.
enum AgentsPageHookVerdict: String, Equatable, Sendable {
    case allow, deny, ask
}

enum AgentsPageHook {
    struct Step: Equatable, Sendable {
        var page: AgentsPage
        var sends: [AgentsPageHookVerdict]
    }

    static func tapAllow(_ page: AgentsPage) -> Step {
        if page.revision.showing?.tier == .destructive {
            return Step(page: page, sends: [])
        }
        return stepped(page, page.applying(.approve))
    }

    static func tapDeny(_ page: AgentsPage) -> Step {
        stepped(page, page.applying(.deny))
    }

    static func undo(_ page: AgentsPage) -> Step {
        stepped(page, page.applying(.undo))
    }

    static func press(_ page: AgentsPage, _ key: HubDecisionKey) -> Step {
        stepped(page, page.applying(.key(key, command: false)))
    }

    static func hold(_ page: AgentsPage, action: HubDecisionAction, milliseconds: Int) -> Step {
        let began = page.applying(.holdBegan(action))
        let released = began.applying(.holdReleased(after: milliseconds))
        return stepped(page, released)
    }

    static func advance(_ page: AgentsPage, ticks: Int) -> Step {
        var current = page
        var sends: [AgentsPageHookVerdict] = []
        for _ in 0..<ticks {
            let next = current.applying(.tick)
            sends.append(contentsOf: appeared(from: current, to: next))
            current = next
        }
        return Step(page: current, sends: sends)
    }

    private static func stepped(_ before: AgentsPage, _ after: AgentsPage) -> Step {
        Step(page: after, sends: appeared(from: before, to: after))
    }

    /// Verdicts whose undo window closed between the two pages. Undo drops the pending action, so nothing here is sent.
    static func appeared(from: AgentsPage, to: AgentsPage) -> [AgentsPageHookVerdict] {
        let start = from.revision.executed.count
        guard to.revision.executed.count > start else { return [] }
        return to.revision.executed.dropFirst(start).map { execution in
            execution.action.isApproval ? .allow : .deny
        }
    }
}

/// Remembers the card id that opened the undo window. Allow is released only while that card is still current.
struct AgentsPageCardGate: Equatable, Sendable {
    var boundID: String?

    func step(before: AgentsPage, after: AgentsPage, currentCard: String?) -> (AgentsPageCardGate, [AgentsPageHookVerdict]) {
        var gate = self
        if before.revision.pending == nil, after.revision.pending != nil {
            gate.boundID = after.revision.pending?.requestIDs.first
        }
        let fresh = AgentsPageHook.appeared(from: before, to: after)
        if !fresh.isEmpty {
            let sends = gate.boundID != nil && gate.boundID == currentCard ? fresh : []
            gate.boundID = nil
            return (gate, sends)
        }
        if before.revision.pending != nil, after.revision.pending == nil {
            gate.boundID = nil
        }
        return (gate, [])
    }
}

/// The card on screen. Its id is the approval id, not the session id.
/// Destructive controls. The stub leaves the button empty: activate changes nothing, and only a long press holds.
enum AgentsPageDestructive {
    static func activate(_ page: AgentsPage) -> AgentsPageHook.Step {
        AgentsPageHook.Step(page: page, sends: [])
    }

    static func confirm(_ page: AgentsPage, action: HubDecisionAction) -> AgentsPageHook.Step {
        _ = action
        return AgentsPageHook.Step(page: page, sends: [])
    }

    static func keyboard(_ page: AgentsPage, key: HubDecisionKey) -> AgentsPageHook.Step {
        AgentsPageHook.press(page, key)
    }

    static func voiceOverConfirmLabel(_ action: HubDecisionAction) -> String {
        "Confirm \(action.title)"
    }
}

/// Hold progress. The stub never fills and always animates.
struct AgentsPageHoldFill: Equatable, Sendable {
    var fraction: Double
    var animates: Bool

    static func progress(heldMilliseconds: Int, reduceMotion: Bool) -> AgentsPageHoldFill {
        _ = (heldMilliseconds, reduceMotion)
        return AgentsPageHoldFill(fraction: 0, animates: true)
    }
}

/// The Undo chip. The stub has no countdown.
enum AgentsPageUndoChip {
    static func countdown(_ page: AgentsPage) -> String? {
        _ = page
        return nil
    }
}

enum AgentsPageLive {
    static func request(approvalID: String, sessionID: String?, tool: String, highRisk: Bool, command: String?) -> AgentsPageRequest {
        AgentsPageRequest(
            id: approvalID,
            sessionID: sessionID ?? approvalID,
            tool: tool,
            highRisk: highRisk,
            command: command,
            tier: highRisk ? .high : .low
        )
    }
}

// AGENTS-PAGE-MODEL-END
