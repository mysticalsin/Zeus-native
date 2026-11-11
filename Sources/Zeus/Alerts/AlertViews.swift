import AppKit
import SwiftUI
import ZeusCore

// MARK: Shared material

/// Dark glass used by every alert surface: a 1 px inner highlight and a very low accent glow.
/// Reduce Transparency swaps the material for a solid fill. No new colours: Theme tokens plus the per-app accent.
struct AlertGlass: ViewModifier {
    var accent: Color = Theme.accent
    var radius: CGFloat = 22
    var lifted = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(Theme.storm)
                } else {
                    shape.fill(Theme.storm.opacity(0.92)).background(.ultraThinMaterial, in: shape)
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.02)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: accent.opacity(0.14), radius: lifted ? 18 : 14, y: lifted ? 8 : 6)
    }
}

extension View {
    func alertGlass(accent: Color = Theme.accent, radius: CGFloat = 22, lifted: Bool = false) -> some View {
        modifier(AlertGlass(accent: accent, radius: radius, lifted: lifted))
    }
}

enum AlertStyle {
    static let stretch = Animation.spring(response: AlertMotion.stretchResponse, dampingFraction: AlertMotion.stretchDamping)
    static func crossfade(_ reduceMotion: Bool) -> Animation? { reduceMotion ? .easeInOut(duration: AlertMotion.reducedFade) : nil }
    static func transition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        // Back into the notch: shrinks toward its width and height, anchored at the top, content fading first.
        return .asymmetric(
            insertion: .identity,
            removal: .modifier(active: CollapseIntoNotch(progress: 1), identity: CollapseIntoNotch(progress: 0)))
    }
}

/// Collapse back into the notch silhouette (185 x 32 against the 360 x 64 capsule).
private struct CollapseIntoNotch: ViewModifier {
    var progress: Double
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1 - 0.49 * progress, y: 1 - 0.5 * progress, anchor: .top)
            .offset(y: -6 * progress)
            .opacity(1 - progress)
    }
}

// MARK: Incoming alert

/// One glass capsule. It starts as the notch silhouette, stretches down with a spring, then its content
/// appears in order (icon, title, body, 60 ms apart) and a luminous edge sweeps around it once.
/// Everything is a one-shot animation: after `AlertMotion.sweepDuration` the card owns no running animation.
struct AlertCapsule: View {
    static let width: CGFloat = 360
    static let restHeight: CGFloat = 64
    static let actionHeight: CGFloat = 104
    static let notchWidth: CGFloat = 185
    static let notchHeight: CGFloat = 32

    let item: AlertItem
    let depth: Int
    let hovered: Bool
    var hiddenCount = 0
    var actions = AlertActions()

    @State private var landed: Bool
    @State private var sweep: Double
    @State private var sweepDone: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(item: AlertItem, depth: Int, hovered: Bool, hiddenCount: Int = 0, startSettled: Bool = false, actions: AlertActions = AlertActions()) {
        self.item = item; self.depth = depth; self.hovered = hovered; self.hiddenCount = hiddenCount; self.actions = actions
        _landed = State(initialValue: startSettled)
        _sweep = State(initialValue: startSettled ? 1 : 0)
        _sweepDone = State(initialValue: startSettled)
    }

    private var isFront: Bool { depth == 0 }
    private var settledLook: Bool { landed || reduceMotion }
    private var showActions: Bool { hovered && isFront }
    private var accent: Color { AppIconCache.shared.entry(for: item.appID).accent }
    private var radius: CGFloat { settledLook ? 22 : 10 }
    private var height: CGFloat { settledLook ? (showActions ? Self.actionHeight : Self.restHeight) : Self.notchHeight }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                AlertAppIcon(bundleID: item.appID, size: 30)
                    .modifier(Stagger(index: 0, on: settledLook, reduceMotion: reduceMotion))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title.isEmpty ? item.appName : item.title)
                        .font(TopBarStyle.label(12.5, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                        .modifier(Stagger(index: 1, on: settledLook, reduceMotion: reduceMotion))
                    Text(item.body)
                        .font(TopBarStyle.label(11.5, .regular)).foregroundStyle(Theme.cloudSecondary).lineLimit(1)
                        .modifier(Stagger(index: 2, on: settledLook, reduceMotion: reduceMotion))
                }
                Spacer(minLength: 4)
                badges.modifier(Stagger(index: 2, on: settledLook, reduceMotion: reduceMotion))
            }
            if showActions {
                actionRow.transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, showActions ? 12 : 0)
        .frame(width: settledLook ? Self.width : Self.notchWidth, height: height, alignment: showActions ? .top : .center)
        .clipped()
        .alertGlass(accent: accent, radius: radius, lifted: showActions)
        .overlay { sweepLayer.allowsHitTesting(false) }
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .offset(y: showActions ? -2 : 0)
        .animation(reduceMotion ? AlertStyle.crossfade(true) : AlertStyle.stretch, value: settledLook)
        .animation(reduceMotion ? AlertStyle.crossfade(true) : AlertStyle.stretch, value: showActions)
        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
            if isFront, value.translation.height < -24 { actions.dismiss(item.id) }
        })
        .onAppear(perform: land)
        .allowsHitTesting(isFront)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(!isFront)
        .accessibilityLabel(item.spokenText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the app.")
        .accessibilityAction { actions.open(item.id) }
        .accessibilityAction(named: "Open") { actions.open(item.id) }
        .accessibilityAction(named: "Snooze for 10 minutes") { actions.snooze(item.id) }
        .accessibilityAction(named: "Clear") { actions.dismiss(item.id) }
        .accessibilityAction(.escape) { actions.dismiss(item.id) }
    }

    @ViewBuilder private var badges: some View {
        HStack(spacing: 4) {
            if item.count > 1 {
                Text("x\(item.count)").font(TopBarStyle.label(10, .semibold).monospacedDigit())
                    .foregroundStyle(Theme.cloudSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            if isFront, hiddenCount > 0 {
                Text("+\(hiddenCount)").font(TopBarStyle.label(10, .semibold).monospacedDigit())
                    .foregroundStyle(Theme.cloudPrimary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(accent.opacity(0.25)))
                    .accessibilityLabel("\(hiddenCount) more alerts")
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            if AlertAppGlyph.supportsReply(item.appID) {
                AlertActionButton(title: "Reply", symbol: "arrowshape.turn.up.left.fill", tint: accent) { actions.open(item.id) }
            }
            AlertActionButton(title: "Open", symbol: "arrow.up.forward.app.fill", tint: accent) { actions.open(item.id) }
            AlertActionButton(title: "Snooze", symbol: "moon.zzz.fill", tint: nil) { actions.snooze(item.id) }
            AlertActionButton(title: "Clear", symbol: "xmark", tint: nil) { actions.dismiss(item.id) }
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
        }
    }

    /// A conic gradient in the app accent rotates once around the card, masked to a 1.5 pt border and fading out.
    /// Rotation is the only thing animated, and the layer leaves the tree when it ends.
    @ViewBuilder private var sweepLayer: some View {
        if !sweepDone, !reduceMotion, depth == 0 {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            AngularGradient(colors: [accent.opacity(0), accent, Color.white.opacity(0.9), accent.opacity(0)], center: .center)
                .frame(width: Self.width * 2, height: Self.width * 2)
                .rotationEffect(.degrees(sweep * 360))
                .opacity(1 - 0.9 * sweep)
                .frame(width: Self.width, height: Self.restHeight)
                .mask { shape.strokeBorder(lineWidth: 1.5).frame(width: Self.width, height: Self.restHeight) }
        }
    }

    private func land() {
        guard !landed else { return }
        landed = true
        guard isFront, !reduceMotion else { sweepDone = true; return }
        withAnimation(.linear(duration: AlertMotion.sweepDuration).delay(0.05)) { sweep = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(AlertMotion.sweepDuration + 0.1))
            sweepDone = true
        }
    }
}

/// Content that fades and rises 3 pt after the shape lands, `index` steps of 60 ms apart.
private struct Stagger: ViewModifier {
    let index: Int
    let on: Bool
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : 3)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2).delay(AlertMotion.contentDelay(index: index)), value: on)
    }
}

struct AlertActions {
    var open: (String) -> Void = { _ in }
    var dismiss: (String) -> Void = { _ in }
    var snooze: (String) -> Void = { _ in }
}

struct AlertActionButton: View {
    let title: String
    let symbol: String
    let tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(TopBarStyle.label(10.5, .semibold))
                .foregroundStyle(tint == nil ? Theme.cloudSecondary : Theme.cloudPrimary)
                .padding(.horizontal, 9).frame(height: 24)
                .background(Capsule().fill((tint ?? Color.white).opacity(tint == nil ? 0.07 : 0.26)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

/// Up to three cards fan behind the newest one; the front card carries a "+N" chip for the rest.
struct AlertStackView: View {
    let stack: AlertStack
    var settled = false
    var actions = AlertActions()
    var onHover: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(stack.visible.enumerated()), id: \.element.id) { depth, item in
                AlertCapsule(item: item, depth: depth, hovered: stack.isHovered, hiddenCount: stack.hiddenCount,
                             startSettled: settled, actions: actions)
                    .scaleEffect(1 - 0.06 * CGFloat(depth), anchor: .top)
                    .offset(y: 8 * CGFloat(depth))
                    .opacity(1 - 0.45 * Double(depth))
                    .zIndex(Double(-depth))
                    .transition(AlertStyle.transition(reduceMotion: reduceMotion))
            }
        }
        .frame(width: AlertCapsule.width, alignment: .top)
        .animation(reduceMotion ? AlertStyle.crossfade(true) : AlertStyle.stretch, value: stack.visible.map(\.id))
        .onHover(perform: onHover)
    }
}
