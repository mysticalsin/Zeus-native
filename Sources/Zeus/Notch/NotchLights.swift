import SwiftUI
import ZeusCore

/// One arm of the closed notch, drawn in a canvas as wide as the screen with the notch centred at
/// the top: from the middle of the bottom lip, round the corner, up the side, over the shoulder,
/// then out along the top edge. The right arm is the mirror image.
struct NotchArm: Shape {
    var bodyWidth: CGFloat
    var bodyHeight: CGFloat
    var shoulder: CGFloat = 8
    var bottomRadius: CGFloat = 10
    var arm: CGFloat

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, left = cx - bodyWidth / 2, s = shoulder
        let r = min(bottomRadius, (bodyHeight - s) / 2)
        let top: CGFloat = 0.8
        var p = Path()
        p.move(to: CGPoint(x: cx, y: bodyHeight))
        p.addLine(to: CGPoint(x: left + s + r, y: bodyHeight))
        p.addQuadCurve(to: CGPoint(x: left + s, y: bodyHeight - r), control: CGPoint(x: left + s, y: bodyHeight))
        p.addLine(to: CGPoint(x: left + s, y: s))
        p.addQuadCurve(to: CGPoint(x: left, y: top), control: CGPoint(x: left + s, y: top))
        p.addLine(to: CGPoint(x: left - arm, y: top))
        return p
    }
}

extension NotchLightTint {
    var color: Color {
        switch self {
        case .white: .white
        case .amber: Color(red: 1, green: 0.72, blue: 0.2)
        case .mint: Color(red: 0.45, green: 0.95, blue: 0.78)
        case .green: Color(red: 0.3, green: 0.9, blue: 0.45)
        case .blue: Theme.accent
        case .cyan: Color(red: 0.25, green: 0.88, blue: 1)
        case .purple: Color(red: 0.66, green: 0.45, blue: 1)
        case .sky: Theme.sky
        case .ember: Theme.ember
        case .leaf: Theme.leaf
        }
    }
}

/// Everything that lights the closed notch: the agent halo on the arms, one-shot effects
/// (copy, Caps Lock, Shift, battery, drops, reminders, events, shortcuts, entrances) and the
/// steady gauges (timer, music wave, music progress, drag crests, mic glow).
struct NotchLights: View {
    let topBar: TopBarModel
    let status: NotchModel.Status
    /// The closed black shape's size (wings included).
    let body_: CGSize
    let shoulder: CGFloat

    /// Frame interval of the lights; shares the mascot's 24 fps grid (see `TickClock`).
    static let frameInterval: TimeInterval = 1.0 / LivingAvatar.busyFPS

    private var store: SettingsStore { SettingsStore.shared }
    private var arm: CGFloat { CGFloat(NotchLightMath.armLength(store.string("halo.armWidth"))) }
    private var thickness: CGFloat { CGFloat(max(store.double("halo.thickness"), 100)) / 100 }
    private var shoulderFraction: Double {
        NotchLightMath.shoulderFraction(notchHalfWidth: body_.width / 2, notchHeight: body_.height, arm: Double(arm))
    }
    private var agentGlowing: Bool { status != .idle && topBar.haloStyle != .off }
    private var musicPlaying: Bool { topBar.nowPlaying?.isPlaying == true }

    private var anythingLit: Bool {
        !topBar.lights.isEmpty || agentGlowing || topBar.isDraggingFiles || topBar.micListening
            || (topBar.focus.phase != .idle && store.bool("lights.timer"))
            || (musicPlaying && (topBar.liveMusicWings || store.bool("lights.musicProgress")))
    }

    var body: some View {
        if body_.width > 0, anythingLit {
            // 24 fps, the mascot's busy rate, so both redraw in the same run-loop turn: soft light looks the
            // same as 120 Hz ProMotion at a fifth of the work.
            TickingView(interval: Motion.reduced ? 0.5 : NotchLights.frameInterval) { context in
                canvas(at: context.date)
            }
            .allowsHitTesting(false)
        }
    }

    private func canvas(at now: Date) -> some View {
        let t = now.timeIntervalSinceReferenceDate
        let s = shoulderFraction
        return ZStack(alignment: .top) {
            // Steady layers first, effects on top.
            if agentGlowing { agentHalo(t) }
            if topBar.focus.phase != .idle, store.bool("lights.timer") {
                let fraction = 1 - topBar.focus.progress(at: now)
                let tint: NotchLightTint = topBar.focus.phase == .focus ? .amber : .mint
                let breathe = topBar.focus.isPaused ? 0.5 + 0.3 * sin(t * 2) : 1
                arms([NotchLightMath.timerGauge(remainingFraction: fraction)], tint.color, opacity: breathe)
            }
            if musicPlaying, !agentGlowing {
                let tint = ArtworkStore.shared.tint(for: topBar.nowPlaying, saturation: 0.5, brightness: 1)
                if topBar.liveMusicWings, !Motion.reduced {
                    let live = store.bool("lights.liveSpectrum") && AudioSpectrumService.shared.running
                    arms([live ? NotchLightMath.musicWave(time: t, level: Double(AudioSpectrumService.shared.overall) * 1.4) : NotchLightMath.musicWave(time: t)], tint, opacity: 0.8)
                }
                if store.bool("lights.musicProgress"), let playing = topBar.nowPlaying, playing.duration > 0 {
                    let elapsed = playing.position + now.timeIntervalSince(playing.positionAt)
                    let left = max(0, 1 - elapsed / playing.duration)
                    arms([.init(from: 0, to: s * left, opacity: 0.45)], tint, opacity: 1)
                }
            }
            if topBar.isDraggingFiles {
                arms(NotchLightMath.dragCrests(time: t, shoulder: s), NotchLightTint.amber.color, opacity: 1)
            }
            if topBar.micListening, store.bool("lights.micGlow") {
                let level = 0.35 + 0.65 * min(1, topBar.micLevel * 1.6)
                arms([.init(from: 0, to: 1, opacity: level)], NotchLightTint.purple.color, opacity: 1)
            }
            ForEach(topBar.lights) { light in
                let p = now.timeIntervalSince(light.startedAt) / light.duration
                effect(light.kind, progress: p, time: t)
            }
        }
    }

    @ViewBuilder
    private func effect(_ kind: NotchLightKind, progress p: Double, time t: Double) -> some View {
        let segments = NotchLightMath.segments(kind, progress: p, shoulder: shoulderFraction)
        switch kind {
        case .edgeWave: EmptyView() // a separate click-through overlay (EdgeWave.swift)
        case .entrance(let style, let tint): entrance(style, tint: tint, progress: p, time: t)
        default: arms(segments, color(for: kind), opacity: 1)
        }
    }

    /// An entrance: its own choreography, drawn by the shared halo renderer.
    private func entrance(_ style: HaloEntrance, tint: NotchLightTint, progress p: Double, time t: Double) -> some View {
        let intensity = max(store.double("halo.intensity"), 50) / 100
        let white = WallpaperLuminance.shared.whiteAmount(enabled: store.bool("halo.wallpaper"))
        let layers: [EntranceLayer]
        let hue: Double
        if Motion.reduced {
            // No travelling light: the whole outline fades in and out together (this also keeps Strobe from flashing).
            layers = [.init([.init(from: 0, to: 1, opacity: sin(max(0, min(1, p)) * .pi) * 0.8)])]
            hue = 0
        } else {
            let frame = NotchLightMath.entranceFrame(style, progress: p, shoulder: shoulderFraction)
            layers = frame.layers
            hue = frame.hueShift
        }
        return HaloArmsCanvas(body_: body_, shoulder: shoulder, arm: arm, layers: layers.map { layer in
            var paint = HaloPaint(color: tint.color, opacity: min(1, intensity), white: min(1, layer.white + white * 0.5), hueShift: hue,
                                  line: 1.6 * thickness * CGFloat(layer.width), bloom: CGFloat(intensity) * CGFloat(layer.bloom), time: t)
            paint.reduceMotion = Motion.reduced
            return HaloArmsLayer(segments: layer.segments, style: .classic, paint: paint)
        })
    }

    private func color(for kind: NotchLightKind) -> Color {
        switch kind {
        case .copySweep, .shiftCrest, .shortcut: .white
        case .capsLock(let on): on ? Theme.bolt : .white
        case .battery: NotchLightTint.green.color
        case .landed(let airDrop): (airDrop ? NotchLightTint.blue : .amber).color
        case .reminderPinned: NotchLightTint.blue.color
        case .eventRibbon: NotchLightTint.cyan.color
        case .entrance(_, let tint), .edgeWave(let tint): tint.color
        case .hudLevel(let kind, _, _, _, _):
            switch kind {
            case .volume: Theme.bolt
            case .brightness: Theme.sky
            case .keyboardBacklight: NotchLightTint.purple.color
            }
        }
    }

    /// The agent's colour along both arms, in the chosen halo style.
    private func agentHalo(_ t: Double) -> some View {
        let breath = Motion.reduced ? 0.75 : 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 2 * .pi / (status == .needsYou ? 1.8 : 2.6)))
        let style = topBar.haloStyle
        var paint = HaloPaint(color: status.color, white: WallpaperLuminance.shared.whiteAmount(enabled: store.bool("halo.wallpaper")),
                              line: 1.6 * thickness, time: t)
        paint.reduceMotion = Motion.reduced
        return HaloArmsCanvas(body_: body_, shoulder: shoulder, arm: arm,
                       layers: [HaloArmsLayer(segments: [LightSegment(from: 0, to: 1, opacity: breath)], style: style, paint: paint)])
    }

    /// Draws lit segments on the arms with a soft glow.
    private func arms(_ segments: [LightSegment], _ color: Color, opacity: Double, bloom: CGFloat = 1, dash: [CGFloat] = []) -> some View {
        let line = 1.6 * thickness
        return ZStack(alignment: .top) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.opacity > 0.01, segment.to > segment.from {
                    if segment.side <= 0 { stroke(segment, color, opacity, line, bloom, dash) }
                    if segment.side >= 0 { stroke(segment, color, opacity, line, bloom, dash).scaleEffect(x: -1, y: 1) }
                }
            }
        }
    }

    private func stroke(_ segment: LightSegment, _ color: Color, _ opacity: Double, _ line: CGFloat, _ bloom: CGFloat, _ dash: [CGFloat]) -> some View {
        let o = segment.opacity * opacity
        return NotchArm(bodyWidth: body_.width, bodyHeight: body_.height, shoulder: shoulder, arm: arm)
            .trim(from: segment.from, to: segment.to)
            .stroke(color.opacity(o), style: StrokeStyle(lineWidth: line, lineCap: .round, dash: dash))
            .shadow(color: color.opacity(o * 0.9), radius: 3 * thickness * bloom)
            .shadow(color: color.opacity(o * 0.55), radius: 10 * thickness * bloom)
    }
}

/// One style, one stretch of arm, one paint.
struct HaloArmsLayer {
    var segments: [LightSegment]
    var style: HaloStyle
    var paint: HaloPaint
}

/// Both arms of the closed notch in one canvas, drawn by the renderer the Settings and welcome previews share.
struct HaloArmsCanvas: View {
    let body_: CGSize
    let shoulder: CGFloat
    let arm: CGFloat
    let layers: [HaloArmsLayer]

    var body: some View {
        let pad: CGFloat = 80
        Canvas { ctx, size in
            let outline = Polyline(path: NotchArm(bodyWidth: body_.width, bodyHeight: body_.height, shoulder: shoulder, arm: arm)
                .path(in: CGRect(origin: .zero, size: size)))
            for layer in layers {
                for segment in layer.segments where segment.opacity > 0.01 && segment.to > segment.from {
                    var paint = layer.paint
                    paint.opacity *= segment.opacity
                    let lit = outline.slice(from: segment.from, to: segment.to)
                    if segment.side <= 0 { HaloRenderer.draw(layer.style, line: lit, in: &ctx, paint: paint) }
                    if segment.side >= 0 {
                        var mirrored = ctx
                        mirrored.translateBy(x: size.width, y: 0)
                        mirrored.scaleBy(x: -1, y: 1)
                        HaloRenderer.draw(layer.style, line: lit, in: &mirrored, paint: paint)
                    }
                }
            }
        }
        .frame(width: body_.width + 2 * (arm + pad), height: body_.height + pad)
    }
}
