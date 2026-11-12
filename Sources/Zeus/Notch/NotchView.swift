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

struct NotchView: View {
    let model: NotchModel
    /// The top bar (tabs, pages, closed wings). Nil keeps the classic agents-only notch.
    var topBar: TopBarModel? = nil
    /// The hardware notch (width 0 on Macs without one).
    let notch: CGSize
    /// A slim pill on a display without a notch, so the notch still has a place to glow and open from.
    var slimPill = false
    /// Snapshots and previews pin the drop; nil reads Settings > Appearance > Top bar position.
    var topOffsetOverride: Double? = nil

    /// How far the closed bar and the peek card sit below the top of the screen. The open panel stays
    /// flush with the top; the notch light, ticker and wings are part of the closed bar and move with it.
    private var topOffset: CGFloat {
        let resolved = topOffsetOverride.map(TopBarPosition.clamped) ?? TopBarPositionModel.shared.offset
        return CGFloat(TopBarPosition.applied(resolved: resolved, panelOpen: model.presentation == .panel))
    }

    private var barHeight: CGFloat { max(notch.height, 30) }
    private var hasNotch: Bool { notch.width > 0 }

    /// Idle and closed, the top bar is exactly the hardware notch (square top, no ears); open it
    /// flares 27.5 pt ears like Glance. The classic notch keeps its small shoulders.
    private var idleClosed: Bool {
        guard let topBar, hasNotch, model.presentation == .closed else { return false }
        return ClosedWings.kind(of: topBar) == .none
    }
    /// A stalled session the peek is talking about (no card of its own to compete with).
    private var stalledPeek: NotchModel.Session? {
        guard model.approval == nil, model.completion == nil, model.failure == nil,
              let session = model.peekSession, session.status == .stalled else { return nil }
        return session
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
    static let wingsSpring = Animation.spring(
        response: NotchClosedBodyLayout.wingsSpringResponse,
        dampingFraction: NotchClosedBodyLayout.wingsSpringDamping)

    /// The closed width while closed (nil otherwise), the trigger for `wingsSpring`.
    var closedWidthKey: CGFloat? {
        model.presentation == .closed ? size(for: .closed).width : nil
    }

    /// The pill on displays without a notch.
    static let pillSize = CGSize(width: 96, height: 9)

    private func size(for presentation: NotchModel.Presentation) -> CGSize {
        switch presentation {
        case .closed:
            if let topBar {
                let wingKind = ClosedWings.kind(of: topBar)
                let showWings = NotchClosedBodyLayout.showWings(
                    closedWingKindIsNone: wingKind == .none,
                    hasLights: !topBar.lights.isEmpty,
                    hasLiveActivity: topBar.hasLiveActivity)
                if showWings {
                    let extra = ClosedWings.extraWidth(for: topBar)
                    let base = hasNotch ? notch.width : 40
                    return CGSize(
                        width: NotchClosedBodyLayout.bodyWidth(
                            notchWidth: base, shoulder: shoulder, showWings: true,
                            extraWidth: extra, hasNotch: hasNotch, slimPill: slimPill),
                        height: barHeight)
                }
            }
            if hasNotch { return CGSize(width: notch.width + 2 * shoulder, height: notch.height) }
            return slimPill ? CGSize(width: Self.pillSize.width, height: Self.pillSize.height) : .zero
        case .peek:
            if let approval = model.approval {
                let wide = (approval.detail?.height ?? 0) > 0
                // 6 pt more than before for the avatar header row of the shared card grammar.
                return CGSize(width: max(notch.width + 2 * shoulder + 240, wide ? 520 : 440), height: barHeight + 98 + approval.extraHeight)
            }
            if model.completion != nil {
                return CGSize(width: max(notch.width + 2 * shoulder + 240, 460), height: barHeight + 10 + CompletionCardView.height)
            }
            if model.failure != nil || stalledPeek != nil {
                return CGSize(width: max(notch.width + 2 * shoulder + 240, 480), height: barHeight + 10 + AgentTroubleCard.height)
            }
            if let recap = model.recap {
                return CGSize(width: max(notch.width + 2 * shoulder + 240, 520), height: barHeight + 14 + WelcomeRecapCardView.height(for: recap))
            }
            return CGSize(width: (hasNotch ? notch.width : 120) + 2 * shoulder + 230, height: barHeight)
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
        return closed.width > 0 ? closed : CGSize(width: notch.width + 2 * shoulder, height: notch.height)
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
                        .padding(.top, barHeight + 6 + topOffset)
                        .transition(AlertStyle.transition(reduceMotion: Motion.reduced))
                }
            }
            .animation(Motion.reduced ? AlertStyle.crossfade(true) : AlertStyle.stretch, value: model.alerts.isEmpty)
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
        let glowing = glowsOutline(status: status)
        // Only tick while the halo is drawn and breathing, and only the outline layers (never the
        // content): an idle notch, or a closed one whose arms carry the glow, costs nothing.
        let breathing = !Motion.reduced && glowing
        let shape = NotchShape(shoulder: shoulder, earHeight: earHeight, bottomRadius: bottomRadius)
        let glanceOpen = topBar != nil && model.presentation == .panel
        return ZStack(alignment: .top) {
            TickingView(interval: 1 / 30, paused: !breathing) { context in
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
                        // Always the same black fill with Glance's open gradient over it: switching the
                        // fill between two style types cross-fades a new layer in at the final size
                        // instead of growing the body.
                        .fill(Color.black)
                        .overlay { shape.fill(Glass.notchPanelFill).opacity(glanceOpen ? 1 : 0) }
                        // Glance's soft drop shadow under the open body (parity/N4: alpha 0.19 at 2 pt
                        // below, 0.10 at 15 pt, gone by 50 pt; weaker at the sides).
                        .shadow(color: .black.opacity(glanceOpen ? Glass.notchShadow.opacity : 0),
                                radius: Glass.notchShadow.radius, y: Glass.notchShadow.y)
                        .shadow(color: glow.opacity(glowing ? 0.28 * breath : 0), radius: 9)
                        .shadow(color: glow.opacity(glowing ? 0.2 * breath : 0), radius: 3)
                        .shadow(color: Theme.bolt.opacity(glowing && halo == .storm ? 0.3 * breath : 0), radius: 26)
                    shape.stroke(glow.opacity(glowing ? 0.35 + 0.5 * breath : 0), lineWidth: 1.2)
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
        }
        .frame(width: size.width, height: size.height)
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
            if let topBar, model.presentation == .closed, hasNotch || slimPill || !topBar.lights.isEmpty {
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
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.approval?.id)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.sessions.count)
        .animation(Self.wingsSpring, value: topBar.map { ClosedWings.kind(of: $0) })
    }

    @ViewBuilder
    private var content: some View {
        switch model.presentation {
        case .closed:
            if let topBar {
                ClosedWings(topBar: topBar).frame(height: barHeight)
            }
        case .peek:
            VStack(spacing: 10) {
                peekBar
                if let approval = model.approval {
                    ApprovalBody(approval: approval, compact: true)
                        .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.12)))
                } else if let completion = model.completion {
                    CompletionCardView(completion: completion) { model.completion = nil }
                        .transition(.opacity.combined(with: .offset(y: -4)).animation(.spring(response: 0.34, dampingFraction: 0.82).delay(0.1)))
                } else if let failure = model.failure {
                    AgentTroubleCard(kind: .failed, sessionID: failure.sessionID, agent: failure.agent, project: failure.project, reason: failure.reason) {
                        NotchControllerBridge.dismissFailure()
                    }
                    .transition(.opacity.combined(with: .offset(y: -4)).animation(.spring(response: 0.34, dampingFraction: 0.82).delay(0.1)))
                } else if let session = stalledPeek {
                    AgentTroubleCard(kind: .stalled, sessionID: session.id, agent: session.agent, project: session.project,
                                     reason: session.reason ?? "No activity for a while") {
                        model.peekSessionID = nil
                        NotchControllerBridge.closePeek()
                    }
                    .transition(.opacity.combined(with: .offset(y: -4)).animation(.spring(response: 0.34, dampingFraction: 0.82).delay(0.1)))
                } else if let edit = model.selectionEdit {
                    SelectionEditBody(edit: edit)
                        .padding(.horizontal, 16)
                } else if let preview = model.workBehind, preview.streaming {
                    WorkBehindBody(preview: preview)
                        .padding(.horizontal, 16)
                } else if let recap = model.recap {
                    WelcomeRecapCardView(recap: recap) { model.recap = nil; NotchControllerBridge.closePeek() }
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .offset(y: -4)).animation(.spring(response: 0.34, dampingFraction: 0.82).delay(0.1)))
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
            BoltShape()
                .fill(status.color)
                .frame(width: 11, height: 13)
                .shadow(color: status.color.opacity(0.9), radius: 4)
            Text(model.approval?.agent ?? model.peekSession?.agent ?? "Zeus")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.cloudPrimary)
                .lineLimit(1)
            Spacer(minLength: hasNotch ? notch.width + 8 : 12)
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
    let edit: SelectionEdit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(edit.diff) { line in
                Text(prefix(line.kind) + line.text)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(color(line.kind))
                    .lineLimit(2)
            }
            HStack {
                Spacer()
                NotchButton(title: "Accept", tint: Theme.leaf, filled: true) { HandsHUD.shared.accept() }
            }
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
                BoltShape().fill(Theme.bolt).frame(width: 11, height: 13)
                    .shadow(color: Theme.bolt.opacity(0.8), radius: 4)
                Text("Zeus")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.cloudPrimary)
                Spacer(minLength: notchWidth + 8)
                Text("\(model.sessions.count) agent\(model.sessions.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cloudSecondary)
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
            // Glance (parity/N4): brightest under the fourth card's left edge, about 77 % across,
            // and it never reaches the tab row (y 37 stays black edge to edge).
            RadialGradient(colors: [contentGlow.opacity(0.35), .clear], center: UnitPoint(x: 0.77, y: 1.0),
                           startRadius: 10, endRadius: 170)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
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

    /// Content tint: playing music paints a violet/album glow (Codex review 1 live pair); idle Home
    /// keeps the copper behind Calendar from TOPBAR-SPEC §2.
    private var contentGlow: Color {
        if let playing = topBar.nowPlaying {
            return ArtworkStore.shared.tint(for: playing, saturation: 0.45, brightness: 0.55, scale: 0.8)
        }
        return GlanceTint.glow
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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.isEnabled) private var isEnabled
    private let reduceMotionOverride: Bool?

    init(reduceMotion: Bool? = nil) { reduceMotionOverride = reduceMotion }

    func makeBody(configuration: Configuration) -> some View {
        let reduceMotion = reduceMotionOverride ?? systemReduceMotion
        return configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? Motion.pressedScale : 1)
            .animation(Motion.feedback(reduceMotion: reduceMotion), value: configuration.isPressed)
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
